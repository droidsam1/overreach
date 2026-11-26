# Visual Today

The layout and tokens behind [ADR-0042](../adr/0042-visual-today.md). Tasks:
[#211](https://github.com/droidsam1/overreach/issues/211). The approved mock-ups are on the owner's design canvas
(<https://claude.ai/artifact/5CQuDjZDbAvQZYFH4wda6D>); this page is the source of truth for agents.

## Tokens

Dark values are from the mock-ups; light values are chosen in #212 with the same roles and at least 4.5:1 for text.

| Role | Green | Amber | Red | Done | Neutral |
| --- | --- | --- | --- | --- | --- |
| Accent (ring, badge, button) | `#4ADE80` | `#F5A524` | `#F87171` | `#A78BFA` | `#9CA3AF` |
| Surface (hero card) | `#13261B` | `#2A1F0C` | `#2A1212` | `#1E1836` | `#1A1D22` |
| Border | `#1F4A31` | `#5A4116` | `#5A1E1E` | `#3A2E66` | none |
| Symbol | ✓ | – | ✕ | ✓ | ? |

Other colours: page `#0E1013`, card `#1A1D22`, inner tile `#2A2E35`, secondary text `#A1A7B0`. Kinds: strength violet
`#A78BFA`, run blue `#5AA9FF`, sleep teal `#2DD4BF`, rest green. Typography uses the system font, with a large title for "Today", heavy title2 for the verdict and
heavy title3 for values.

| Role | DesignSystem token | Points |
| --- | --- | --- |
| Hero and week card corners | `Radius.card` | 24 |
| Compact card and tile corners | `Radius.tile` | 16 |
| Card padding | `Spacing.medium` by default | 16 |
| Gap between blocks | `Spacing.large` | 24 |

## Hero

Ring (88 pt) · badge "Green · Ready" · verdict · one reason line. Below: three signal tiles in a row, then the full-width
accent button with the verb. Deload, safety and loading states use the same card.

## Signal tiles

Title, value + unit, compact trend (7–14 days) over the shaded personal band, status line. The tile behind an amber or
red verdict has an accent border and the status in the accent colour with an arrow. Order: leading reason, then HRV,
sleep, resting HR; ACWR ("Load") replaces one when it is a reason. Missing data hides a tile. Tap opens Why.

## Your week

Header "Your week" + block week on the right. Seven-day strip: filled circle for done (strength, run), green outline
with moon for rest logged, outline for planned, highlighted ring for today, dashed for nothing. Progress bar with
strength and run segments and one summary line. Divider, then today's session: icon tile, title, one detail line,
tag "Today" or "Adjusted" (the planned run struck through when the advice changed it).

## Pending prompt

Card with title, why it matters, dismiss (×). The check-in shows five options (symbol + word) answered with one tap,
and "More: sleep, stress, pain…". Other prompts keep their content in the same card.

## Link tiles

Grid of 3–4 tiles (Why · Options · Recovery · History): coloured icon at the top, label at the bottom, 70–76 pt high. Recovery and History switch to their tab; Why and Options push level-2
screens inside Today.

## Why

Back to Today; title "Why "<verdict>"?". "What weighs" segmented bar with legend. One card per reason with a signal:
value, 14-night chart over the band with out-of-band points in the accent, one sentence, evidence pill and source
link; ACWR as a gauge with its usual zone. Normal signals as two small cards. Rows: training that counts, sources and
coverage, further reading.

## After training

Hero in the done tone: full ring with ✓, "Push A completed", "Recovery is part of the plan". Three totals, a record
row with a trophy when the session set one, then Your week with tomorrow's session. "Log another activity" as a
bordered button. Rest logged uses the same layout in green.
