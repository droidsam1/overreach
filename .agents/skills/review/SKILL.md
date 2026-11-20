---
name: review
description: Review an Overreach diff or pull request against CODING_STANDARDS.md. Use when asked to review code, a branch or a PR.
---

# Review

1. Get the diff: `git diff $(git merge-base origin/main HEAD)` for a branch, or `gh pr diff <number>` for a PR.
   Done when you have the list of changed files.
2. Run `python3 scripts/check-local.py` (Windows: `py -3 scripts/check-local.py`). Report its failures as they
   are; skip the rules it covers in the next step.
3. Read the sections of [CODING_STANDARDS.md](../../../CODING_STANDARDS.md) that match the changed files and
   check each changed hunk against them. Open surrounding code only when a hunk depends on it.
4. Report findings most severe first, each with `file:line`, the rule it breaks and a concrete fix. Say plainly
   when there are none. Done when every changed file was checked against its sections.
