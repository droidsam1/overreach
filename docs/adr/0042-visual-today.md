# 0042 — Visual Today: cards, signals and week progress

- **Status:** Accepted
- **Date:** 2026-11-22

## Context

[ADR-0041](0041-minimal-ui-progressive-disclosure.md) cut Today to one hero, one prompt, the plan and a link row. The
structure works, but every block is still text of the same weight: green, amber and red differ only by a small badge
and a sentence, and the recovery readings and the week's progress that the app already computes are one level down
(Recovery) or on another tab (Plan). The owner compared it with the coloured cards of Garmin Connect: the first
impression is reading, not seeing.

The owner reviewed and approved mock-ups of four screens on 2026-11-22: green hero, amber hero with a pending
check-in, the Why screen, and the done-today state. [The spec](../design/today-visual.md) describes them.

## Decision

Keep ADR-0041's rules and change how Today renders them:

1. **The hero is a card tinted by the readiness tone**, with a ring and symbol, the verdict, one reason line and the
   verb button. Colour is always paired with a symbol and text.
2. **Up to three signal tiles sit inside the hero.** Each shows a value the app already computes, its recent trend
   over the personal band and a short status. The tile for the reason behind an amber or red verdict is emphasized.
   This moves the leading readings from level 2 to level 1, as part of the hero's "one leading reason", not as a new
   block. Tapping a tile opens Why. No composite score is added.
3. **"Today's plan" becomes "Your week"**: a seven-day strip, week and block progress and today's session. Week
   progress comes from one `TrainingServices` answer shared with Plan (ADR-0035).
4. **The pending prompt is answerable in place**: the check-in's feeling is a one-tap scale; details stay one tap away.
5. **The link row becomes tiles.** Why becomes one visual pushed screen (charts, gauge, evidence pills, navigation
   rows) without nested disclosure.
6. **Done today shows the session**: totals, real records (`SessionReport`) and tomorrow's session.

Today still shows at most four blocks: hero, your week, pending prompt, link tiles.

## Consequences

- Presentation gains display values for signals, week, quick check-in, done-today and Why; DesignSystem gains
  value-only components (ring, signal tile, trend chart, gauge, week strip, link tile, answer scale, progress bar).
- Tiles must never show a band or status no rule computes; missing data hides a tile instead of showing a dash.
- Charts and tinted surfaces raise the bar for contrast, Dynamic Type and VoiceOver: each UI task attaches light,
  dark and large-text screenshots, and the device review (#21) re-checks Today.
- Work is split into parallel tasks under [#211](https://github.com/droidsam1/overreach/issues/211).
