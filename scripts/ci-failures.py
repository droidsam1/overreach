#!/usr/bin/env python3
"""Prints only the errors of failed GitHub Actions runs, grouped by job, instead of the full logs.

Usage: scripts/ci-failures.py [PR number | run id | PR or run URL]
  Without an argument it reads the runs of the current commit (HEAD).
"""
import json
import re
import subprocess
import sys
import time

ERROR = re.compile(r"##\[error\]|\berror:|✘|[Ee]xpectation failed|recorded an issue|Not in the catalog|^FAIL\b")
CONTEXT_LINE = re.compile(r"^\s*\|")
RUNNER_PATH = re.compile(r"(/__w|/Users/runner/work|/home/runner/work)/overreach/overreach/")
TIMESTAMP = re.compile(r"^﻿?\d{4}-\d\d-\d\dT[\d:.]+Z ")
PER_JOB = 15


def gh(*args):
    for attempt in range(3):
        result = subprocess.run(["gh", *args], capture_output=True)
        if result.returncode == 0:
            return result.stdout.decode("utf-8", errors="replace")
        error = result.stderr.decode("utf-8", errors="replace").strip()
        if "401" in error or "auth login" in error:
            sys.exit("gh is not authenticated. Run `gh auth status`; if the token is bad, ask the user to run "
                     "`gh auth login`.")
        if not re.search(r"HTTP 5\d\d|timeout|connection", error, re.I) or attempt == 2:
            sys.exit(f"gh {' '.join(args)} failed: {error}")
        time.sleep(5 * (attempt + 1))


def runs_for_commit(sha):
    runs = json.loads(gh("run", "list", "--commit", sha, "--limit", "20",
                         "--json", "databaseId,workflowName,status,conclusion"))
    pending = [run["workflowName"] for run in runs if run["status"] != "completed"]
    if pending:
        print(f"Still running: {', '.join(pending)}")
    return [run["databaseId"] for run in runs if run["conclusion"] == "failure"]


def target_runs(argument):
    if argument is None:
        sha = subprocess.check_output(["git", "rev-parse", "HEAD"]).decode().strip()
        return runs_for_commit(sha)
    if match := re.search(r"/actions/runs/(\d+)", argument):
        return [int(match.group(1))]
    if match := re.search(r"/pull/(\d+)", argument):
        argument = match.group(1)
    if not argument.isdigit():
        sys.exit(__doc__)
    if len(argument) >= 8:
        return [int(argument)]
    sha = json.loads(gh("pr", "view", argument, "--json", "headRefOid"))["headRefOid"]
    return runs_for_commit(sha)


def summarize(run_id):
    info = json.loads(gh("run", "view", str(run_id), "--json", "workflowName,url,jobs"))
    print(f"== {info['workflowName']} {info['url']}")
    failed_steps = {
        job["name"]: [step["name"] for step in job["steps"] if step["conclusion"] == "failure"]
        for job in info["jobs"] if job["conclusion"] == "failure"
    }
    jobs = {}
    for line in gh("run", "view", str(run_id), "--log-failed").splitlines():
        parts = line.split("\t", 2)
        if len(parts) == 3:
            jobs.setdefault(parts[0], []).append(RUNNER_PATH.sub("", TIMESTAMP.sub("", parts[2])))
    for job, steps in failed_steps.items():
        lines = jobs.get(job, [])
        errors = [line for line in lines if ERROR.search(line) and not CONTEXT_LINE.match(line)]
        shown = list(dict.fromkeys(errors))[:PER_JOB] or lines[-PER_JOB:]
        print(f"-- {job} (failed step: {', '.join(steps) or 'unknown'})")
        for line in shown:
            print(f"   {line[:400]}")


def main():
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    runs = target_runs(sys.argv[1] if len(sys.argv) > 1 else None)
    if not runs:
        print("No failed runs.")
        return 0
    for run_id in runs:
        summarize(run_id)
    return 1


if __name__ == "__main__":
    sys.exit(main())
