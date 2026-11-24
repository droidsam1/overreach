"""Read the executable issue list in docs/priorities.md."""

import re
from typing import NamedTuple

READY_HEADING = "## Ready to implement"
READY_ROW = re.compile(
    r"[1-9][0-9]*\. \[#(?P<number>[1-9][0-9]*)\]"
    r"\((?P<url>https://github\.com/droidsam1/overreach/issues/(?P=number))\) — (?P<summary>\S.*)"
)
EXTRA_LINK = re.compile(r"\]\(|https?://|#[0-9]+")


class ReadyIssue(NamedTuple):
    number: str
    url: str
    row: str


def ready_issues(markdown):
    lines = markdown.splitlines()
    if READY_HEADING not in lines:
        raise ValueError(f"docs/priorities.md: missing '{READY_HEADING}' heading")

    issues, problems, seen = [], [], set()
    start = lines.index(READY_HEADING) + 1
    for line_number, line in enumerate(lines[start:], start=start + 1):
        if line.startswith("## "):
            break
        if not line.strip():
            continue
        match = READY_ROW.fullmatch(line)
        if not match or EXTRA_LINK.search(match["summary"]):
            problems.append(f"docs/priorities.md:{line_number}: expected one issue link followed by a summary")
            continue
        number = match["number"]
        if number in seen:
            problems.append(f"docs/priorities.md:{line_number}: duplicate issue #{number}")
            continue
        seen.add(number)
        issues.append(ReadyIssue(number, match["url"], line))

    if problems:
        raise ValueError("\n".join(problems))
    return issues
