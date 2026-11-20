#!/usr/bin/env python3
"""Fails when SwiftLint reports a warning on a line this branch changed. Older warnings are only counted.

Reads SwiftLint output in the github-actions-logging format (from a file or stdin).
Usage: swiftlint --reporter github-actions-logging | scripts/new-lint-warnings.py [--base origin/main] [LOG]
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DIAGNOSTIC = re.compile(r"^::(warning|error) file=([^,]+),line=(\d+)(?:,col=\d+)?::(.*)$")
HUNK = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@")
SOURCE_ROOTS = ("Packages/", "App/Sources/")


def git(*args):
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True, check=True).stdout


def changed_lines(base):
    """Changed lines per path; None means the whole file is new."""
    common = git("merge-base", base, "HEAD").strip()
    changed, path = {}, None
    for line in git("diff", "-U0", "--no-color", "--no-renames", common, "--").splitlines():
        if line.startswith("+++ "):
            path = line[6:] if line.startswith("+++ b/") else None
            if path:
                changed.setdefault(path, set())
        elif path and (hunk := HUNK.match(line)):
            start, count = int(hunk.group(1)), int(hunk.group(2) or 1)
            changed[path].update(range(start, start + count))
    for path in git("ls-files", "--others", "--exclude-standard").splitlines():
        changed[path] = None
    return changed


def relative(path):
    path = path.replace("\\", "/")
    starts = [path.find(root) for root in SOURCE_ROOTS if root in path]
    return path[min(starts):] if starts else path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", default="origin/main")
    parser.add_argument("log", nargs="?")
    args = parser.parse_args()
    output = Path(args.log).read_text(encoding="utf-8", errors="replace") if args.log else sys.stdin.read()
    changed = changed_lines(args.base)
    new, existing = [], 0
    for line in output.splitlines():
        if not (match := DIAGNOSTIC.match(line.strip())):
            continue
        path, number = relative(match.group(2)), int(match.group(3))
        lines = changed.get(path, set())
        if lines is None or number in lines:
            new.append(f"{path}:{number}: {match.group(4)}")
        else:
            existing += 1
    print("\n".join(new) if new else "No new lint warnings.", f"({existing} older warnings in changed files)")
    return 1 if new else 0


if __name__ == "__main__":
    sys.exit(main())
