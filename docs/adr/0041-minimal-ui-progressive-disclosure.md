# 0041 — Minimal UI with two levels of progressive disclosure

- **Status:** Accepted
- **Date:** 2026-11-22

## Context

Overreach must answer "what should I do today?" at a glance. A code review on 2026-11-22 found:

- Today (`FeatureToday/TodayView.swift`) can stack about 14 blocks: decision, today's plan, run option, readiness
  details, warnings, deload proposal, "I want to lift today", check-in, movement, dog-walk question, connect Health,
  connect Garmin, **View recovery** and **View recent training**. Each block is justified alone; together they turn a
  decision into reading.
- In the most common state (`NextAction.readiness`) the primary action renders nothing, so Today has no button.
- Evidence and guidance texts (`strengthDetails`, deload rows) render inline.
- Onboarding asks five steps (goal, about, walking, devices, start) before the first recommendation.

The [iPhone UX guide](../design/iphone-ux.md) already asks for one dominant action and labelled routes to detail.
This ADR makes that concrete and records the evidence.

## Evidence

| Finding | Source | What it supports |
| --- | --- | --- |
| Choice overload is real when the decision is difficult, the set complex and preferences uncertain (meta-analysis, 99 observations, N = 7,202). | Chernev, Böckenholt & Goodman 2015, *J Consumer Psychology* | One recommendation with one verb; alternatives folded. |
| Designs with more than two disclosure levels usually have low usability: people get lost between levels. The split should follow frequency of use. | Nielsen Norman Group, *Progressive Disclosure* | Two levels: Today, then one pushed screen. |
| Tutorials raised play time up to 29 % only in the most complex of three games; mechanics learnable by experimenting did not need up-front teaching. Context-sensitive teaching beats up-front manuals. | Andersen et al. 2012, CHI, *The impact of tutorials on games of varying complexity* | Short onboarding; ask profile questions when they change a decision. |
| Gamification has a robust medium effect on cognitive learning outcomes; motivational and behavioural effects are smaller and less stable. Small average effect on intrinsic motivation. | Sailer & Homner 2020, *Educ Psychol Rev*; 2023 meta-analysis in *ETR&D* (g = 0.257) | Feedback that builds competence; no points or badges as goals. |
| In a 24-week RCT (N = 602), gamified step goals increased activity; only competition kept an effect after the game ended. | Patel et al. 2019, *JAMA Internal Medicine* (STEP UP) | Compare the athlete with their own usual week, not with a game score. |
| Broken streaks lower later engagement and raise abandonment. | Silverman & Barasch 2023, *J Consumer Research* (via INSEAD summary) | No streaks. Rest is a valid, completed action. |
| Progress perceived as already started increases completion (endowed progress). | Nunes & Drèze 2006, *J Consumer Research* | Show real progress through the week and block. |
| Social networks use "interactive hooks" to keep people engaged as long as possible. | Mildner et al. 2023, CHI, dark patterns in social networking services | What not to copy: no feeds, infinite scroll, guilt notifications or variable rewards. |
| Few wearable composite scores publish validation of the final number; users ask which inputs moved it. | 2025 review of 14 composite scores (De Gruyter, DOI 10.1515/teb-2025-0001) | Keep the traffic light with its leading reason in one line; the rest behind **Why**. |

Links are in the [UX guide's research section](../design/iphone-ux.md#progressive-disclosure-adr-0041).

## Decision

1. **One hero, one verb.** Every Today state except loading shows a verdict, one leading reason and one prominent
   button whose label names the outcome ("Start Legs A", "Run 30 min easy", "Rest today").
2. **One pending prompt.** At most one secondary prompt (source retry, break confirmation, check-in, connect a source,
   a contextual question), chosen by a pure priority rule in `TodayPresentation`.
3. **Two levels only.** Level 1 is the hero, today's plan, the pending prompt and a link row
   (**Why · Recovery · History**). Level 2 is a pushed screen. Evidence, guidance, alternatives and metrics live on
   level 2. Today shows at most four blocks; a test enforces the budget.
4. **Every move ships its route.** Content leaving Today gets its route from Today in the same change.
5. **Ask in context.** Onboarding asks goal and devices only. Other profile questions arrive as the pending prompt
   when their answer would change a recommendation, and stay editable in Settings.
6. **Show what the data supports.** A section appears when there is data that makes it meaningful. Otherwise a single
   line names what unlocks it.
7. **Reward competence, not compulsion.** Immediate feedback where the action happens (set completion haptic),
   celebration only for real achievements (PRs, goal milestones), visible real progress through the week and block,
   and rest recorded as a completed action. No streaks, points, badges, leaderboards, variable rewards or guilt
   wording.

Tasks: [#179](https://github.com/droidsam1/overreach/issues/179) and its sub-issues #180–#187.

## Implementation

The sub-issues shipped, including sections that appear when data becomes available
([#185](https://github.com/droidsam1/overreach/issues/185)) and set feedback and strength achievements
([#191](https://github.com/droidsam1/overreach/pull/191)). Running-goal celebration needs an event that marks goal
progress. Device timing and accessibility checks are tracked in [#21](https://github.com/droidsam1/overreach/issues/21).

## Consequences

- Today becomes testable for density: the set of visible blocks is computed in `TodayPresentation`.
- Some information needs one more tap. The **Why** screen must be easy to find and its label stays stable.
- The pending-prompt queue delays lower-priority questions by a day or more; the order must be reviewed when a new
  prompt is added.
- Moving profile questions out of onboarding means early recommendations run with defaults; rules must already
  handle missing profile fields (they do, as all metrics are optional).
- Use the guide's before/after check to measure time and wrong turns on a device.
