# Evidence register

Every rule in `Analytics` that recommends, proposes or evaluates something has an entry here (ADR-0012).
Levels: **strong** (meta-analyses / umbrella reviews / position stands built on them), **moderate** (RCTs or
low-certainty syntheses), **limited** (consensus, observational, mechanistic), **heuristic** (coaching default,
configurable). Keys are referenced from code as `EvidenceReference(key:level:)`.

Latest full review: `docs/evidence-review-2026-11.md` (2026-11-20), with open findings and proposed entries.

## Menstrual cycle

### `cycle-phase-performance` — limited (no phase-based rules)
No influence of cycle phase on acute strength or resistance-training adaptations shown by current evidence;
performance possibly trivially lower in the early follicular phase, low-quality evidence; individual approach
recommended. → Cycle used only as context (ADR-0009).
Refs: Colenso-Semple et al. 2023 (umbrella review); McNulty et al. 2020 (meta-analysis). Reviewed 2026-11-16.

### `cycle-luteal-nutrition` — moderate
Meet carbohydrate needs in all phases; protein 1.4–2.2 g/kg/day, upper end in the luteal phase; energy
availability first. Refs: ISSN position stand, Sims et al. 2023. Reviewed 2026-11-16.

## Daily activity

### `walking-active-recovery` — moderate
Active recovery gives a small-to-moderate reduction in DOMS and perceived fatigue vs passive rest.
Refs: Dupuy et al. 2018 (meta-analysis, 99 studies). Reviewed 2026-11-16.

### `walking-no-interference` — moderate
Interference scales with endurance-training frequency/duration; concurrent aerobic training does not
compromise hypertrophy or maximal strength (may blunt explosive strength, more within the same session than with
≥ 3 h between). Low-intensity walking is below that. Moderate, not strong: the trials are of structured endurance
training, and walking is an extrapolation (in the safe direction). Refs: Wilson et al. 2012; Schumann et al. 2022,
Sports Med 52:601 (meta-analyses). Reviewed 2026-11-20.

### `low-steps-exercise-resistance` — moderate
≈ 5,000 steps/day or fewer blunted the metabolic response to exercise; ≈ 8,500 protected it.
Refs: Burton & Coyle 2021 (randomised crossover). Reviewed 2026-11-16.

### `walking-load-baseline` — heuristic
Only walking above the 28-day personal baseline counts as extra load; weight starts low and is configurable.
Reviewed 2026-11-16.

## Progression engine

### `progression-load-or-reps` — moderate
Progressing by adding reps at a fixed load and by adding load at fixed reps gave similar hypertrophy and
strength in trained lifters over 8 weeks (strength slightly favoured load, of questionable practical size).
→ Double progression is the default; rep progression is a valid way to progress.
Refs: Plotkin et al. 2022, PeerJ 10:e14142 (RCT). Reviewed 2026-11-16.

### `proximity-to-failure` — strong
Hypertrophy improves as sets end closer to failure; strength gains are similar across a wide range of RIR.
→ Default target RPE 8 (≈ 2 RIR) for hypertrophy work; strength work does not need to approach failure.
Training to failure gave only a trivial hypertrophy advantage over stopping short (Refalo et al. 2023, 15 studies),
and 1–2 RIR matched failure for quadriceps growth in trained lifters over 8 weeks (Refalo et al. 2024).
Refs: Robinson et al. 2024, Sports Med 54(9) (dose-response meta-regression, 55 studies); Refalo et al. 2023, Sports
Med 53(3) (meta-analysis); Refalo et al. 2024, J Sports Sci (RCT). Reviewed 2026-11-20.

### `rir-based-rpe` — moderate
RPE scale anchored to reps in reserve (RPE = 10 − RIR). Loads for reps × RPE are derived from the estimated
1RM assuming a set of r reps at RIR behaves like a set of r + RIR to failure (Epley).
Refs: Zourdos et al. 2016, J Strength Cond Res; Helms et al. 2016. Reviewed 2026-11-16.

### `rir-estimation` — moderate
Estimates of reps in reserve were about 1 rep off on average, usually too low: people thought they had fewer reps
left than they did. A scoping review with exploratory meta-analysis (12 studies, 414 participants) found this,
with very high heterogeneity. Estimates are more accurate close to failure, in sets with fewer reps and with
heavier loads. Training experience did not clearly help (systematic review of 26 studies; findings conflict
between studies).
→ RPE and RIR are the same scale (RPE = 10 − RIR), and users choose how to log it. The effort guide warns about
the bias: when unsure, pick the value with more reps left.
Refs: Halperin et al. 2022, Sports Med 52(2):377–390; Russo et al. 2025, Phys Ther Rev 31(1) (systematic review).
Reviewed 2026-11-19.

### `rir-calibration` — heuristic
The guide suggests taking the last set of a safe exercise (a machine or an isolation exercise) to failure now and
then, to compare the estimate with what was possible. No trial shows this improves accuracy. Never with heavy
barbell lifts without safeties.

### `autoregulation-load` — moderate
Autoregulated (RPE/velocity) and percentage-based load prescription gave similar strength gains.
→ RPE-based scheme offered as an option, not as superior.
Refs: Hickmott et al. 2022, Sports Med Open 8:9 (meta-analysis, 15 studies). Reviewed 2026-11-16.

### `e1rm-estimation` — limited
Lifters under-predict reps to failure by ~1 rep on average and get less accurate in higher-rep sets.
→ e1RM uses sets of ≤ 12 reps; RPE < 6 is ignored (treated as a set to failure, a conservative estimate).
Refs: Halperin et al. 2022, Sports Med (meta-analysis). Cut-offs are heuristic. Reviewed 2026-11-16.

### `volume-dose-response` — strong
Weekly set volume has a positive dose-response with diminishing returns for hypertrophy (and smaller for
strength); counting indirect sets as 0.5 ("fractional") fits best. Per-session benefits plateau around ~11
fractional sets per muscle (preprint).
→ Effective sets per muscle use 1 / 0.5 weighting; stall suggestions add/remove a set relative to a
configurable 10–20 weekly fractional sets range (heuristic within the evidence).
Refs: Pelland et al. 2026, Sports Med 56(2):481–505 (meta-regressions, 67 studies); Remmert et al. 2025 (SportRxiv
preprint). Reviewed 2026-11-20 (`docs/evidence-review-2026-11.md`).

### `effective-set-threshold` — heuristic
A working set counts toward weekly volume from RPE 6 (≈ 4 RIR), or when no RPE is logged. Hypertrophy improves
gradually as sets end closer to failure, with no cliff at a given RIR, and strength gains are similar across a wide
RIR range; RIR estimates are also about 1 rep off. So only clearly easy sets are left out; the exact cut-off is a
default. Refs: Robinson et al. 2024, Sports Med 54(9) (meta-regressions); Pelland et al. 2026, Sports Med 56(2):481;
Halperin et al. 2022 (RIR accuracy). Reviewed 2026-11-20.

### `deload-design` — limited
Expert Delphi consensus defines a deload as a period of reduced training stress to mitigate fatigue and
enhance preparedness; typically reduced volume and/or intensity of effort, not complete rest.
Refs: Bell et al. 2023, Sports Med Open 9:87. Reviewed 2026-11-16.

### `deload-cost` — moderate
A 1-week training break mid-programme slightly reduced lower-body strength gains and did not change
hypertrophy. → Deloads are proposed from fatigue signals, not on a timer alone, and reduce training instead
of stopping it. Refs: Coleman et al. 2024, PeerJ 12:e16777 (RCT). Reviewed 2026-11-16.

### `stall-heuristics` — heuristic
Stall = no e1RM gain > 1 % over the last 3 exposures vs the 6 before, with ≥ 2 missed targets. Linear reset
−10 % after 3 misses; microload at half the increment when the miss was by 1 rep; variation swap 3–4 weeks.
All configurable. Reviewed 2026-11-16.

### `rpe-creep` — heuristic
Same load and reps over 3 exposures with RPE up ≥ 1 point → accumulated fatigue signal (weight 1).
Reviewed 2026-11-16.

### `weekly-load-change` — heuristic
The last 7 days' load against the usual week (mean of the 3 weeks before it, uncoupled). Above 1.5× it adds a weak
deload signal (weight 1, never enough on its own). It replaced the acute:chronic workload ratio (ACWR): the coupled
ratio (acute week inside the chronic window) creates a spurious acute–chronic correlation, the injury association
has been argued to be largely an artefact of the ratio, and window lengths are arbitrary. Never shown as injury
risk. Refs: Lolli et al. 2019, Br J Sports Med 53:921; Impellizzeri et al. 2020, Int J Sports Physiol Perform
15:907; Impellizzeri et al. 2021, Sports Med 51:581. Reviewed 2026-11-20.

### `deload-practice` — limited
Competitive strength and physique athletes deload for about 6 days every 5–6 weeks, mainly to manage fatigue,
reducing volume and load and raising RIR while keeping frequency and exercises (cross-sectional survey, n = 246).
→ The planned interval (default 6 weeks) adds one point to a deload proposal; it never triggers one alone.
Refs: Rogerson et al. 2024, Sports Med Open 10:22. Reviewed 2026-11-20.

## Warm-up

### `warm-up-general` — moderate
In a meta-analysis of 32 studies, a warm-up improved performance in 79 % of the outcomes studied. Before a
leg-press 1RM, 20 minutes of easy cycling added to the specific warm-up raised the 1RM by about 8 % (crossover,
n = 13). In another crossover study, warm-up conditions did not change reps to failure at 80 % 1RM.
→ The logger offers an optional tip (5–10 minutes of easy cardio) until the first set. It is never added to the
session.
Refs: Fradkin et al. 2010, J Strength Cond Res 24(1):140–148 (systematic review and meta-analysis); Abad et al.
2011, J Strength Cond Res 25(8):2242–2245; Ribeiro et al. 2014, Rev Bras Cineantropom Desempenho Hum.
Reviewed 2026-11-19.

### `warm-up-specific` — moderate
Specific warm-up sets give mixed results across 11 studies. A general warm-up followed by a low-volume specific
warm-up is suggested.
- **Squat:** one set at about 80 % of the training load gave higher bar velocity than one at 40 % (trained men,
  crossover).
- **Bench press:** a progressive 40 % → 80 % warm-up gave more total work. Light-only warm-ups were the weakest.
- **Training volume:** 5 reps at 80 % of the 10RM gave more total volume than 10–15 reps at 40–60 %.

→ Warm-ups end close to the working load (about 80 %, 90 % for heavy work) with few reps. Muscles already
worked earlier in the session get a single set. Warm-up sets are saved as warm-ups and never count for progress or
volume.
Refs: Ribeiro et al. 2021, Motricidade 17(1) (systematic review); Ribeiro et al. 2020, Int J Environ Res Public
Health 17(18):6882; Viveiros et al. 2024, J Bodyw Mov Ther 40:1487–1491. A 2026 scoping review on the topic (Neves
et al., J Sci Sport Exerc) was retracted and is not used. Reviewed 2026-11-19.

### `warm-up-ramp` — heuristic
The number of steps and their percentages and reps come from 1RM-testing practice and coaching defaults:
- heavy work (about 80 % 1RM or more): 40 % × 5, 60 % × 3, 80 % × 2, 90 % × 1;
- moderate work: 50 % × 6, 80 % × 4;
- light work: 60 % × 6.

Warm-up reps never exceed the working reps. Loads are rounded to the exercise's increment, never below the empty
20 kg bar for barbell lifts. Warm-ups are added automatically for main lifts and for the first exercise that
works a muscle in the session; the other exercises get them on demand.

## Training focus and blocks

### `loading-by-goal` — strong
1RM gains are larger with heavy loads (> 60 % 1RM); hypertrophy is similar across a wide loading range when sets
go to or near failure. → Strength focus uses heavy loads; hypertrophy focus is flexible on load.
Refs: Schoenfeld et al. 2017, J Strength Cond Res 31:3508 (meta-analysis, 21 studies); Lopez et al. 2021, Med
Sci Sports Exerc (network meta-analysis); Schoenfeld et al. 2021, Sports 9:32 (review). Reviewed 2026-11-16.

### `rest-hypertrophy` — moderate
Small hypertrophy benefit of rests > 60 s; no appreciable difference beyond ~90 s. → Hypertrophy rest 90–180 s.
Refs: Singer et al. 2024, Front Sports Act Living 6:1429789 (Bayesian meta-analysis, 9 studies). Reviewed
2026-11-16.

### `rest-strength` — moderate
Longer rests (3 min vs 1 min) improved strength and hypertrophy in trained men. → Strength rest 3–5 min.
Refs: Schoenfeld et al. 2016, J Strength Cond Res (RCT). Reviewed 2026-11-16.

### `periodization` — moderate
With volume equated, periodised training improves 1RM more than non-periodised, not hypertrophy; undulating
beats linear for 1RM in trained lifters. Linear vs daily undulating give similar hypertrophy.
→ Block suggestions for strength goals; for hypertrophy goals periodisation is optional.
Level: one meta-analysis of short, heterogeneous studies with an effect only on 1RM, so moderate (was strong until
the 2026-11-20 review); no newer synthesis found.
Refs: Moesgaard et al. 2022, Sports Med 52:1647 (meta-analysis, 35 studies); Grgic et al. 2017, PeerJ 5:e3695.
Reviewed 2026-11-20.

### `focus-heuristics` — heuristic
Set classification cut-offs (≤ 6 reps at ≥ 78 % e1RM = strength; ≥ 15 reps = endurance; 60 % majority), streak
lengths, block lengths (4–8 weeks), templates and deload placement. All configurable. Reviewed 2026-11-16.

## Training plans

### `frequency-volume-equated` — strong
With weekly volume equated, how many days a week a muscle is trained makes no difference to hypertrophy and a small
one to strength; most of the apparent benefit of higher frequency comes from the extra volume. The follow-up text
says so ("about the same muscle and nearly the same strength").
→ When planned sessions keep being missed, the follow-up proposes fewer sessions a week (the user keeps their
weekly sets in fewer, fuller sessions) instead of a plan they cannot keep.
Refs: Schoenfeld, Grgic & Krieger 2019, J Sports Sci 37:1286 (meta-analysis, 25 studies); Grgic et al. 2018,
Sports Med 48:1207 (meta-analysis, strength); Saric et al. 2019, J Strength Cond Res 33:S122 (RCT, trained men,
3 vs 6 sessions); Pelland et al. 2026, Sports Med 56(2):481 (meta-regressions: with volume equated, frequency
still has a small effect on strength, none on hypertrophy). Reviewed 2026-11-20.

### `retraining-after-break` — moderate
A break of up to ~10 weeks lowers strength and size, but they come back quickly with retraining, and after a
second training block the outcomes match continuous training. Strength is kept better than size. Evidence on how
long gains last without training is thin and mostly in untrained or older people.
→ After 14 days or more without strength sessions, the follow-up says to keep the plan and ease back in, rather
than restart or shorten it.
Refs: Halonen et al. 2024, Scand J Med Sci Sports 34:e14739 (RCT, n = 55); Ogasawara et al. 2011, Clin Physiol
Funct Imaging 31:399 (randomised, PubMed 21771261); Encarnação et al. 2022, Muscles 1:1 (systematic review); Grgic 2022, Int J Environ Res
Public Health 19:14048 (meta-analysis, older adults). Reviewed 2026-11-19.

### `illness-return` — limited
For acute respiratory illness in athletes, return to training is decided by symptoms, severity and warning signs,
not by a fixed timeline; most cases cost a few days.
→ A recent "ill" check-in replaces every other proposal with "rest until the symptoms ease, then come back
gradually". The app never says when it is safe to train: it is not a medical device.
Refs: Schwellnus et al. 2022, IOC consensus, Br J Sports Med 56:1066; Snyders et al. 2022, Br J Sports Med
(systematic review, 54 studies). Reviewed 2026-11-19.

### `easy-strength-example` — heuristic

On an amber day with no strength workout detected today, Today can show a separate light example. The next
undated routine supplies the reference, using ordinary progression targets. If it has no recently performed
exercises, a recent logged session supplies examples instead. A session with insufficient information falls back
to an effort cue. Workouts already logged today or captured by the watch suppress the example.

The defaults are up to three exercises performed in the last 42 days, up to two working sets per exercise
(roughly half the reference, with one as the minimum), repetitions within the reference and recent exposure,
and at least four repetitions in reserve. A lower reference effort is respected. A qualitative load cue avoids
assuming a specific weight will feel light today. The opt-in example creates no session and has no effect on
the rotation. Reduced volume and effort are used in deload practice. The studies support neither these exact
numbers nor prescribing this example from HRV. Reviewed 2026-11-20. [Deload consensus](https://doi.org/10.1186/s40798-023-00633-0) · [Athlete survey](https://pubmed.ncbi.nlm.nih.gov/38499934/) · [Repetitions in reserve](https://pubmed.ncbi.nlm.nih.gov/27531969/)

### `plan-adherence` — heuristic
A break is 14 days without strength sessions; low adherence is under two thirds of planned sessions over the last
two finished weeks of a block; the proposed frequency is the sessions actually done per week, rounded up;
missed sessions add whole weeks to the block, at most 4 in all, and each missed week is offered once. All
configurable. Reviewed 2026-11-19.

## Readiness

The daily traffic light on Today (ADR-0020). Each signal compares today with the person's own baseline; how they
combine is a labelled heuristic.

### `readiness-hrv` — moderate
HRV-guided training (train hard while the 7-day rolling ln HRV is inside the personal normal range, easy when it
drops below) gives similar or slightly better endurance and VO2max changes than predefined plans, with fewer
non-responders and better vagal HRV; effects on performance are trivial to small and the trials are few.
A 7-day rolling average is more valid than a single morning value, and needs at least ~3 valid nights a week.
The one RCT of HRV-guided resistance training found no advantage for strength or muscle (small sample, older
women), so HRV only moderates intensity here and never decides the strength plan alone.
→ Baseline = mean ± 0.5 SD of ln nightly HRV over the previous 60 days (≥ 14 nights); signal when the 7-day mean
(≥ 3 nights) is below that range. Apple Watch reports SDNN, not RMSSD, and wearable HRV agrees only loosely
with chest-strap references: the same personal-range rule is applied to whatever the source reports, which is a
heuristic transfer, and only ever within one statistic (`hrv-metrics`).
→ Readiness reports the number of comparable daily readings actually used in the rolling window and indicates
when either window has insufficient coverage. Missing, non-positive and non-finite values are excluded. The
calendar windows retain their existing overlap, and the displayed count does not change the decision threshold.
→ The Today details distinguish observed readings, the app's reference window and the remaining uncertainty about
the cause. Recent workouts are aligned by local date to the latest comparable reading. Date order does not establish
the precise sleep or measurement interval. For easy-run copy, conversational effort is a practical cue rather than
a conversion to a particular zone system. [Foster et al., talk-test study](https://pubmed.ncbi.nlm.nih.gov/18277826/)
Refs: Düking et al. 2021, J Sci Med Sport 24:1180 (meta-analysis, wearables); Manresa-Rocamora et al. 2021, Int
J Environ Res Public Health 18:10299 (meta-analysis); Granero-Gallegos et al. 2020, Int J Environ Res Public
Health 17:7999 (meta-analysis); Vesterinen et al. 2016, Med Sci Sports Exerc 48:1347 (RCT, SWC protocol); Plews
et al. 2012, Eur J Appl Physiol 112:3729 (7-day rolling average); Front Physiol 2024, 15:1472702 (RCT,
HRV-guided resistance training, n = 21); Sensors 2024, 24:6220 (Apple Watch HRV validity). Reviewed 2026-11-19.

### `hrv-metrics` — strong
RMSSD and SDNN are different statistics: RMSSD reflects beat-to-beat (vagal) variation, SDNN the total variation
over the recording, and both depend on recording length. Their values and norms differ, so a baseline built with one
cannot judge the other. Garmin reports nightly RMSSD (Personal API `lastNightAvg`); Apple Health stores
`heartRateVariabilitySDNN` from short Apple Watch readings. Athlete monitoring is usually built on ln RMSSD.
→ Every HRV value carries its statistic (`HRVMetric`); readiness baselines and Today's 7-day average only use nights
of the same statistic as the latest night. Switching watches starts a new baseline (14 nights) instead of a false
drop or rise (ADR-0024). Refs: Task Force of the ESC and NASPE 1996, Circulation 93:1043 (standards); Shaffer &
Ginsberg 2017, Front Public Health 5:258 (review of HRV metrics and norms); Plews et al. 2013, Sports Med 43:773
(ln RMSSD for athlete monitoring). Reviewed 2026-11-20.

### `hrv-metric-type` — moderate
SDNN and RMSSD measure different things (overall vs beat-to-beat variability; short-term SDNN tracks LF power,
r = 0.90–0.94), RMSSD is the more robust metric in short recordings, and no conversion between them exists.
Wearable HRV is comparable only within one device and one metric.
→ Apple Watch SDNN and Garmin RMSSD use separate baselines (`hrv-metrics`). The [research note](design/hrv-sources.md)
compares the two inputs and motivates preserving both values when they are available for the same night.
Refs: Esco 2026, J Funct Morphol Kinesiol 11:304 (narrative review); Shaffer & Ginsberg 2017, Front Public Health
5:258 (review); Munoz et al. 2015, PLoS One 10:e0138921 (n = 3,387); Doherty et al. 2025, Transl Exerc Biomed
(review of 14 composite scores). Reviewed 2026-11-20.

### `wearable-hrv-validity` — moderate
Wrist HRV is inaccurate in absolute terms but reliable enough for a personal trend. Nocturnal RMSSD vs chest-strap
ECG (536 nights): Garmin Fenix 6 CCC 0.87, MAPE 10.5 %, behind Oura (0.97–0.99) and WHOOP (0.94); against each
person's own baseline (nightly Z-scores) Garmin agreed least (CCC 0.77). Garmin Elevate v4 (short supine and seated
recordings): test–retest ICC 0.84 / 0.79, proportional bias, individual errors from −43 % to +118 %. Apple Watch
S9/Ultra 2 SDNN from 5-minute morning Breathe readings: −8.3 ms bias, limits of agreement −53.8 to +37.2 ms, MAPE
28.9 %, outside a ±10 ms equivalence margin; no validation of the passive nocturnal SDNN (3–4 spot readings a
night) that Health stores.
→ Interpret wearable HRV against the person's own baseline for the same device. The use of passive Apple Watch
SDNN in the readiness rule remains a heuristic transfer. Refs: Dial et al. 2025, Physiol Rep 13:e70527;
Sensors 2026, 26:6549 (Elevate v4, n = 23);
O'Grady et al. 2024, Sensors 24:6220; Miller et al. 2022, Sensors 22:6317. Reviewed 2026-11-20.

### `hrv-nocturnal` — moderate
Nocturnal HR and RMSSD are reliable, have a low typical error and respond to the preceding training load; their
response to two weeks of overload tracked 3000 m performance changes, while morning values responded differently.
→ Nightly averages are a valid input for the 7-day rolling rule. Refs: Nuuttila et al. 2022, Int J Sports Physiol
Perform 17:1296; Nuuttila et al. 2024, Sports Med Open 10:120; Mishica et al. 2022, PLoS One 17:e0262333.
Reviewed 2026-11-20 (full texts checked).

### `composite-scores` — limited
Device scores (Garmin HRV status and baseline, Body Battery, training readiness, other brands' readiness and
recovery) have undisclosed inputs, weights and baselines and no rigorous independent validation; they can change
without notice.
→ Shown as context, labelled as the device's, never a rule input. Refs: Doherty et al. 2025, Transl Exerc Biomed,
doi 10.1515/teb-2025-0001; Garmin HRV status documentation. Reviewed 2026-11-20.

### `hrv-cycle-phase` — moderate
Vagally mediated HRV falls from the follicular to the luteal phase (d = −0.39, 37 studies), and within-person
studies tie it to higher progesterone. → Until phase-aware baselines exist (ADR-0009), for people who track a
natural cycle a low HRV is shown with the cycle as a possible cause (`hrvMayReflectCycle`) and does not count
towards red; other signals still do. Refs: Schmalenberger et al. 2019, J Clin Med 8:1946 (meta-analysis).
Reviewed 2026-11-20.

### `readiness-resting-hr` — limited
Short-term overload raises resting HR moderately, longer overload does not, and changes must be read together with
other signs; daily resting measures are most useful next to training logs and questionnaires.
→ Signal when today's resting HR is ≥ 5 bpm above its 60-day mean (≥ 14 nights). The 5 bpm threshold is a
coaching default (configurable). Refs: Bosquet et al. 2008, Br J Sports Med 42:709 (systematic review, PubMed
18308872); Buchheit 2014, Front Physiol 5:73 (review). Reviewed 2026-11-19.

### `readiness-sleep` — moderate
Acute sleep loss lowers performance: about −3 % for maximal strength and more for endurance and
strength-endurance, with high heterogeneity; the effect likely grows over several short nights. Athletes often
sleep < 7 h, and sleep need is individual rather than a fixed 7–9 h.
→ Signal when last night was under 6 h (configurable; a personal sleep baseline is a later refinement).
Refs: Craven et al. 2022, Sports Med 52:2669 (meta-analysis); Walsh et al. 2021, Br J Sports Med 55:356 (expert
consensus). Reviewed 2026-11-19.

### `readiness-subjective` — moderate
Self-reported well-being responds to acute and chronic training load more sensitively and consistently than common
objective markers, and the two often disagree, so both are worth collecting.
→ Check-in energy ≤ 2 / 5 and soreness 3 / 3 are one signal each. Refs: Saw, Main & Gastin 2016, Br J Sports Med
50:281 (systematic review, 56 studies). Reviewed 2026-11-19.

### `readiness-context-prompt` — heuristic

Below-range HRV prompts a question about recent unusual stress. When resting heart rate is also above the
personal reference, the first question asks whether new symptoms make the user feel too unwell to train.
Daily-life HRV can vary with perceived stress and physical activity. The exact prompt and its priority are
product heuristics. Stress is shown as self-reported context and has no weight in the traffic light. A negative,
unsure or skipped answer neither clears the athlete to train nor counts as evidence of illness. Questions and
answers apply only to the current day. Reviewed 2026-11-20. [Daily-life study](https://pubmed.ncbi.nlm.nih.gov/39032150/)

### `readiness-reported-symptoms` — limited

When the athlete reports that new symptoms make them feel too unwell to train, Today suggests skipping the
session and reassessing how they feel. This extends the existing symptom-led approach to a direct self-report,
without a diagnosis or a time to return. The IOC guidance applies to acute respiratory illness in athletes and
considers symptoms and severity for return decisions. A wearable deviation only selects a question. The app
offers no symptom-specific triage in this flow. Reviewed 2026-11-20. [IOC consensus](https://doi.org/10.1136/bjsports-2022-105759)

### `readiness-combination` — heuristic
Sick in the check-in → red (see `illness-return`). No signal → green; one or more → amber; two or more with at
least one of HRV or resting HR → red. Subjective and sleep signals alone never make it red. Nothing to judge
(no baseline, no sleep, no check-in) → unknown. Phase-aware baselines for naturally cycling users (ADR-0009)
are not applied yet. All thresholds configurable. Reviewed 2026-11-19.

## Wearable data

How Today presents numbers from the devices (evidence review 2026-11, §5). Only measured values and Overreach's own
calculations feed rules; the devices' estimates are shown as such.

### `wearable-sleep-stages` — limited
Consumer wrist devices detect sleep well but agree only fairly to moderately with polysomnography on stages
(κ ≈ 0.2–0.5 across six devices); an Apple Watch Series 8 underestimated deep sleep by about 43 minutes.
→ Deep and REM sleep are shown as "watch estimate" and never feed a rule. Refs: Schyvens et al. 2025, Sleep Adv
6(2):zpaf021; Apple Watch S8 validation 2024. Reviewed 2026-11-20.

### `wearable-vo2max` — moderate
Exercise-based watch VO2max estimates are acceptable at group level but have wide individual error; resting-based
ones overestimate. → Shown as a watch estimate to follow as a trend. Refs: Molina-García et al. 2022, Sports Med
52:1577 (meta-analysis, INTERLIVE). Reviewed 2026-11-20.
