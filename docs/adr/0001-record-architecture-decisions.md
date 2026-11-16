# 0001 — Record architecture decisions

- **Status:** Accepted
- **Date:** 2026-11-16

## Context

Overreach is open source and will be worked on across many sessions, by humans and AI assistants. Decisions
that are only in someone's head get re-litigated or silently broken.

## Decision

Record every significant architectural or product-technical decision as a short ADR in `docs/adr/`, numbered
sequentially, using `0000-template.md`. ADRs are immutable once accepted; a change of mind is a new ADR that
supersedes the old one.

## Consequences

- Contributors and assistants can understand *why* the code looks the way it does.
- Small overhead per decision; keep ADRs to one page.
