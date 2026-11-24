#!/usr/bin/env python3
"""Run local Overreach checks for the changes since a branch diverged.

Also fails on CRLF working copies (fix with --fix-eol), warns when HEAD is far behind the base, checks that no other
PR claims this branch's task (scripts/check-task-claim.py) and stops early when Docker is needed but not running.
"""
import argparse
import hashlib
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LINT_CONFIG = ".swiftlint.yml"
LINT_IMAGE = "ghcr.io/realm/swiftlint:0.57.0"
ERROR = re.compile(r"::error\b|\berror:|expectation failed|recorded an issue", re.I)
BEHIND_LIMIT = 10
_docker_ready = None


def crlf_paths():
    """Tracked text files whose working copy has CRLF although the repository stores LF (.gitattributes)."""
    output = subprocess.run(["git", "ls-files", "--eol", "-z"], cwd=ROOT, capture_output=True, check=True).stdout
    paths = []
    for entry in output.split(b"\0"):
        if b"\t" not in entry:
            continue
        info, path = entry.split(b"\t", 1)
        fields = info.split()
        if fields[:2] == [b"i/lf", b"w/crlf"] or (fields[:1] == [b"i/lf"] and b"w/mixed" in fields):
            paths.append(os.fsdecode(path))
    return paths


def line_endings(fix):
    """Older checkouts keep CRLF working copies after the switch to LF; edits and tests expect LF."""
    paths = crlf_paths()
    if not paths:
        return 0
    if fix:
        for path in paths:
            file = ROOT / path
            file.write_bytes(file.read_bytes().replace(b"\r\n", b"\n"))
        print(f"FIXED line endings - {len(paths)} files rewritten with LF", flush=True)
        return 0
    print(f"FAIL line-endings - {len(paths)} files have CRLF in this working copy (e.g. {paths[0]}). "
          "Run again with --fix-eol to rewrite them with LF; the content does not change.", flush=True)
    return 1


def behind(base):
    if base == "HEAD":
        return
    count = int(subprocess.check_output(["git", "rev-list", "--count", f"HEAD..{base}"], cwd=ROOT).decode())
    if count > BEHIND_LIMIT:
        print(f"WARN HEAD is {count} commits behind {base}. Rebase, or start new work from a fresh {base} "
              "(git fetch first).", flush=True)


def docker_ready(name, quiet=False):
    global _docker_ready
    if _docker_ready is None:
        try:
            result = subprocess.run(["docker", "info"], capture_output=True, timeout=30)
            _docker_ready = result.returncode == 0
        except (OSError, subprocess.TimeoutExpired):
            _docker_ready = False
    if not _docker_ready and not quiet:
        print(f"FAIL {name} - Docker is not running. Start Docker Desktop (or ask the user to) and run again; "
              "the Docker installation itself needs no debugging.", flush=True)
    return _docker_ready


def git_paths(*args):
    result = subprocess.run(["git", *args], cwd=ROOT, capture_output=True, check=True)
    return set(os.fsdecode(path) for path in result.stdout.split(b"\0") if path)


def changes(base):
    common = subprocess.check_output(["git", "merge-base", base, "HEAD"], cwd=ROOT).decode().strip()
    tracked = git_paths("diff", "--name-only", "--no-renames", "-z", common, "--")
    return tracked | git_paths("ls-files", "--others", "--exclude-standard", "-z")


def is_swift_source(path):
    return path.endswith(".swift") and path.startswith(("App/Sources/", "Packages/"))


def affects_localization(path):
    return (
        path in {"scripts/check-localization.py", "App/Resources/Localizable.xcstrings", "App/Resources/InfoPlist.xcstrings"}
        or path.endswith(".swift") and path.startswith((
            "App/Sources/",
            "Packages/OverreachCore/Sources/Presentation/",
            "Packages/OverreachKit/Sources/DesignSystem/",
            "Packages/OverreachKit/Sources/Feature",
        ))
    )


def run_check(name, command, logs, *, cwd=ROOT, env=None):
    log = logs / (name + ".log")
    with log.open("wb") as output:
        try:
            result = subprocess.run(command, cwd=cwd, env=env, stdout=output, stderr=subprocess.STDOUT)
            status = result.returncode
        except OSError as error:
            output.write(f"{error}\n".encode())
            status = 127
    lines = log.read_text(encoding="utf-8", errors="replace").splitlines()
    if status == 0:
        markers = ("tests passed", "strings translated", "rules hold", "new lint warnings")
        summary = next((line for line in reversed(lines) if any(marker in line for marker in markers)), "")
        if "Test run with" in summary:
            summary = summary[summary.index("Test run with"):]
        if name == "swiftlint":
            summary = f"{sum(line.startswith('::warning ') for line in lines)} warnings"
        print(f"PASS {name}" + (f" - {summary.strip()}" if summary else ""), flush=True)
    else:
        print(f"FAIL {name} (exit {status})")
        diagnostics = [line for line in lines if ERROR.search(line)]
        for line in dict.fromkeys((diagnostics or lines[-6:])[:6]):
            print(line[:400])
        print(f"Full log: {log}", flush=True)
    return status if status >= 0 else 128 - status


def lint(paths, logs, image, base):
    with tempfile.TemporaryDirectory(prefix="lint-", dir=logs) as directory:
        staging = Path(directory)
        configuration = [LINT_CONFIG] if (ROOT / LINT_CONFIG).is_file() else []
        for path in [*configuration, *paths]:
            destination = staging / path
            destination.parent.mkdir(parents=True, exist_ok=True)
            # SwiftLint reads LF files in CI. Normalize working copies without touching the checkout.
            destination.write_text((ROOT / path).read_text(encoding="utf-8-sig"), encoding="utf-8", newline="\n")
        options = ["--quiet", "--no-cache", "--reporter", "github-actions-logging"]
        if shutil.which("swiftlint"):
            status = run_check("swiftlint", ["swiftlint", *options], logs, cwd=staging)
        elif not docker_ready("swiftlint", quiet=True):
            # Without SwiftLint or Docker only line length can be checked; CI runs the full rules.
            script = [sys.executable, "scripts/new-lint-warnings.py", "--line-length", "--base", base]
            status = run_check("line-length", script, logs)
            print("WARN swiftlint - not run: only line length on changed lines was checked; CI runs the full rules.")
            return status
        else:
            command = ["docker", "run", "--rm", "-v", f"{staging}:/src:ro", "-w", "/src", image, "swiftlint"]
            status = run_check("swiftlint", [*command, *options], logs)
    # Lines this branch changed must not add warnings; older warnings are only counted.
    script = [sys.executable, "scripts/new-lint-warnings.py", "--base", base, str(logs / "swiftlint.log")]
    return status or run_check("new-lint-warnings", script, logs)


def core_tests(logs):
    if shutil.which("swift"):
        return run_check("core", ["swift", "test", "--package-path", "Packages/OverreachCore"], logs)
    if not docker_ready("core"):
        return 1

    # Each checkout gets its own SwiftPM build products when using Docker.
    checkout = hashlib.sha256(os.fsencode(ROOT)).hexdigest()[:12]
    env = {**os.environ, "OVERREACH_SWIFT_BUILD_VOLUME": f"overreach-swift-build-{checkout}"}
    if os.name == "nt":
        shell = shutil.which("pwsh") or "powershell"
        command = [shell, "-NoProfile", "-File", str(ROOT / "scripts/test-core.ps1")]
    else:
        command = ["sh", "scripts/test-core.sh"]
    return run_check("core", command, logs, env=env)


def configure_merge_drivers():
    """Repository-local git settings that .gitattributes refers to; shared by every worktree."""
    driver = f'"{Path(sys.executable).as_posix()}" scripts/merge-xcstrings.py %O %A %B'
    subprocess.run(["git", "config", "merge.xcstrings.name", "String Catalog merge per key"], cwd=ROOT, check=True)
    subprocess.run(["git", "config", "merge.xcstrings.driver", driver], cwd=ROOT, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", help="Base ref to compare against (origin/main, or HEAD if unavailable)")
    parser.add_argument("--lint-image", default=LINT_IMAGE, help="Docker image to use when SwiftLint is unavailable locally")
    parser.add_argument("--fix-eol", action="store_true", help="Rewrite CRLF working copies of tracked files with LF")
    args = parser.parse_args()
    configure_merge_drivers()

    base = args.base
    if base is None:
        exists = subprocess.run(
            ["git", "rev-parse", "--verify", "--quiet", "origin/main"], cwd=ROOT, stdout=subprocess.DEVNULL
        ).returncode == 0
        base = "origin/main" if exists else "HEAD"
    paths = changes(base)
    lint_candidates = paths
    if LINT_CONFIG in paths:
        lint_candidates = git_paths("ls-files", "--cached", "--others", "--exclude-standard", "-z")
    lint_paths = sorted(path for path in lint_candidates if is_swift_source(path) and (ROOT / path).is_file())
    translation_check = any(affects_localization(path) for path in paths)
    core_check = any(path.startswith("Packages/OverreachCore/") or path in {
        "scripts/test-core.sh", "scripts/test-core.ps1",
    } for path in paths)
    apple_check = any(path.startswith(("App/", "Packages/OverreachKit/")) for path in paths)

    logs = Path(tempfile.mkdtemp(prefix="overreach-check-"))
    print(f"Base: {base} | {len(paths)} changed paths | Logs: {logs}", flush=True)
    behind(base)
    statuses = [line_endings(args.fix_eol), run_check("repository", [sys.executable, "scripts/check-repo.py"], logs)]
    if paths & {"scripts/priority_queue.py", "scripts/claim-task.py", "scripts/check-task-claim.py",
                "scripts/test-priority-queue.py"}:
        statuses.append(run_check("priority-queue", [sys.executable, "scripts/test-priority-queue.py"], logs))
    # Its own PASS/WARN/FAIL lines: another agent working on the same task stops this one early.
    statuses.append(subprocess.run([sys.executable, "scripts/check-task-claim.py"], cwd=ROOT).returncode)
    if translation_check:
        statuses.append(run_check("localization", [sys.executable, "scripts/check-localization.py"], logs))
    if lint_paths:
        statuses.append(lint(lint_paths, logs, args.lint_image, base))
    if core_check:
        statuses.append(core_tests(logs))
    if apple_check:
        print("Apple package tests and the iOS simulator build run in CI.")
    return next((status for status in statuses if status != 0), 0)


if __name__ == "__main__":
    sys.stdout.reconfigure(errors="backslashreplace")
    try:
        sys.exit(main())
    except subprocess.CalledProcessError as error:
        sys.exit(error.stderr.decode(errors="replace").strip() if error.stderr else str(error))
    except OSError as error:
        sys.exit(str(error))
