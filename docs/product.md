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
| Nightly HRV, Body Battery, stress, respiration, SpO2, training status/readiness, load, recovery time, VO2max, race predictions, activity details | Garmin Connect (unofficial API) | Optional; tokens in Keychain; direct from iPhone |
| Subjective state (sick, energy, soreness) | Daily check-in | 10 seconds |

## Core analytics

- Effective sets per muscle group per week (RPE ≥ 7; primary muscle 1, secondary 0.5).
- Tonnage, estimated 1RM (Epley), relative intensity.
- Session load (sRPE), run load (TRIMP or Garmin load), acute:chronic workload ratio.
- Per-muscle fatigue with recovery decay (48–72 h legs/back, 24–48 h shoulders/arms).
- Progressive-overload detection (double progression, load progression, rep cycles, deloads), stall alerts.
- Run/lift interference and "what if I run X km today?" simulation.
- Readiness traffic light (rules, thresholds configurable, always shows the reasons).

## Screens

Today · Train · History · Trends · Exercises · Plan · Assistant · Settings (+ Onboarding).

## Phases

0. Foundation — repo, modules, CI, design system, domain model, docs.
1. Replace Strong (v0.1) — logger, CSV import, write workouts to Health, JSON backup in iCloud Drive, and the
   progression engine: next-session targets, stall detection with suggestions, deload proposals from training
   signals (see `docs/design/progression-engine.md`).
2. Recovery (v0.2) — Health + Garmin sync, check-in, Today, traffic light; deloads also weigh HRV, resting HR,
   sleep, stress and sickness.
3. Intelligence — plan, load/progression, recommendations, shareable report, Trends.
4. Validation & distribution — paid developer account, CloudKit sync, TestFlight, in-app chat via API.

Later: Shortcuts actions and widget, morning notification, Connect IQ watch app for own HRV, HRV written
to Health, more data sources, nutrition, optional remote MCP connector.
