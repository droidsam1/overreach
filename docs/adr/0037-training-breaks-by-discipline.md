# 0037 — Count training breaks by discipline

- Status: accepted
- Date: 2026-11-21

## Context

[ADR-0029](0029-unplanned-deloads.md) combines inactivity across strength and running. An athlete who
keeps running during a break from lifting could still receive a strength deload proposal.

## Decision

Count a gap of seven complete local days in the available activity history as recovery for its discipline.
Start from the first qualifying activity. Running needs a distance goal or runs in two of the four weeks ending
on the last active day. Suppress inferred running breaks when a run source reports a read failure. Reduced-load
weeks use the last year of training and require confirmation while automatic breaks are enabled.

Settings → Training enables automatic counting by default. Turning it off restores the combined gap heuristic
and its confirmation rules. Existing saved answers without a discipline apply to both. New answers attach to
their period and discipline. Both fields are additive in backup format 1.

A strength gap of at least 14 days gives four calendar weeks to rebuild from the first day back before proposing
a strength deload. Strength deload performance signals use exposures from after the break. A running gap of
at least 14 days gives an easy-pace suggestion for the first two runs when readiness and the schedule allow it.

## Consequences

The recovery history distinguishes strength and running. Running breaks do not reset the strength deload clock.
A gap describes the available record. Athletes whose activity is only partly logged can turn off automatic
counting. Evidence and threshold limits are in [training-breaks](../evidence.md#training-breaks--heuristic).
