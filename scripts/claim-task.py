#!/usr/bin/env python3
"""Claim a task before writing code: pick it, open the claiming draft PR and confirm nobody claimed it first.

The window between reading docs/priorities.md and opening the claiming PR is where two agents pick the same task.
This script keeps it to seconds and resolves the race the same way for everyone: the older PR keeps the task
(scripts/check-task-claim.py applies the same rule in CI).

Usage:
  scripts/claim-task.py --next                 # first unclaimed task in "Ready to implement"
  scripts/claim-task.py <issue URL | #N | docs/<file>.md#anchor>
  scripts/claim-task.py --none "<reason>"      # work outside the backlog (a user request)
Options:
  --here            claim the current branch and its commits instead of a new branch from origin/main
  --branch NAME     branch name (default: task/<task>)
  --title TITLE     PR title (default: "chore(claim): <task>"; rename it when the work is ready)
  --trailer TEXT    line appended to the claim commit message (repeatable), e.g. a Co-Authored-By line
  --wait SECONDS    pause before the final check, so a PR opened at the same moment is visible (default 20)
  --dry-run         print the task --next would claim and change nothing

Prints `CLAIMED <task> #<PR> <branch>` and the priorities item, or exits 1 when nothing could be claimed.
"""
import argparse
import importlib.util
import json
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
_spec = importlib.util.spec_from_file_location("check_task_claim", ROOT / "scripts/check-task-claim.py")
claims = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(claims)

ITEM = re.compile(r"^(?:\d+\.|-)\s", re.M)
TASK = re.compile(r"\]\(((?:https://github\.com/[^)]+/issues/\d+)|(?:[\w./-]+\.md#[\w-]+))\)")
# "once #12 is done", "once #12 and #13 are done", "once #12, #13 and #14 are done"
BLOCKED_BY = re.compile(r"#(\d+)(?=(?:,?\s*(?:and\s+)?#\d+)*\s+(?:is|are)\s+done)", re.I)
MAX_ATTEMPTS = 5


def git(*args, check=True):
    result = subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True)
    if check and result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or f"git {' '.join(args)} failed")
    return result.stdout.strip()


def gh_write(method, path, fields):
    """REST only: GraphQL (`gh pr …`) is refused in some agent sandboxes."""
    args = ["gh", "api", "-X", method, path]
    for name, value in fields.items():
        if isinstance(value, bool):
            args += ["-F", f"{name}={str(value).lower()}"]
        else:
            args += ["-f", f"{name}={value}"]
    result = subprocess.run(args, cwd=ROOT, capture_output=True, text=True)
    if result.returncode != 0:
        # gh prints the API's reason (for example the validation errors of a 422) on stdout.
        detail = " ".join(part.strip() for part in (result.stderr, result.stdout) if part.strip())
        raise RuntimeError(f"{detail or f'gh api {path} failed'}\nIf gh cannot open the PR here, open it as a draft "
                           "with the GitHub tool; its body starts with `Task: <link>`.")
    return json.loads(result.stdout or "{}")


def ready_items():
    """The tasks of each "Ready to implement" item on origin/main, in order, with the item's text."""
    text = git("show", "origin/main:docs/priorities.md")
    section, _, rest = text.split("## Ready to implement", 1)[-1].partition("\n## ")
    # A task the later sections also list (e.g. "Needs a person or an iPhone") is mentioned, not ready for an agent.
    elsewhere = {match.group(1) for match in TASK.finditer(rest)}
    starts = [match.start() for match in ITEM.finditer(section)] + [len(section)]
    items = []
    for start, end in zip(starts, starts[1:]):
        body = section[start:end].strip()
        tasks = []
        for match in TASK.finditer(body):
            if match.group(1) in elsewhere:
                continue
            following = body[match.end():].split("](", 1)[0]
            tasks.append((match.group(1), BLOCKED_BY.findall(following)))
        items.append((body, tasks))
    return items


def issue_state(owner, repo, number, cache={}):
    """"open", "closed" or "parent" (an issue with sub-issues is an umbrella, not a task)."""
    if number not in cache:
        issue = claims.gh(f"repos/{owner}/{repo}/issues/{number}")
        state = issue["state"]
        if state == "open" and issue.get("sub_issues_summary", {}).get("total", 0) > 0:
            state = "parent"
        cache[number] = state
    return cache[number]


def next_task(owner, repo, skip):
    """The first task of "Ready to implement" that is open, unblocked and unclaimed."""
    claimed = {claims.task_key(pull.get("body")) for pull in open_pulls(owner, repo)}
    for body, tasks in ready_items():
        keys = [(link, claims.task_key(f"Task: {link}"), blockers) for link, blockers in tasks]
        one_at_a_time = "one task at a time" in body.lower()
        if one_at_a_time and any(key in claimed for _, key, _ in keys):
            continue
        for link, key, blockers in keys:
            number = key[1:] if key.startswith("#") else None
            if number and issue_state(owner, repo, number) != "open":
                continue
            if any(issue_state(owner, repo, blocker) == "open" for blocker in blockers):
                continue
            if key in claimed or key in skip:
                if one_at_a_time:
                    break
                continue
            return link, key, body
    return None


def slugify(text):
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")[:40] or "work"


def open_pulls(owner, repo):
    return claims.gh(f"repos/{owner}/{repo}/pulls?state=open&per_page=100")


def claim(owner, repo, link, key, args, slug):
    """Opens the claiming draft PR and returns it. The branch starts from origin/main unless --here."""
    if args.here:
        branch = git("branch", "--show-current")
        if branch in ("", "main"):
            raise RuntimeError("--here needs a feature branch, not main or a detached HEAD.")
    else:
        branch = args.branch or "task/" + slug
        git("checkout", "-B", branch, "origin/main")
        message = f"chore(claim): {slug}"
        if args.trailer:
            message += "\n\n" + "\n".join(args.trailer)
        git("commit", "--allow-empty", "-m", message)
    git("-c", "push.negotiate=true", "push", "-u", "origin", branch)
    body = f"Task: {link}\n\nClaimed with `scripts/claim-task.py`. Work in progress."
    return gh_write("POST", f"repos/{owner}/{repo}/pulls", {
        "title": args.title or f"chore(claim): {slug}", "head": branch, "base": "main", "body": body, "draft": True,
    }) | {"branch": branch}


def first_claim(owner, repo, pull, key):
    """An older open PR claiming the same task, or None when this PR is the first."""
    mine = (pull["created_at"], pull["number"])
    older = [other for other in open_pulls(owner, repo)
             if other["number"] != pull["number"] and claims.task_key(other.get("body")) == key
             and (other["created_at"], other["number"]) < mine]
    return min(older, key=lambda other: (other["created_at"], other["number"])) if older else None


def withdraw(owner, repo, pull, winner):
    gh_write("PATCH", f"repos/{owner}/{repo}/pulls/{pull['number']}", {"state": "closed"})
    gh_write("POST", f"repos/{owner}/{repo}/issues/{pull['number']}/comments", {
        "body": f"Withdrawn: #{winner['number']} claimed the same task first.",
    })


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    target = parser.add_mutually_exclusive_group(required=True)
    target.add_argument("task", nargs="?", help="issue URL, #N or docs/<file>.md#anchor")
    target.add_argument("--next", action="store_true", help="the first unclaimed task in docs/priorities.md")
    target.add_argument("--none", metavar="REASON", help="work outside the backlog")
    parser.add_argument("--here", action="store_true")
    parser.add_argument("--branch")
    parser.add_argument("--title")
    parser.add_argument("--trailer", action="append", default=[])
    parser.add_argument("--wait", type=float, default=20)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    try:
        owner, repo = claims.repository()
        git("fetch", "--quiet", "origin", "main")
        if args.none:
            pull = claim(owner, repo, f"none — {args.none}", "none", args, slugify(args.none))
            print(f"CLAIMED none #{pull['number']} {pull['branch']}")
            return 0
        skip = set()
        for _ in range(MAX_ATTEMPTS):
            item = ""
            if args.next:
                found = next_task(owner, repo, skip)
                if not found:
                    print("NONE - every ready task is claimed, blocked or closed. Ask the user what to do next.")
                    return 1
                link, key, item = found
                if args.dry_run:
                    print(f"NEXT {key}\n{item}")
                    return 0
            else:
                link = args.task
                key = claims.task_key(f"Task: {link}")
                taken = [pull for pull in open_pulls(owner, repo) if claims.task_key(pull.get("body")) == key]
                if taken:
                    print(f"TAKEN - #{taken[0]['number']} already claims {key}. Choose another task.")
                    return 1
            pull = claim(owner, repo, link, key, args, slugify(key))
            time.sleep(args.wait)
            winner = first_claim(owner, repo, pull, key)
            if winner is None:
                print(f"CLAIMED {key} #{pull['number']} {pull['branch']}")
                if item:
                    print(item)
                return 0
            withdraw(owner, repo, pull, winner)
            print(f"LOST - #{winner['number']} claimed {key} first; #{pull['number']} is closed.")
            if not args.next or args.here:
                return 1
            skip.add(key)
        print("NONE - too many races in a row. Ask the user.")
        return 1
    except (RuntimeError, OSError) as error:
        print(f"FAIL claim - {error}")
        return 1


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())
