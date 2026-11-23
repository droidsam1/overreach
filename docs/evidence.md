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
Newer work agrees: no day of the cycle disadvantages eumenorrheic women in strength or power (Blagrove et al.
2020), a 2025 NSCA review finds the case for phase-based periodization lacking, and a phase-periodized pilot gave
no advantage over usual training (Vargas-Molina et al. 2022). Oral contraceptive users show trivially lower
performance than naturally cycling women (Elliott-Sale et al. 2020), not a reason to change loads.
Refs: Colenso-Semple et al. 2023, Front Sports Act Living 5:1054542 (umbrella review); McNulty et al. 2020, Sports
Med 50:1813 (meta-analysis); Blagrove et al. 2020, J Sci Med Sport 23:1220 (meta-analysis); Elliott-Sale et al.
2020, Sports Med 50:1785 (meta-analysis); Vargas-Molina et al. 2022, J Strength Cond Res (pilot RCT).
Reviewed 2026-11-20.

### `cycle-phase-baselines` — moderate (heuristic windows)
Within a natural cycle, wearable signals shift with phase: nocturnal resting HR and skin temperature rise in the
mid and late luteal phase (about +2 to +5 bpm vs the early follicular phase), and time-domain HRV (RMSSD/SDNN) is
3–9 % lower late vs early in the cycle, up to ~16 % RMSSD in the late luteal phase. Sleep metrics do not shift
consistently. A whole-cycle baseline therefore makes normal luteal values look like poor recovery.
→ For people who track a natural cycle and have a confident phase estimate, the HRV and resting-HR signals compare
today with the same phase window (follicular vs luteal) of previous cycles once ≥ 2 cycles have data in that
window; until then a low HRV keeps `hrvMayReflectCycle` and the resting-HR threshold widens by 3 bpm in the luteal
window. Window sizes, the 2-cycle minimum and the 3 bpm widening are labelled heuristics.
Refs: living systematic review of wearable HRV across the cycle, Sports Med 2025, doi 10.1007/s40279-025-02388-y;
Schmalenberger et al. 2019, J Clin Med 8:1946 (meta-analysis); Alzueta et al. 2022, Int J Womens Health 14:491,
doi 10.2147/IJWH.S341917; Goodale et al. 2019, J Med Internet Res 21:e13404. Reviewed 2026-11-20.

### `cycle-phase-estimation` — moderate (limits)
Real-world cycles vary: in 612,613 tracked cycles the mean length was 29.3 days, the follicular phase averaged 16.9
days and the luteal 12.4 days, but the luteal phase still ranged 7–19 days, so "start − 14" is an approximation. Counting days from
the period start cannot verify phase: research best practice needs urinary LH and serum progesterone, and
calendar-only studies are judged low validity.
→ The app estimates only coarse windows from period starts in Health (menstrual, follicular, luteal, late luteal),
never ovulation or fertility, with a confidence that drops with few cycles, a cycle-length spread > 7 days, cycles
outside 21–35 days or an overdue period. Low confidence → no phase is used. Refs: Bull et al. 2019, npj Digit Med
2:83; Elliott-Sale et al. 2021, Sports Med 51:843 (methodological recommendations); 2025 audit in J Sports Sci,
doi 10.1080/02640414.2025.2583013. Reviewed 2026-11-20.

### `cycle-symptoms` — moderate
Most athletes report cycle symptoms (~74 % negative symptoms, ~32 % dysmenorrhoea; ~4 % miss training), but which
phase and how much varies widely between people and studies; few athletes plan training around the cycle.
→ Symptoms logged in the check-in drive autoregulation (RPE-based targets) on the day, for any phase; the reason
names the symptom, never the phase. Refs: Taim et al. 2023, Sports Med 53:1963 (systematic review, 60 studies,
6,380 athletes); McNamara et al. 2022, Front Physiol 13:964238 (survey, 1,086 athletes); JSAMS 2024 scoping review.
Reviewed 2026-11-20.

### `cycle-hormonal-contraception` — limited
Combined oral contraceptives suppress the natural hormone cycle; in the active-pill phase resting HR is higher and
RMSSD lower than in the pill-free week, mostly explained by HR. Users also show lower HRV than naturally cycling
women. → With hormonal contraception or menopause no phase is estimated and the overall baseline is used; the
pill-week effect is too small and inconsistent for a rule. Refs: Stone et al. 2026, Physiol Rep,
doi 10.14814/phy2.71175; wearable HRV living review (Sports Med 2025). Reviewed 2026-11-20.

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
A dog-walk tag adds context in Today. The same walking minutes feed the baseline and load with or without a tag.
Implemented defaults (`EverydayMovement.Settings`): the baseline is the median of the 28 days before, used from
14 days with data; a walking spike is ≥ 60 min above the usual walking minutes; "far below" is under both half the
usual steps and 5,000 steps (`low-steps-exercise-resistance`) on each of the last 3 complete days.
Walks found in step counts (`StepWalkDetection.Settings`): at least 10 minutes of 60–140 steps a minute, with
pauses of up to 3 minutes inside one walk. 60 steps/min separates walking from pottering about; above ≈ 140
steps/min people usually run, so those minutes are left out. Both are product heuristics.

For weekly load, excess minutes are allocated proportionally across bouts. Effort is estimated as ten times
the HR reserve fraction, bounded to 1–3. Without usable HR reserve, effort is 1, multiplied by 1.3 at 50 m of
ascent per kilometre. The walking estimate contributes at weight 0.25 to the weekly comparison. These values
are product heuristics. A small crossover study found next-day soreness after downhill walking. Ascent data
only adjusts the fallback load estimate. The warm-up cue asks the athlete to check for fatigue.
Reviewed 2026-11-21. [Downhill walking trial](https://pubmed.ncbi.nlm.nih.gov/29679309/)

## Progression engine

### `dog-walk-suggestion` — heuristic
Overreach asks "With <dog>?" on walks of 10 minutes or more that nobody has answered. With fewer than 10 answered
walks it asks on every one. Afterwards it asks only within ±45 minutes of a usual slot, a time of day with at least 3
confirmed dog walks in the last 28 days; a slot whose last 5 answers are all "No" stops asking, and weekend slots are
learned apart once weekends have 10 answers of their own. Implemented in `DogWalkSuggestion`. Product heuristics to
keep the question rare once learned; none is a clinical rule. Reviewed 2026-11-22.

### `first-progression` — heuristic
Repeat the first session as a starting point. Progressive overload for long-term adaptation can come from
load or reps. Plotkin et al. compared both in trained lifters over eight weeks and found broadly similar
adaptations. Chaves et al. compared both in untrained adults over ten weeks and found similar quadriceps
growth, with a larger gain on the leg-extension 1RM in the load group. These trials support offering both
options and leave the size and timing of each increment open. ACSM's historical
2009 guideline suggested increasing load by 2–10% after exceeding the rep goal by one or two reps on two
consecutive sessions. The 2026 update discusses individualizing the stimulus and gives no universal
session-to-session step. Overreach's equipment increments, effort gate, two-rep range extension and
5%/10% caps are product heuristics. They are not estimates of the optimal training dose.
Refs: [ACSM 2026](https://pmc.ncbi.nlm.nih.gov/articles/PMC12965823/),
[ACSM 2009](https://pubmed.ncbi.nlm.nih.gov/19204579/),
[Plotkin et al. 2022](https://doi.org/10.7717/peerj.14142),
[Chaves et al. 2024](https://pubmed.ncbi.nlm.nih.gov/38286426/). Reviewed 2026-11-20.

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
[Pancar et al. 2026](https://doi.org/10.1038/s41598-026-40612-5) found similar eight-week hypertrophy
and strength-endurance with two reduced-volume weeks in untrained men. The trial did not test when to prescribe
a reduction. Overreach's fatigue requirement is a product heuristic ([ADR-0036](adr/0036-deload-needs-fatigue.md)).
Refs: Bell et al. 2023, Sports Med Open 9:87. Reviewed 2026-11-21.

### `deload-cost` — moderate
A 1-week training break mid-programme slightly reduced lower-body strength gains and did not change
hypertrophy. → Deloads are proposed from fatigue signals, not on a timer alone, and reduce training instead
of stopping it. Refs: Coleman et al. 2024, PeerJ 12:e16777 (RCT). Reviewed 2026-11-16.

### `deload-recovery-signals` — limited
No single recovery marker identifies accumulated fatigue: the ECSS/ACSM consensus treats overtraining as a diagnosis
of exclusion built on a sustained performance decrement plus mood and other signs. Resting HRV and resting HR are
largely unchanged in functional overreaching in meta-analysis (Bellenger 2016); weekly-averaged vagal HRV can even
rise (parasympathetic hyperactivity, Manresa-Rocamora 2021), so a low-HRV rule misses part of overreaching and is
never decisive. Self-reported well-being tracks load more sensitively than objective markers (Saw 2016), and short
sleep lowers performance (Craven 2022).
→ Recovery signals only reinforce a deload that training already suggests: each adds 1 point, at most 2 in total,
and a proposal still needs a lift signal (stalls, an e1RM drop or RPE creep). A proposal also needs at least one
fatigue signal. Recovery signals count only when
sustained over the last 7 days (HRV 7-day trend below the personal range on ≥ 5 days, judged within one HRV
statistic, ADR-0024; resting HR ≥ 5 bpm above its baseline on ≥ 4 days; < 6 h sleep on ≥ 4 nights; low energy or
high soreness in ≥ 3 check-ins). Being sick in the last 7 days replaces the deload with a return-to-training note
(`illness-return`). Garmin stress and Body Battery are proprietary scores without validation for this and are not
used. Phase-aware baselines (ADR-0009) are not applied yet. Refs: Meeusen et al. 2013, Eur J Sport Sci 13:1 and Med
Sci Sports Exerc 45:186 (ECSS/ACSM joint consensus); Bellenger et al. 2016, Sports Med 46:1461 (systematic review
and meta-analysis); Manresa-Rocamora et al. 2021, Scand J Med Sci Sports 31:1164 (meta-analysis); Saw, Main &
Gastin 2016, Br J Sports Med 50:281 (systematic review); Craven et al. 2022, Sports Med 52:2669 (meta-analysis).
Reviewed 2026-11-20.

### `deload-life-stress` — limited

Training and life demands add up: the 2018 consensus on recovery frames the balance between stress (training load
and other life demands) and recovery as what sustains performance. In students lifting weights, higher life
stress went with worse recovery of muscle function over 96 hours (Bartholomew 2008; Stults-Kolehmainen 2012, 2014;
small, observational) and smaller strength gains over 12 weeks. In a collegiate team, HRV changes that look like
fatigue can come from non-training factors, so the fix may be life stress or sleep, not less training (Flatt et al.
2018). Exercise itself is not a stressor to avoid: a single bout lowers blood pressure and cortisol reactivity to
stress, with higher intensity giving larger reductions, and self-reported stress changes little (2024 systematic
review, 31 studies); exercise programmes lower anxiety and depressive symptoms (resistance training: Gordon 2018,
Conn 2010 for activity in general), and for perceived stress the pooled evidence is thin. No study tests which
exercise is best for a stressed athlete, or whether harder is better.
→ A yes to the stress question (last 14 days) keeps the proposal's score and changes the week to a steadier one:
same days, 75 % of the sets, about 5 % less load, RPE 8 at most, with no sets to failure and a prompt to protect
sleep and keep moving at a comfortable effort. Stress alone never proposes a week. No stress is inferred from the
device ([ADR-0038](adr/0038-life-stress-in-deload-proposals.md)). The multipliers are product heuristics.
Refs: [Kellmann et al. 2018](https://pubmed.ncbi.nlm.nih.gov/29345524/), Int J Sports Physiol Perform 13:240
(consensus); Bartholomew et al. 2008 ([PubMed 18545186](https://pubmed.ncbi.nlm.nih.gov/18545186/)),
Stults-Kolehmainen et al. 2012 ([22688829](https://pubmed.ncbi.nlm.nih.gov/22688829/)) and 2014
([24343323](https://pubmed.ncbi.nlm.nih.gov/24343323/)) on life stress, recovery and strength gains; Flatt et al.
2018 (HRV and non-training factors in collegiate swimmers); [J Behav Med 2024](https://link.springer.com/10.1007/s10865-024-00470-w)
(acute exercise and stress reactivity); Gordon et al. 2018, JAMA Psychiatry (resistance training and depressive
symptoms); Conn 2010 ([PubMed 20410849](https://pubmed.ncbi.nlm.nih.gov/20410849/), activity interventions and
anxiety). Reviewed 2026-11-21.

### `unplanned-deload` — heuristic

Bell et al. [2023 Delphi](https://pmc.ncbi.nlm.nih.gov/articles/PMC10511399/) and
[2024 athlete survey](https://pmc.ncbi.nlm.nih.gov/articles/PMC10948666/) support looking for a short period
of reduced training stress and volume. Retrospective detection in hybrid athletes is an Overreach heuristic.
Overreach checks seven complete calendar days against recent training and, for matched strength routines,
reconstructed progression targets. The 50% and 65% load ratios, effort cutoffs, running-duration fallback,
and one-week grace period for repeat advice are product heuristics. A break in logging can require
confirmation before it counts as recovery. Plan prioritizes up to two unanswered periods from the last 12 weeks
after the last strength recovery. Today uses the same selection and asks when the answer would change a deload
proposal. The display limit and review window are product heuristics. Performance drops only compare sessions
since the last recovery period (ADR-0033). The last recovery is the latest
accepted deload week or counted period (`RecoveryHistory`), and no deload is proposed in the 7 days after it.
Reviewed 2026-11-21.

### `training-breaks` — heuristic

[Coleman et al. 2024](https://peerj.com/articles/16777/) found similar hypertrophy after a one-week strength break
in a nine-week trial, with greater strength gains in the continuous-training group.
[Chen et al. 2022](https://pubmed.ncbi.nlm.nih.gov/33517866/) found lower VO₂max after two weeks of detraining in
15 endurance-trained men. These studies examine cessation in single disciplines. Counting seven complete days as
rest, using 14 days to start a return period, requiring four weeks before a strength deload and advising an easy
pace for the first two runs are product heuristics. See [ADR-0037](adr/0037-training-breaks-by-discipline.md).
Reviewed 2026-11-21.

### `stall-heuristics` — heuristic
Stall = no e1RM gain > 1 % over the last 3 exposures vs the 6 before, with ≥ 2 missed targets. Linear reset
−10 % after 3 misses; microload at half the increment when the miss was by 1 rep, down to 1 kg; variation swap 3–4 weeks.
Applying a suggestion from Plan: linear → double progression keeps the sets and uses the current reps as the floor
(5 → 5–7, 8 → 8–12); a new rep range moves 2 reps heavier when the floor stays at 3 or more (8–12 → 6–10), else lighter.
Current stall assessments require a progression-eligible exposure in the last 28 days. Deload and Plan signals
also use active routine or rotation membership when it is known. Stalls and elapsed time alone do not imply
accumulated fatigue. These are Overreach heuristics ([ADR-0036](adr/0036-deload-needs-fatigue.md)). The [2026 ACSM position stand](https://pubmed.ncbi.nlm.nih.gov/41843416/)
reviews prescription variables for strength and hypertrophy. The thresholds above are product choices.
Reviewed 2026-11-21.

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

### `easy-run-example` — heuristic

Today can offer conversational running on green or amber days with usable recovery data. Green needs recent
comparable HRV or sleep. Amber needs an active HRV, resting heart rate or sleep signal. Severe soreness, a symptom
reason to skip training or a run already completed today suppresses the example. An explicit running rest day is
respected, and an event today or tomorrow takes precedence. Review multiple due runs in Plan. A confirmed link
counts as a completed run even during a source outage. Green keeps planned quality and long runs in place.
The athlete can apply a suggested same-day easy session from Today. Plan rechecks available space before saving
a suggested move. The search uses an empty running slot two to seven days away and leaves one day on either side
of a hard run or event. That spacing is a schedule heuristic.

Duration uses the lower median of the last five or fewer measured runs in 28 days, with at least one within 14 days.
Use three quarters of that duration on amber and cap by the relevant planned duration when available. The example
is capped at 30 minutes, 20 for a pain-free objective or 15 before a next-day quality or long run, with a 5-minute
minimum. Balanced and strength-first plans also use the lower cap around dated strength, and put today's strength
session ahead of an optional run. Without a fresh run or a nearby key session, the optional cue uses familiar
duration chosen by the athlete. Goal time is displayed in Plan
as an ambition and never used to set the easy pace. The time limits, cutoffs and goal-specific cap are conservative
product defaults. Talk-test studies support the intensity cue. HRV-guided endurance research supports considering
individual changes but does not validate these specific wearable or dosing cutoffs. Reviewed 2026-11-20.
[Talk-test study](https://pubmed.ncbi.nlm.nih.gov/18277826/) · [Individual endurance training trial](https://pubmed.ncbi.nlm.nih.gov/26909534/) · [Single-session running exposure cohort](https://bjsm.bmj.com/content/59/17/1203)

### `run-walk-progression` — heuristic

For a pain-free running goal, Today can show a small run/walk example in distance blocks, for example
"3 × (1.25 km easy · walk 0.25 km) · 0.3 km easy". Pace is never the target, because outdoor runs have stops and pace
changes.

**Session ceiling (cohort evidence).** The whole session, walking included, stays within 10% of the longest run of
the last 30 days and never passes the goal distance. In a Garmin cohort of 5,205 runners followed for 18 months,
single sessions more than 10% longer than the longest run of the previous 30 days had higher overuse-injury rates
(adjusted hazard rate ratios 1.64 for 10–30%, 1.52 for 30–100% and 2.28 for more than 100%). Week-to-week ratios
showed no association and the acute:chronic workload ratio showed an inverse one, so Overreach does not cap weekly
volume. Older evidence agrees that weekly rules are weak: the 10% weekly rule did not reduce injuries in a randomized
trial of 532 novices (20.8% vs 20.3%), and a novice cohort linked only increases above 30% over two weeks to some
injury types. The cohort is observational, with self-reported injuries; the 10% cut-off was chosen by its authors.

**Inside the ceiling (heuristic).** Progress turns walking into running. The running stretch starts from the longest
continuous running segment without reported pain: Garmin's run/walk detection (`RWD_RUN`) when the watch provides it,
otherwise the whole run. After a run without reported pain it grows by 0.25 km and repeats with the athlete's own
typical walk break (Garmin `RWD_WALK`, 0.1 to 0.5 km, 0.25 km by default) until the ceiling. A new runner begins with
0.5 km of running, a 0.5 km walk and 0.5 km of running. A run holds the progression, repeating the last tolerated
session, when its pain was above 3/10 (a configurable product default), did not settle by the next morning, or was
not yet confirmed as settled; two holds in a row shorten the stretch by 0.25 km and the session to 90% of the longest
tolerated run. Pain up to the threshold that settled by morning does not hold. Older yes/no answers keep the cautious
reading: any pain holds. A confirmed run that meets the goal ends the progression. The stretch step, walk lengths,
the 14-day gap, the 3/10 threshold and the step back are conservative product defaults, not research findings.
Pain-monitoring models accept mild pain (up to 5/10) that settles by the next morning in Achilles tendinopathy
rehabilitation; Overreach uses the lower 3/10 because it is not tied to one injury. Pain is asked after any recorded
run when the goal aims for pain-free running, with or without a plan: 0–10 during and after, and the next day
whether it settled. The answer is stored by run (activity id and source). The goal-met rule is unchanged: a
pain-free goal still needs no pain. The wording is pending review with the symptom-wording task. Not medical
advice: pain that persists belongs with a clinician. Decision record: [ADR-0043](adr/0043-running-dose-single-session-ceiling.md). Reviewed 2026-11-23.
[Single-session spike cohort](https://doi.org/10.1136/bjsports-2024-109380) · [Graded novice programme trial](https://doi.org/10.1177/0363546507307505) · [Weekly progression cohort](https://www.jospt.org/doi/10.2519/jospt.2014.5164) · [Pain-monitoring model trial](https://doi.org/10.1177/0363546506298279)

### `single-session-ceiling` — limited

Plan warns when a dated run is planned more than 10% longer than the longest session of the 30 days before it, and
offers to shorten it to that ceiling (rounded down to 100 m). It is a warning, never a block. Source: the Garmin
cohort of 5,205 runners in `run-walk-progression` (Frandsen et al., BJSM 2025), where single sessions more than 10%
over the longest run of the previous 30 days had higher overuse-injury rates (adjusted hazard rate ratios 1.52–2.28),
and week-to-week ratios showed no association. As in that study, runs that start less than 15 minutes after the
previous one ended count as one session. A run planned only by duration is converted with the pace of the last 30
days. Runs planned earlier in the calendar count for later days, so a plan that grows by up to 10% per session passes;
races keep their distance and are not flagged. Without any recorded or planned run in the window there is no ceiling.
The evidence is observational, with self-reported injuries, and the 10% cut-off was chosen by the authors. Decision
record: [ADR-0043](adr/0043-running-dose-single-session-ceiling.md). Reviewed 2026-11-23.
[Single-session spike cohort](https://doi.org/10.1136/bjsports-2024-109380)

### `easy-strength-example` — heuristic

On an amber day with no strength workout detected today, Today can show a separate light example. The next
undated routine supplies the reference, using ordinary progression targets. If it has no recently performed
exercises, a recent logged session supplies examples instead. A session with insufficient information falls back
to an effort cue. Workouts already logged today or captured by the watch suppress the example.

The defaults are up to three exercises performed in the last 42 days, up to two working sets per exercise
(roughly half the reference, with one as the minimum), repetitions within the reference and recent exposure,
and at least four repetitions in reserve. A lower reference effort is respected. A starting load requires a
recent session with enough working sets at or below the effort ceiling, at least as many reps per set, and
recorded weights at or below the lowest reference weight. Use the lightest qualifying weight in that session.
When those data are missing, use the effort cue. Today's effort takes precedence over the starting load.

Today compares a dated routine on amber days. Without one, the athlete asks for the example and can use the next
routine, the next workout in their rotation or a recent workout (ADR-0033). The example creates no session and
leaves the rotation in place. An explicit strength rest day, a pending race today without a dated lift, or
strength work already recorded today suppresses the opt-in. Reduced volume and effort are used in deload practice.
The studies support neither the exact thresholds nor prescribing this example from HRV. Reviewed 2026-11-21.
[Deload consensus](https://doi.org/10.1186/s40798-023-00633-0) · [Athlete survey](https://pubmed.ncbi.nlm.nih.gov/38499934/) · [Repetitions in reserve](https://pubmed.ncbi.nlm.nih.gov/27531969/)

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
→ Each statistic is its own series (`hrvRMSSDMs`, `hrvSDNNMs`); readiness judges one series and Today's 7-day
average uses one statistic, never mixing or converting them. A new watch builds its own baseline (14 nights) instead
of causing a false drop or rise (ADR-0024, ADR-0025). Refs: Task Force of the ESC and NASPE 1996, Circulation 93:1043 (standards); Shaffer &
Ginsberg 2017, Front Public Health 5:258 (review of HRV metrics and norms); Plews et al. 2013, Sports Med 43:773
(ln RMSSD for athlete monitoring). Reviewed 2026-11-20.

### `hrv-metric-type` — moderate
SDNN and RMSSD measure different things (overall vs beat-to-beat variability; short-term SDNN tracks LF power,
r = 0.90–0.94), RMSSD is the more robust metric in short recordings, and no conversion between them exists.
Wearable HRV is comparable only within one device and one metric.
→ Apple Watch SDNN and Garmin RMSSD are separate series, both kept when a night has both; when both can be compared
the rule uses RMSSD, the better-supported input (ADR-0025, [research note](design/hrv-sources.md)).
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
towards red; other signals still do. Superseded for confident phase estimates by `cycle-phase-baselines`. Refs: Schmalenberger et al. 2019, J Clin Med 8:1946 (meta-analysis).
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

Compared HRV below range and resting heart rate above range prompt a question about symptoms that affect
training. Recent pain reported on a linked run prompts a question about worsening pain or changes in stride.
A positive answer favors skipping the session. Rehabilitation protocols use these observations to guide running
progression. The choice to skip the session and the prompt window are coaching heuristics.
With a low HRV trend, Today asks about fatigue after recorded training or unusual stress when no recent training
was recorded. Low reported energy with a stable comparison and no recent training can also prompt the stress
question. Reported fatigue counts once with the energy scale. Reported stress explains what the athlete felt
and carries zero weight in the readiness level. Negative, unsure and skipped answers preserve the existing
decision. Answers apply only to their calendar day. Reviewed 2026-11-21.
[Daily-life study](https://pubmed.ncbi.nlm.nih.gov/39032150/) · [Brigham and Women's return-to-running guidance](https://www.brighamandwomens.org/assets/bwh/patients-and-families/rehabilitation-services/pdfs/le-running-injury-prevention-tips-and-return-to-running-program-bwh.pdf)

### `readiness-reported-symptoms` — limited

An athlete who reports feeling too unwell to train is advised to skip the session and reassess how they feel.
Fever or feeling ill uses the rest and gradual return guidance in `illness-return`. Reported chest discomfort,
unusual breathlessness or dizziness takes priority and prompts medical advice before resuming exercise.
The IOC consensus identifies these symptoms as reasons to stop exercise and seek medical assessment in the
context of acute respiratory illness. Overreach uses a conservative self-report rule and leaves diagnosis and
individual return decisions to clinicians. Clinical review of the check-in wording and escalation remains
pending before release. Literature reviewed 2026-11-21. [IOC consensus](https://doi.org/10.1136/bjsports-2022-105759)

### `readiness-combination` — heuristic
Sick in the check-in → red (see `illness-return`). No signal → green; one or more → amber; two or more with at
least one of HRV or resting HR → red. Subjective and sleep signals alone never make it red. Nothing to judge
(no baseline, no sleep, no check-in) → unknown. Phase-aware baselines for naturally cycling users (ADR-0009)
are not applied yet. All thresholds configurable. Reviewed 2026-11-19.

### `readiness-input-quality` — heuristic
Data-quality defaults for the readiness inputs (ADR-0032). HRV outside 3–300 ms, resting HR outside 25–150 bpm and
sleep of 0 h or above 18 h are treated as measurement errors and ignored. Sleep and daytime HRV readings are
separate series, as HRV depends on posture, activity and time of day. An earlier day never stands in for today's
resting HR or sleep. The ranges are wide engineering limits, not physiological norms. Reviewed 2026-11-21.

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

## Hybrid plan candidates

### `hybrid-priority-spacing` — heuristic

Check whether hard lower-body work competes with a priority run or lift on the same or an adjacent
day. Treat the calendar window as a review trigger and use actual timing when available. Try to move
the lower-priority session to a compatible available slot before proposing reduced work. Concurrent
training outcomes and acute fatigue studies inform the check. [Evidence and replay cases](evidence-readiness-and-hybrid.md#candidate-hybrid-planning-rules)

### `concurrent-lower-body-run` — heuristic

Leg strength work today, or a heavy leg session yesterday, holds back an *unplanned* easy run in Today; a run
the athlete scheduled stays, shortened to the nearby-session maximum. A running priority turns the rule off.
Chronic evidence does not call for avoiding runs: concurrent training does not blunt hypertrophy or maximal
strength on average, and between-session spacing matters less than within-session order (Schumann et al. 2022;
Eddens et al. 2018, strength before endurance favours lower-body strength). What it does support is smaller:
explosive strength is the outcome most affected, the lower-body strength effect in trained people appeared
mainly with both in one session, and a hard second session is limited by acute fatigue (Doma and Deakin 2013).
Direct trials of an easy run after leg work are missing, so the rule is a conservative default for an extra,
unplanned run and never overrides the athlete's own plan. → Implemented defaults (`LowerBodyLoad.Settings`):
"heavy" is 8 or more lower-body working sets, or any set at RPE 9 or higher; the window is today and yesterday,
by calendar day; a lower-body exercise is one with a lower-body primary muscle. Without dated strength, a rotation
repeated at a steady gap (`RotationProjection`, at most every 4 days) supplies tomorrow's session; its leg demand
comes from that workout's last session, where 3 or more lower-body working sets of 5 reps or fewer with load also
count as heavy. Rest days in the projected cycle are scored as run windows: the day after a heavy leg session is
*avoid*, the day before one or after a moderate one is *good*, the rest are *best*. These are product heuristics.
Refs: [Schumann et al. 2022](https://pubmed.ncbi.nlm.nih.gov/34757594/) ·
[Eddens et al. 2018](https://pubmed.ncbi.nlm.nih.gov/28917030/) ·
[Doma and Deakin 2013](https://pubmed.ncbi.nlm.nih.gov/23724883/) ·
[Sex and training-status analysis](https://pmc.ncbi.nlm.nih.gov/articles/PMC10933151/). Reviewed 2026-11-22.

### `run-before-strength-carryover` — limited

How much a recorded run carries over into the next lift. Aerobic work before strength lowers strength moderately,
most after more than 30 min or moderate-to-high intensity and little after short easy work (Markov et al. 2022,
meta-analysis, trained men, mostly same-session). Leg-press volume was lower 4 and 8 h after aerobic work and back at
24 h, for intervals and continuous work alike (Sporer and Wenger 2003, cycling). Unaccustomed and downhill running
cause muscle damage with strength back after about 48 h; regular runners are protected by the repeated-bout effect.
Running may interfere more than cycling at the fibre level (Lundberg et al. 2022). → Defaults
(`RunCarryover.Settings`, #269): *notable* when anaerobic training effect ≥ 2.0 or aerobic ≥ 4.0, more than 60 min or
110 % of the longest run of 30 days, elevation gain ≥ 15 m/km, no run in the previous 14 days, less than 24 h to the
next lift, check-in soreness 3 of its 0–3 scale, or a pain report that holds (ADR-0043); otherwise *light*. The thresholds are
heuristics. Refs: [Markov et al. 2022](https://doi.org/10.1007/s40279-021-01615-6) ·
[Sporer and Wenger 2003](https://pubmed.ncbi.nlm.nih.gov/14636098/) ·
[Lundberg et al. 2022](https://doi.org/10.1007/s40279-022-01688-x) ·
[Downhill running recovery](https://doi.org/10.1038/s41598-020-76008-2). Reviewed 2026-11-23.

### `rotation-reorder-after-run` — heuristic

Whether to keep, swap, postpone or cap the next leg-heavy session after a recorded run (ADR-0044). Supporting
findings: weekly volume matters more than the day a muscle is trained (`frequency-volume-equated`); choosing the
day's session by readiness gave equal or better leg strength than a fixed order (McNamara and Stearne 2010, small
trial); autoregulated loads match or beat fixed loads for maximal strength (Zhang et al. 2021, meta-analysis); heavy
leg strength work leaves residual fatigue for one to several days (Doma et al. 2017, review); HRV-guided resistance
training did not beat fixed recovery in a trial (Bittencourt et al. 2024, older women). No trial tests swapping
sessions after an extra run. → Planned defaults (#271): light carry-over and green readiness keep the plan; otherwise
swap with the next slot without heavy leg demand when every slot stays in the cycle and heavy-leg sessions stay
≥ 48 h apart, then postpone one day, then keep with no load increase and top sets at RPE 8. Refs:
[McNamara and Stearne 2010](https://lida.sport-iat.de/ta/Record/4019534?lng=en) ·
[Zhang et al. 2021](https://doi.org/10.3389/fphys.2021.651112) ·
[Doma et al. 2017](https://researchonline.jcu.edu.au/51391/) ·
[Bittencourt et al. 2024](https://doi.org/10.3389/fphys.2024.1472702). Reviewed 2026-11-23.

### `hybrid-race-taper` — limited

For an athlete with established running exposure, reducing running volume before a priority race
while retaining familiar intensity is a candidate for review. The evidence spans endurance sports
and protocols. Specific dates, volumes and adjustments to lifting require validation for this
population. [Taper meta-analysis](https://doi.org/10.1371/journal.pone.0282838)

### `hybrid-tolerated-exposure` — heuristic

Start with completed comparable work that the athlete reports tolerating. Compare running duration,
distance and intensity separately from hard lifting sets and impact work. Change one running demand
at a time as a candidate default. Hold progression when the decision depends on missing exposure
or symptom information. [Evidence and replay cases](evidence-readiness-and-hybrid.md#candidate-hybrid-planning-rules)
