#!/usr/bin/env python3
"""Fails when SwiftLint reports a warning on a line this branch changed. Older warnings are only counted.

Reads SwiftLint output in the github-actions-logging format (from a file or stdin).
With --line-length it needs no SwiftLint: it checks only the line length of changed Swift lines, the one rule a
machine without Docker can still enforce.
Usage: swiftlint --reporter github-actions-logging | scripts/new-lint-warnings.py [--base origin/main] [LOG]
       scripts/new-lint-warnings.py --line-length [--base origin/main]
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
LINE_LENGTH = 120  # `line_length: warning` in .swiftlint.yml


def git(*args):
    # UTF-8 explicitly: Windows would decode with its ANSI code page and fail on the translated strings.
    command = ["git", "-c", "core.quotepath=false", *args]
    return subprocess.run(command, cwd=ROOT, capture_output=True, encoding="utf-8", errors="replace",
                          check=True).stdout


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


def long_lines(changed):
    """SwiftLint-style diagnostics for changed Swift lines over LINE_LENGTH characters."""
    for path, lines in sorted(changed.items()):
        if not path.endswith(".swift") or not path.startswith(SOURCE_ROOTS):
            continue
        file = ROOT / path
        if not file.is_file():
            continue
        for number, text in enumerate(file.read_text(encoding="utf-8-sig").splitlines(), 1):
            if len(text) > LINE_LENGTH and (lines is None or number in lines):
                yield (f"::warning file={path},line={number}::Line should be {LINE_LENGTH} characters or less; "
                       f"currently it has {len(text)} characters (line_length)")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", default="origin/main")
    parser.add_argument("--line-length", action="store_true", help="check line length only, without SwiftLint")
    parser.add_argument("log", nargs="?")
    args = parser.parse_args()
    changed = changed_lines(args.base)
    if args.line_length:
        output = "\n".join(long_lines(changed))
    else:
        output = Path(args.log).read_text(encoding="utf-8", errors="replace") if args.log else sys.stdin.read()
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
