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
  --dry-run         show the task --next would claim and why earlier tasks were skipped

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

from priority_queue import ready_issues

ROOT = Path(__file__).resolve().parent.parent
_spec = importlib.util.spec_from_file_location("check_task_claim", ROOT / "scripts/check-task-claim.py")
claims = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(claims)

MAX_ATTEMPTS = 5


def git(*args, check=True):
    result = subprocess.run(["git", *args], cwd=ROOT, capture_output=True, encoding="utf-8")
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
    result = subprocess.run(args, cwd=ROOT, capture_output=True, encoding="utf-8")
    if result.returncode != 0:
        # gh prints the API's reason (for example the validation errors of a 422) on stdout.
        detail = " ".join(part.strip() for part in (result.stderr, result.stdout) if part.strip())
        raise RuntimeError(f"{detail or f'gh api {path} failed'}\nIf gh cannot open the PR here, open it as a draft "
                           "with the GitHub tool; its body starts with `Task: <link>`.")
    return json.loads(result.stdout or "{}")


def next_task(owner, repo, priorities, skip):
    """Return the first available issue and the reasons earlier rows were skipped."""
    claimed = {}
    for pull in sorted(open_pulls(owner, repo), key=claims.claim_order):
        claimed.setdefault(claims.task_key(pull.get("body")), pull["number"])

    skipped = []
    for task in priorities:
        key = f"#{task.number}"
        if key in claimed:
            reason = f"claimed by PR #{claimed[key]}"
        elif key in skip:
            reason = "already attempted this run"
        else:
            endpoint = f"repos/{owner}/{repo}/issues/{task.number}"
            issue = claims.gh(endpoint)
            if issue["state"] != "open":
                reason = "closed"
            elif issue.get("sub_issues_summary", {}).get("total", 0):
                reason = "umbrella issue with sub-issues"
            else:
                dependencies = claims.gh(f"{endpoint}/dependencies/blocked_by?per_page=100", paginate=True)
                blockers = [f"#{dependency['number']}" for dependency in dependencies
                            if dependency["state"] == "open"]
                if not blockers:
                    return task, skipped
                reason = "blocked by " + ", ".join(blockers)
        skipped.append(f"SKIP {key} - {reason}")
    return None, skipped


def slugify(text):
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")[:40] or "work"


def open_pulls(owner, repo):
    return claims.gh(f"repos/{owner}/{repo}/pulls?state=open&per_page=100", paginate=True)


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
    if args.dry_run and not args.next:
        parser.error("--dry-run requires --next")

    try:
        owner, repo = claims.repository()
        git("fetch", "--quiet", "origin", "main")
        if args.none:
            pull = claim(owner, repo, f"none — {args.none}", "none", args, slugify(args.none))
            print(f"CLAIMED none #{pull['number']} {pull['branch']}")
            return 0
        priorities = ready_issues(git("show", "origin/main:docs/priorities.md")) if args.next else []
        skip = set()
        for _ in range(MAX_ATTEMPTS):
            item = ""
            if args.next:
                task, skipped = next_task(owner, repo, priorities, skip)
                if args.dry_run or task is None:
                    if task is None:
                        print("NONE - no task is currently available in docs/priorities.md.")
                    else:
                        print(f"NEXT #{task.number}\n{task.row}")
                    for reason in skipped:
                        print(reason)
                    return 0 if task is not None else 1
                link, key, item = task.url, f"#{task.number}", task.row
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
    except (RuntimeError, OSError, ValueError) as error:
        print(f"FAIL claim - {error}")
        return 1


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())
