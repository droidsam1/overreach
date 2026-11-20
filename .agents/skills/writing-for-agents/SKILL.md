---
name: writing-for-agents
description: Style for anything an agent reads in Overreach — AGENTS.md, CLAUDE.md, CODING_STANDARDS.md, skills and docs reached through pointers. Use when writing or editing them.
---

# Writing for agents

Adapted for Overreach from the `writing-for-agents` skill in
[mattpocock/skills](https://github.com/mattpocock/skills).

## Where things go

| Content | Home | Loaded |
| --- | --- | --- |
| Map: what the project is, where things are, commands | `AGENTS.md` (`CLAUDE.md` imports it) | Every turn |
| Judgment rules for writing and reviewing code | `CODING_STANDARDS.md` | When writing or reviewing |
| Mechanical rules | `scripts/check-*.py`, `.swiftlint.yml`, CI | Never read: they fail |
| Reasons and history of a decision | `docs/adr/` | Through pointers |
| Procedures for a kind of task | `.agents/skills/<name>/SKILL.md`, copied to `.claude/skills/` | When the task matches |

Search `docs/` before writing a new document; extend the one that already covers the subject.

## Principles

- **Pointers.** A pointer names out-of-context material and says when to open it. Lead with the trigger word,
  use one pointer per branch of work, and leave out what the target already says.
- **Two costs.** Always-loaded text costs tokens on every turn; each extra document costs the human attention to
  know it exists. Keep always-loaded text short and add documents only where they pay for themselves.
- **Steps and reference.** Steps are ordered actions; reference is consulted when needed. Keep steps in the main
  file. Keep reference inline when most runs need it, otherwise behind a pointer.
- **Finish lines.** Each step ends with a checkable condition. A vague condition makes agents stop early.
- **Split on real boundaries:** a handoff, a subagent, or later steps that tempt the agent to rush earlier ones.
- **Leading words.** Use concepts the model already knows ("tight", "red") instead of re-explaining them. State
  what to do; a prohibition plants the behaviour it forbids.
- **Prune.** One meaning in one place. Don't restate what scripts or config already show, or what the model does
  by default. Delete stale lines.
- **Mechanical beats written.** If a rule can be checked, write the check and drop the sentence.
