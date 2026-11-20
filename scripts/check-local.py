#!/usr/bin/env python3
"""Run local Overreach checks for the changes since a branch diverged."""
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
        summary = next((line for line in reversed(lines) if "tests passed" in line or "strings translated" in line), "")
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


def lint(paths, logs, image):
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
            return run_check("swiftlint", ["swiftlint", *options], logs, cwd=staging)
        command = ["docker", "run", "--rm", "-v", f"{staging}:/src:ro", "-w", "/src", image, "swiftlint"]
        return run_check("swiftlint", [*command, *options], logs)


def core_tests(logs):
    if shutil.which("swift"):
        return run_check("core", ["swift", "test", "--package-path", "Packages/OverreachCore"], logs)

    # Each checkout gets its own SwiftPM build products when using Docker.
    checkout = hashlib.sha256(os.fsencode(ROOT)).hexdigest()[:12]
    env = {**os.environ, "OVERREACH_SWIFT_BUILD_VOLUME": f"overreach-swift-build-{checkout}"}
    if os.name == "nt":
        shell = shutil.which("pwsh") or "powershell"
        command = [shell, "-NoProfile", "-File", str(ROOT / "scripts/test-core.ps1")]
    else:
        command = ["sh", "scripts/test-core.sh"]
    return run_check("core", command, logs, env=env)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", help="Base ref to compare against (origin/main, or HEAD if unavailable)")
    parser.add_argument("--lint-image", default=LINT_IMAGE, help="Docker image to use when SwiftLint is unavailable locally")
    args = parser.parse_args()

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

    if not (lint_paths or translation_check or core_check):
        print(f"No applicable local checks ({len(paths)} changed paths, base {base}).")
        if apple_check:
            print("Apple package tests and the iOS simulator build run in CI.")
        return 0

    logs = Path(tempfile.mkdtemp(prefix="overreach-check-"))
    print(f"Base: {base} | {len(paths)} changed paths | Logs: {logs}", flush=True)
    statuses = []
    if translation_check:
        statuses.append(run_check("localization", [sys.executable, "scripts/check-localization.py"], logs))
    if lint_paths:
        statuses.append(lint(lint_paths, logs, args.lint_image))
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
