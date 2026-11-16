# 0012 — Every recommendation rule is evidence-based and says how strong its evidence is

- **Status:** Accepted
- **Date:** 2026-11-16

## Context

Overreach proposes loads, progressions, deloads, rest, walks and (later) nutrition. Fitness apps often encode
folklore as rules. The product owner's requirement: all recommendation, proposal and evaluation logic must use
the most robust and most recent scientific evidence available, and the best available heuristics where
evidence runs out.

## Decision

1. **Research before rules.** Before implementing or changing any rule in `Analytics` (progression, stalls,
   deloads, readiness, load, cycle, walking, nutrition), search for the current evidence, preferring, in
   order: recent umbrella reviews and meta-analyses (and meta-regressions), position stands and consensus
   statements, RCTs, observational studies, expert/coaching heuristics. Prefer the newest high-quality
   synthesis; note when an older one is still the best available.
2. **Evidence register.** Every rule has an entry in `docs/evidence.md` with a stable key, what the evidence
   says, the level (`strong`, `moderate`, `limited`, `heuristic` — `EvidenceLevel` in `Domain`), the
   references, and the date it was last reviewed.
3. **Traceable in code.** Each rule cites its key (`EvidenceReference`) in a doc comment, and the reasons it
   returns carry it, so the UI and the shareable report can show *why* and *how sure*.
4. **Heuristics are labelled, not hidden.** Where research gives no precise number (e.g. the exact stall
   window), we pick a sensible default, label it `heuristic`, and make it configurable.
5. **Individual data beats group averages** when the user has enough history (e.g. personal per-phase or
   per-exercise patterns), as long as the rule that learns from it is itself evidence-based.
6. **Review.** Entries older than ~12 months, or contradicted by a newer synthesis, are re-checked when the
   related rule is touched. A changed conclusion updates the entry, the rule and the CHANGELOG.

## Consequences

- PRs that add or change a rule include the `docs/evidence.md` update (PR template checklist).
- Some features ship with conservative defaults and "low certainty" labels rather than confident claims.
- Recommendations never present themselves as medical advice (see `CLAUDE.md`).
