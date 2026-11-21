---
name: retro
description: Retrospective of one or more agent sessions on Overreach that proposes changes to the agent guide, checks and tooling. Use only when the user asks for a retro.
disable-model-invocation: true
---

# Retro

Adapted for Overreach from the `retro` skill in [mattpocock/skills](https://github.com/mattpocock/skills).
The goal is a better environment for the next agent run, not a judgement of the last one.

## Steps

1. Read the [writing-for-agents](../writing-for-agents/SKILL.md) skill. Every proposal you write follows it.
2. Gather the sessions. Use the ones the user names; otherwise the current session.
   - Claude Code: `~/.claude/projects/<project path with separators as dashes>/*.jsonl`
   - Codex: `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` (match on the session's `cwd`)
   - Run `scripts/session-usage.py` on each machine where sessions ran (the user runs it on theirs) for each
     session's cost and where it went: re-reading context, cache writes or output.
   - When logs are out of reach, use the trail in git and GitHub: fix-up and "make mergeable" commits, merge
     commits, reverts, `gh pr view --comments`, `gh run list --status failure`.
   Done when you can name, for each session, what it set out to do and where it lost time.
3. Find candidates in each category. Cite the evidence (session and turn, or commit) for every one.
   - **Navigation** — the agent searched for a file, command or doc. Fix: a pointer in `AGENTS.md` or a doc.
   - **Automated checks** — an error a tool could have caught. Fix: `scripts/check-repo.py`,
     `scripts/check-local.py`, `.swiftlint.yml` or CI.
   - **Coding standards** — a judgment call the reviewer missed. Fix: a rule in `CODING_STANDARDS.md`. A
     mechanical rule goes to a check instead.
   - **Agent guide** — `AGENTS.md` steering that belongs in the standards or a check, or that grew past a map.
   - **Parallel work** — conflicts and renumbering between branches. Fix: merge drivers, checks, workflow notes.
   - **Tool economy** — expensive or repeated tool calls, noisy output, slow loops, sessions whose context grew
     past a few hundred thousand tokens. Fix: a script, a flag or a workflow note.
   - **No-ops** — instructions that did not change behaviour. Fix: delete them.
   - **Information access** — logs, data or third-party access the agent lacked. Fix: a script, fixture or doc.
4. Present the candidates to the user, most severe first. For each: the evidence, the change, the file it goes in.
   Done when every candidate has all three and nothing is applied without the user's go-ahead.
