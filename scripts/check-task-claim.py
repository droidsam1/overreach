#!/usr/bin/env python3
"""Detect two agents working on the same task.

Every PR body starts with `Task: <link to the priorities item, design-doc task anchor or issue>` (or
`Task: none — <reason>` for work outside the backlog). This script reads the claim of the branch's PR and fails when
an older open PR, or a PR merged since this branch started, claims the same task: the oldest open claim keeps it, so
two agents that raced resolve it without asking. Locally it fails when the branch has changes and no claiming PR, and
lists what landed on origin/main meanwhile and which design docs it shares with this branch.

Usage:
  scripts/check-task-claim.py          # local: the open PR of the current branch (gh needed; skips without it)
  scripts/check-task-claim.py --ci     # CI on pull_request: reads the PR from GITHUB_EVENT_PATH, needs GH_TOKEN
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TASK_LINE = re.compile(r"^\s*Task:\s*(.*?)\s*$", re.M | re.I)
LINK = re.compile(r"\]\(([^)]+)\)|(https?://\S+|[\w./-]+\.md#[\w-]+|#\d+)")
NO_TASK = re.compile(r"^none\b", re.I)


def task_key(body):
    """The claimed task as a comparable key, "none" for work outside the backlog, or None without a Task line."""
    match = TASK_LINE.search(body or "")
    if not match or not match.group(1) or match.group(1).startswith("<!--"):
        return None
    value = match.group(1)
    if NO_TASK.match(value):
        return "none"
    link = LINK.search(value)
    target = (link.group(1) or link.group(2)) if link else value
    target = re.sub(r"^https://github\.com/[^/]+/[^/]+/(?:blob/[^/]+/)?", "", target)
    target = re.sub(r"^(?:\.\./|\./)*(?:docs/)?", "", target)
    target = re.sub(r"^(?:issues|pull)/(\d+)$", r"#\1", target)
    return target.strip().lower()


def gh(path, *, paginate=False):
    command = ["gh", "api", path]
    if paginate:
        command += ["--paginate", "--slurp"]
    output = subprocess.run(command, cwd=ROOT, capture_output=True, encoding="utf-8")
    if output.returncode != 0:
        raise RuntimeError(output.stderr.strip() or f"gh api {path} failed")
    response = json.loads(output.stdout)
    if paginate:
        return [entry for page in response for entry in page]
    return response


def repository():
    url = subprocess.check_output(["git", "remote", "get-url", "origin"], cwd=ROOT, text=True).strip()
    match = re.search(r"github\.com[:/]([^/]+)/([^/.]+)", url)
    if not match:
        raise RuntimeError(f"origin is not a GitHub repository: {url}")
    return match.group(1), match.group(2)


def timestamp(value):
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def claim_order(pull):
    """Who claimed first: the earlier PR, then the lower number."""
    return pull["created_at"], pull["number"]


def conflicts(owner, repo, pull, key, since):
    """Claims of the same task: (older open PRs and PRs merged after `since`, newer open PRs)."""
    number = pull["number"]
    blocking, later = [], []
    for other in gh(f"repos/{owner}/{repo}/pulls?state=open&per_page=100", paginate=True):
        if other["number"] != number and task_key(other.get("body")) == key:
            older = claim_order(other) < claim_order(pull)
            (blocking if older else later).append(f"#{other['number']} (open) {other['title']}")
    for other in gh(f"repos/{owner}/{repo}/pulls?state=closed&sort=updated&direction=desc&per_page=50"):
        merged = other.get("merged_at")
        if other["number"] != number and merged and timestamp(merged) > since and task_key(other.get("body")) == key:
            blocking.append(f"#{other['number']} (merged {merged[:16]}) {other['title']}")
    return blocking, later


def report(number, key, found, later=()):
    if key is None:
        print(f"FAIL task-claim - PR #{number} has no `Task:` line. Start the description with "
              "`Task: <link to the task anchor or issue>`, or `Task: none — <reason>`.")
        return 1
    if found:
        print(f"FAIL task-claim - {key} was claimed first by " + "; ".join(found)
              + ". Close this PR and run `scripts/claim-task.py --next`, or ask the user.")
        return 1
    if later:
        print(f"WARN task-claim - newer PRs also claim {key}: " + "; ".join(later)
              + ". This PR keeps the task; their check fails until they close.")
    if key == "none":
        print(f"PASS task-claim - #{number} is outside the backlog (Task: none).")
    else:
        print(f"PASS task-claim - #{number} claims {key}; no other PR does.")
    return 0


def landed_meanwhile():
    """Commits that reached origin/main since this branch started, and the design docs both sides touched."""
    subprocess.run(["git", "fetch", "--quiet", "origin", "main"], cwd=ROOT, capture_output=True)
    base = subprocess.run(["git", "merge-base", "HEAD", "origin/main"], cwd=ROOT, capture_output=True, text=True)
    if base.returncode != 0:
        return
    base = base.stdout.strip()
    subjects = subprocess.check_output(["git", "log", "--format=%s", f"{base}..origin/main"], cwd=ROOT, text=True)
    if not subjects.strip():
        return

    def docs(range_):
        names = subprocess.check_output(["git", "diff", "--name-only", range_, "--", "docs/design"], cwd=ROOT, text=True)
        return set(names.split())

    shared = docs(f"{base}..origin/main") & docs(f"{base}...HEAD")
    print("WARN origin/main moved since this branch started: " + "; ".join(subjects.strip().splitlines()))
    if shared:
        print("WARN both sides changed " + ", ".join(sorted(shared)) + ": check the task is still open.")


def unclaimed(branch):
    """A branch without a claiming PR: fine while empty, a failure once it holds work."""
    committed = subprocess.run(["git", "diff", "--quiet", "origin/main...HEAD"], cwd=ROOT).returncode != 0
    uncommitted = subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True).strip()
    if branch not in ("", "main") and (committed or uncommitted):
        print("FAIL task-claim - this branch has changes but no PR claims its task. Run "
              "`scripts/claim-task.py --here <task link>` (or `--here --none \"<reason>\"`) before going on.")
        landed_meanwhile()
        return 1
    print("WARN task-claim - no open PR for this branch. Claim the task before writing code: "
          "`scripts/claim-task.py --next`.")
    landed_meanwhile()
    return 0


def local():
    if not shutil.which("gh"):
        print("SKIP task-claim - gh is not installed.")
        return 0
    try:
        owner, repo = repository()
        branch = subprocess.check_output(["git", "branch", "--show-current"], cwd=ROOT, text=True).strip()
        pulls = gh(f"repos/{owner}/{repo}/pulls?state=open&head={owner}:{branch}")
        if not pulls:
            return unclaimed(branch)
        pull = pulls[0]
        base = subprocess.check_output(["git", "merge-base", "HEAD", "origin/main"], cwd=ROOT, text=True).strip()
        since = timestamp(subprocess.check_output(["git", "show", "-s", "--format=%cI", base], cwd=ROOT, text=True)
                          .strip())
        key = task_key(pull.get("body"))
        found = ([], []) if key in (None, "none") else conflicts(owner, repo, pull, key, since)
        status = report(pull["number"], key, *found)
    except (RuntimeError, subprocess.CalledProcessError, OSError) as error:
        print(f"SKIP task-claim - {error}")
        return 0
    landed_meanwhile()
    return status


def ci():
    event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
    pull = event.get("pull_request")
    if not pull:
        print("SKIP task-claim - not a pull request.")
        return 0
    owner, repo = os.environ["GITHUB_REPOSITORY"].split("/")
    number = pull["number"]
    current = gh(f"repos/{owner}/{repo}/pulls/{number}")
    key = task_key(current.get("body"))
    since = timestamp(gh(f"repos/{owner}/{repo}/commits/{pull['base']['sha']}")["commit"]["committer"]["date"])
    found = ([], []) if key in (None, "none") else conflicts(owner, repo, current, key, since)
    return report(number, key, *found)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--ci", action="store_true", help="read the pull request from the GitHub Actions event")
    sys.exit(ci() if parser.parse_args().ci else local())
