# 0040 — Structured runs in the shared schedule

- **Status:** Accepted
- **Date:** 2026-11-21

## Context

Plan already combines dated strength and running entries with explicit rest and an undated strength rotation.
A planned run stores a purpose, optional duration and distance, and an optional link to a recorded run.

## Decision

Keep the planned run identity and add optional prescription, race priority and scheduling fields. Store pace in
seconds per kilometre and recovery in seconds. Heart-rate zone and perceived effort use the athlete's own scale.
Keep the first date when moving an entry. A postponed entry retains its date for reference but is excluded from
active recommendations and same-day conflicts until the athlete reschedules it. A recording explicitly linked to
an entry is the only way to mark it completed and must be on its scheduled day. An active running rest entry
continues to exclude other active running entries on that day. Strength and running keep separate rest rules.

## Consequences

Old profiles and backups can decode without the new fields. Backups preserve the full calendar. The optional
fields also travel in the existing AI context export. Choices entered in Plan describe the athlete's intent.
