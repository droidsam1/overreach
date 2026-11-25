#!/usr/bin/env python3
"""Wait for several GitHub PRs. Print an initial status and only changes after that."""
import argparse
import concurrent.futures
import json
import subprocess
import time


def summarize(pr):
    """Return a state and a printable summary using the checks on the current head."""
    if pr["state"] == "MERGED":
        return "passed", "merged"
    if pr["state"] == "CLOSED":
        return "failed", "closed without merging"
    checks = pr["statusCheckRollup"]
    if not checks:
        return "pending", "waiting for checks"
    results = []
    for check in checks:
        name = check.get("name") or check.get("context") or "check"
        state = check.get("state")
        if "status" in check:
            state = check.get("conclusion") if check["status"] == "COMPLETED" else "PENDING"
        outcome = (
            "passed" if state in {"SUCCESS", "NEUTRAL", "SKIPPED"}
            else "pending" if state in {"PENDING", "EXPECTED"}
            else "failed"
        )
        results.append((outcome, f"{name}: {state or 'UNKNOWN'}"))
    states = {outcome for outcome, _ in results}
    overall = "failed" if "failed" in states else "pending" if "pending" in states else "passed"
    return overall, ", ".join(sorted(label for _, label in results))


def snapshot(pr, repository, timeout):
    command = ["gh", "pr", "view", pr, "--json", "number,headRefOid,state,statusCheckRollup"]
    if repository:
        command.extend(("--repo", repository))
    result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", timeout=timeout)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or "gh pr view failed")
    data = json.loads(result.stdout)
    state, summary = summarize(data)
    return state, f"#{data['number']} {data['headRefOid'][:7]} {summary}"


def watch(prs, repository, interval, timeout):
    deadline = time.monotonic() + timeout
    previous = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=min(len(prs), 8)) as pool:
        while remaining := deadline - time.monotonic():
            if remaining <= 0:
                break
            pending = pool.map(lambda pr: snapshot(pr, repository, min(remaining, 20)), prs)
            states = []
            for pr, (state, summary) in zip(prs, pending):
                if previous.get(pr) != summary:
                    print(summary, flush=True)
                    previous[pr] = summary
                states.append(state)
            if "failed" in states:
                return 1
            if all(state == "passed" for state in states):
                return 0
            time.sleep(max(0, min(interval, deadline - time.monotonic())))
    print("Timed out waiting for checks.", flush=True)
    return 2


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("prs", nargs="+", help="PR numbers, branches or URLs")
    parser.add_argument("--repo", help="GitHub owner/repo when running outside the checkout")
    parser.add_argument("--interval", type=int, default=30, help="seconds between checks")
    parser.add_argument("--timeout", type=int, default=1800, help="maximum seconds to wait")
    args = parser.parse_args()
    if min(args.interval, args.timeout) < 1:
        parser.error("--interval and --timeout must be positive")
    try:
        return watch(list(dict.fromkeys(args.prs)), args.repo, args.interval, args.timeout)
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        parser.exit(2, f"Could not read checks: {error}\n")


if __name__ == "__main__":
    raise SystemExit(main())
