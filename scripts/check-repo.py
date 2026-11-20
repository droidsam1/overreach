#!/usr/bin/env python3
"""Repository rules that agents and humans would otherwise have to remember.

Checks:
- ADR files are named NNNN-title.md, numbers are unique, and each heading starts with its number.
- The frozen v1 backup fixture (ADR-0018) is unchanged.
- Every released version in CHANGELOG.md has highlights in ReleaseNotes.all ("What's new").
- Shared agent skills in .agents/skills and .claude/skills are identical.
- Relative links in agent guidance resolve.
- No Python bytecode is tracked.

Usage: scripts/check-repo.py
"""
import hashlib
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ADR_DIR = ROOT / "docs/adr"
BACKUP_V1_TESTS = ROOT / "Packages/OverreachCore/Tests/DomainTests/BackupFormatV1Tests.swift"
BACKUP_V1_SHA256 = "011b6d69cad5b15ffff4dd7d71851d8016950a4cf8fa785ec4e89674cb83afb6"
RELEASE_NOTES = ROOT / "Packages/OverreachCore/Sources/Presentation/OnboardingPresentation/WhatsNewModel.swift"
SKILL_MIRRORS = (ROOT / ".agents/skills", ROOT / ".claude/skills")
AGENT_GUIDES = ["AGENTS.md", "CLAUDE.md", "CODING_STANDARDS.md"]
LINK = re.compile(r"\]\(([^)#\s]+)(?:#[^)]*)?\)")


def text(path):
    return path.read_text(encoding="utf-8").replace("\r\n", "\n")


def adrs():
    problems, seen = [], {}
    for path in sorted(ADR_DIR.glob("*.md")):
        match = re.fullmatch(r"(\d{4})-[a-z0-9-]+\.md", path.name)
        if not match:
            problems.append(f"ADR file name is not NNNN-title.md: docs/adr/{path.name}")
            continue
        number = match.group(1)
        if number in seen:
            problems.append(f"ADR {number} is used twice: {seen[number]} and {path.name}. "
                            "Rebase on origin/main and take the next free number.")
        seen[number] = path.name
        heading = text(path).lstrip().split("\n", 1)[0]
        if number != "0000" and not heading.startswith(f"# {number} — "):
            problems.append(f"ADR heading does not start with '# {number} — ': docs/adr/{path.name}")
    return problems


def backup_fixture():
    match = re.search(r'static let fixture = #"""\n(.*?)\n\s*"""#', text(BACKUP_V1_TESTS), re.S)
    if not match:
        return [f"Frozen v1 backup fixture not found in {BACKUP_V1_TESTS.relative_to(ROOT)}"]
    digest = hashlib.sha256(match.group(1).encode()).hexdigest()
    if digest != BACKUP_V1_SHA256:
        return ["The frozen v1 backup fixture changed (ADR-0018). Restore it: make new fields optional or "
                "add a migration step in BackupCodec.migrate instead."]
    return []


def release_notes():
    released = re.findall(r"^## \[(\d+\.\d+\.\d+)\]", text(ROOT / "CHANGELOG.md"), re.M)
    noted = set(re.findall(r'ReleaseNotes\(version:\s*"([^"]+)"', text(RELEASE_NOTES)))
    return [f"CHANGELOG releases {version} but ReleaseNotes.all has no highlights for it"
            for version in released if version not in noted]


def skills():
    first, second = SKILL_MIRRORS
    files = lambda root: {p.relative_to(root) for p in root.rglob("*") if p.is_file()} if root.is_dir() else set()
    problems = []
    for relative in sorted(files(first) | files(second)):
        a, b = first / relative, second / relative
        if not (a.is_file() and b.is_file()) or a.read_bytes().replace(b"\r\n", b"\n") != \
                b.read_bytes().replace(b"\r\n", b"\n"):
            problems.append(f"Skill copies differ: .agents/skills/{relative} and .claude/skills/{relative}. "
                            "Edit one and copy it to the other.")
    return problems


def links():
    guides = [ROOT / name for name in AGENT_GUIDES]
    for root in SKILL_MIRRORS:
        guides += sorted(root.rglob("*.md")) if root.is_dir() else []
    problems = []
    for guide in guides:
        if not guide.is_file():
            problems.append(f"Missing agent guide: {guide.relative_to(ROOT)}")
            continue
        for target in LINK.findall(text(guide)):
            if "://" not in target and not (guide.parent / target).exists():
                problems.append(f"Broken link in {guide.relative_to(ROOT)}: {target}")
    return problems


def bytecode():
    tracked = subprocess.run(["git", "ls-files", "*.pyc", "*/__pycache__/*"], cwd=ROOT,
                             capture_output=True, text=True).stdout.split()
    return [f"Python bytecode is tracked: {path}" for path in tracked]


def main():
    problems = adrs() + backup_fixture() + release_notes() + skills() + links() + bytecode()
    print("\n".join(problems) or "Repository rules hold.")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
