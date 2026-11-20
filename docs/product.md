# Overreach — Product definition (summary)

Overreach is an all-in-one iOS app for hybrid athletes. It replaces a gym logger (Strong), adds recovery data
from Apple Health and Garmin Connect, and answers "how should I train today?" with explainable
recommendations. It is a personal, open-source project; anyone can install it with their own data.

## Goals

- One place for strength sessions, runs and recovery metrics (HRV, sleep, resting HR, Body Battery, load…).
- Concrete daily recommendations (weights, reps, run type, distance, intensity) based on recovery,
  per-muscle-group load, progression and the user's plan.
- AI assistance: in the prototype, a Markdown report shared to the ChatGPT/Claude app; later, an in-app
  chat through any LLM provider (OpenAI by default).
- Credentials and data never leave the device unless the user shares a report.

Non-goals: medical diagnosis, App Store publication (for now), sharing data between people. Nutrition comes later.

## Data sources

| Data | Source | Notes |
| --- | --- | --- |
| Sets, reps, kg, RPE | The app itself | Live session logger |
| Historical strength data | Strong CSV | One-off import |
| Resting HR, HR, sleep, steps, runs | Apple Health (written by Garmin Connect) | Official, automatic |
| Nightly HRV (with status and baseline), sleep score, Body Battery, stress, respiration, SpO2, VO2max, per-activity load and training effect, activity details and FIT files | Garmin Connect Personal API (official, ADR-0022) | Optional; the user's own key in Keychain; direct from iPhone |
| Subjective state (sick, energy, soreness) | Daily check-in | 10 seconds |
| Steps and walks (bouts, HR) | Apple Health + Garmin activities | Baseline-relative; ADR-0010 |
| Menstrual cycle (flow, symptoms) | Apple Health (Cycle Tracking, Flo, Clue…) + check-in | Optional; context only (ADR-0009) |

## Core analytics

- Effective sets per muscle group per week (RPE ≥ 6, or no RPE; primary muscle 1, secondary 0.5).
- Tonnage, estimated 1RM (Epley), relative intensity.
- Session load (sRPE), run load (TRIMP or Garmin load), this week's load against the usual week (not the
  acute:chronic ratio: `weekly-load-change` in `docs/evidence.md`).
- Per-muscle fatigue with recovery decay (48–72 h legs/back, 24–48 h shoulders/arms).
- Progressive-overload detection (double progression, load progression, rep cycles, deloads), stall alerts.
- Run/lift interference and "what if I run X km today?" simulation.
- Daily steps and walks vs the personal baseline: walking above baseline as low-weight leg load, walks as
  active recovery, walking routine (e.g. a dog) as a constraint (`docs/design/daily-activity.md`).
- Training focus per block/session/exercise (declared or inferred), balance findings against the goal, and
  block planning months ahead (`docs/design/training-focus.md`).
- Readiness traffic light (rules, thresholds configurable, always shows the reasons).

## Screens

Today · Train · History · Trends · Exercises · Plan · Assistant · Settings (+ Onboarding).

## Phases

0. Foundation — repo, modules, CI, design system, domain model (incl. athlete profile, cycle and daily-activity types), docs.
1. Replace Strong (v0.1) — logger, CSV import, write workouts to Health, JSON backup in iCloud Drive, and the
   progression engine: next-session targets, stall detection with suggestions, deload proposals from training
   signals (see `docs/design/progression-engine.md`).
2. Recovery (v0.2) — Health + Garmin sync, check-in, Today, traffic light; deloads also weigh HRV, resting HR,
   sleep, stress and sickness; onboarding asks sex, cycle tracking and walking routine;
   steps/walks with baselines and walking load; cycle phase estimate and
   phase-aware HRV/resting-HR baselines (see `docs/design/cycle-aware-training.md`).
3. Intelligence — plan, load/progression, recommendations, shareable report, Trends; walking recommendations;
   symptom-driven autoregulation and personal per-phase patterns for naturally cycling users.
4. Validation & distribution — paid developer account, CloudKit sync, TestFlight, in-app chat via API.

Later: Shortcuts actions and widget, morning notification, Connect IQ watch app for own HRV, HRV written
to Health, more data sources, nutrition (cycle- and load-aware macros), optional remote MCP connector.
