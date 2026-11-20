# HRV from several sources: research and proposal

Status: research done 2026-11-20; proposal in ADR-0024 (Proposed). Answers step 4 of
`docs/design/garmin-integration.md`, which deferred the HRV metric question to "Decide in step 4, with evidence".
Evidence keys: `hrv-metric-type`, `wearable-hrv-validity`, `hrv-nocturnal`, `composite-scores` (`docs/evidence.md`).

## 1. The question

Overreach gets nightly HRV from two places that measure different things:

| | Apple Watch (Health) | Garmin (Personal API) |
|---|---|---|
| Metric | SDNN (`HKQuantityTypeIdentifierHeartRateVariabilitySDNN`) | RMSSD |
| How | ~1-minute spot readings, taken opportunistically (about every 2 h asleep, 3–4 per night, irregular) plus Breathe/Mindfulness sessions | Continuous during sleep, analysed in 5-minute windows; the night's average and the highest 5-minute value |
| What we store | Mean of the readings during that night's sleep (`HealthSamples`), else of the day's readings | `lastNightAvg` |
| Source baseline | None | `baselineLowUpper`/`balancedLow`/`balancedUpper` and status label (method unpublished) |

Both go into `DailyMetrics.hrvNightlyAverageMs`. `TodayModel` merges per day with Garmin first
(`garmin.merging(health)`), so **on any day without a Garmin value the Apple SDNN fills the gap**, and
`ReadinessRules.hrvCheck` then builds one ln baseline out of two different metrics from two devices. The same
happens when someone moves from an Apple Watch to a Garmin (or back): the old metric sits in the 60-day baseline
and the new one in the 7-day window. Neither case is rare for a hybrid athlete who sleeps with one watch and
trains with another.

Questions:
1. Can SDNN and RMSSD share a baseline, or be converted into each other?
2. How good is each device for a nightly, within-person trend?
3. What should happen when the source changes?
4. Should Garmin's own baseline/status, or Body Battery, feed the rules?

## 2. What the evidence says

### 2.1 SDNN and RMSSD are different quantities (`hrv-metric-type`)

- RMSSD reflects beat-to-beat (vagally mediated) variability; short-term SDNN reflects overall variability,
  including slower components, and is strongly associated with LF power (r = 0.90–0.94 at rest and after
  exercise). Their norms and units of change are not interchangeable (Shaffer & Ginsberg 2017; Esco 2026).
- RMSSD is the more robust metric in short recordings: in 3,387 adults, ultra-short (10 s, 1 min) RMSSD agreed
  with the 5-minute reference, SDNN did not (Munoz et al. 2015). A 2026 narrative review concludes RMSSD should be
  the default HRV metric for routine resting monitoring in sport, with SDNN as a complement (Esco 2026).
- No published conversion between a device's nightly SDNN and another device's nightly RMSSD exists; pulse-derived
  RMSSD is "nearly never equivalent" to ECG RMSSD and SDNN only under strict conditions (PRV/HRV preprint, 2023).
- Wearable reviews and guidance agree: track trends **within one device and one metric**; algorithm differences
  and measurement error limit cross-device comparison (narrative review, 2026; Doherty et al. 2025).

→ They must never share a baseline. Converting one into the other is not supported.

### 2.2 Each device is poor in absolute terms, usable for its own trend (`wearable-hrv-validity`)

- **Garmin.** Nocturnal RMSSD vs a chest-strap ECG over 536 nights (13 adults): Oura Gen 4 CCC 0.99 (MAPE 6 %),
  Oura Gen 3 0.97 (7 %), WHOOP 4.0 0.94 (8 %), **Garmin Fenix 6 0.87 (MAPE 10.5 ± 8.6 %)**, Polar 0.82 (16 %)
  (Dial et al. 2025). Elevate v4 (Forerunner 955, n = 23, ECG): good resting HR and good test–retest reliability of
  RMSSD, but proportional bias and wide limits of agreement (individual errors −43 % to +52 % supine); under-reads
  more as true HRV rises (Sensors 2026, 26:6549). Older single-night data with an earlier sensor were worse
  (Forerunner 245: −22 ms bias, ICC 0.24, partly from awake sampling; Miller et al. 2022).
- **Apple Watch.** Series 9 / Ultra 2, 39 adults, 316 serial measurements over 14 days vs Polar H10: SDNN
  under-read by 8.3 ms, MAPE 28.9 %, MAE 20.5 ms, outside the ±10 ms equivalence margin; resting HR agreed well
  (O'Grady et al. 2024, Sensors 24:6220). R–R intervals themselves are accurate at rest (Series 6 vs 3-lead ECG,
  2025; Hernando et al. 2018). **No study validates the passive nocturnal SDNN that Health stores**, and 3–4 spot
  readings a night are sensitive to sleep stage and circadian timing.

→ Both are usable only against the person's own baseline from the same device. Garmin's whole-night RMSSD is
the better-supported input; Apple's nightly SDNN is a weaker one (fewer, spot readings; no nocturnal validation).

### 2.3 Nightly values work for monitoring (`hrv-nocturnal`)

- Nocturnal HR and RMSSD are reliable with low typical error and respond to the preceding training load; the
  first 4 h of sleep responds more than the full night or a morning reading (Nuuttila et al. 2022, IJSPP 17:1296).
- Nocturnal and morning values correlate at baseline (r = 0.42–0.91) but their responses to two weeks of overload
  diverge, especially ln RMSSD; nocturnal changes tracked 3000 m performance changes (r = −0.50 for ln RMSSD)
  (Nuuttila et al. 2024, Sports Med Open). In 11 young endurance athletes, nocturnal and morning HR and RMSSD did
  not differ over the long term ("Evaluation of nocturnal vs. morning measures of heart rate indices in young
  athletes", 2021, PMC8730395).

→ The existing `readiness-hrv` method (7-day rolling ln mean vs the personal 60-day range) transfers to nightly
RMSSD with reasonable support. Applying it to nightly Apple SDNN stays a heuristic transfer.

### 2.4 Source scores (Garmin HRV status, Body Battery) (`composite-scores`)

- Garmin's HRV status compares a 7-day average with a personal range that needs three weeks of data; how the range
  and labels are computed is not published. Firstbeat's methods have a research base, the scores do not.
- None of 14 composite scores from 10 manufacturers (readiness, recovery, Body Battery and the like) has rigorous
  independent validation; inputs, weights and baselines (7 vs 28 days) are undisclosed and can change without
  notice (Doherty et al. 2025, Transl Exerc Biomed, doi 10.1515/teb-2025-0001).

→ Show them as context labelled as Garmin's, never as rule inputs. Our own baseline stays the rule (ADR-0020,
ADR-0022 decision 2).

## 3. Options for the data model

| Option | How | For | Against |
|---|---|---|---|
| A. Keep one field | as today | no change | mixes metrics and devices; violates 2.1 |
| B. Field + tag | `hrvNightlyAverageMs` + `hrvMetric` | small change | `merging` fills field and tag independently unless special-cased; a day can only carry one value, so the other source's night is lost |
| **C. One field per metric** | `hrvRMSSDMs` (Garmin) and `hrvSDNNMs` (Apple), merged independently | both nights kept; each series is clean; the rule chooses a series explicitly | the old field becomes a computed "preferred HRV" for display and reports |

`DailyMetrics` is not persisted or backed up (it is rebuilt from Health and Garmin on each load), so C needs no
backup format bump (ADR-0018). Still, the new fields are optional.

## 4. Proposal (ADR-0024)

1. **One series = one metric from one source.** `DailyMetrics` gets `hrvRMSSDMs` and `hrvSDNNMs`;
   `GarminMapping` fills RMSSD, `HealthSamples` fills SDNN. `hrvNightlyAverageMs` becomes a computed property
   (RMSSD when present, else SDNN) used only for display, the AI report and the exchange context, which also say
   which metric it is. A future source writing RMSSD to Health still lands in its own series because the Health
   identifier says SDNN; a second RMSSD source would need its own field or a source tag (not needed now).
2. **The rule judges one series and never mixes.** `ReadinessRules` picks the series that qualifies (≥ 14 nights
   in the 60-day baseline and ≥ 3 in the last 7); if both qualify it uses RMSSD (better-supported metric and whole
   night). If none qualifies the HRV signal is skipped, as today. The reason says which metric it used
   ("HRV (RMSSD, Garmin) below your normal range").
3. **A source change restarts the baseline.** Because series are separate, a new watch simply has no baseline yet;
   Today says "HRV baseline: 6 of 14 nights" instead of comparing across devices. The switch-over is short: Garmin
   history backfills 60 days on connection (`GarminSyncPlan`), so a Garmin user who connects is usually ready at once.
4. **Evidence levels per series.** RMSSD (Garmin) keeps `readiness-hrv` at moderate. SDNN (Apple) carries the same
   rule but the reason shows the `hrv-metric-type` caveat; the level stays moderate for the rule and the
   transfer is labelled in `docs/evidence.md`.
5. **Garmin's own baseline and status, and Body Battery, are context only** (`composite-scores`). They can appear
   on Today and in the report, labelled as Garmin's, and never change the light.
6. **Not done:** converting SDNN↔RMSSD, comparing absolute HRV across people or devices, using Garmin's highest
   5-minute value (no evidence it adds anything), first-4-hours windows (the API gives no per-window data).

### Tests (realistic fixtures)
- A Garmin user who also wears an Apple Watch some nights: the rule uses RMSSD only; the SDNN nights do not move
  the baseline.
- Apple Watch → Garmin switch on day 30: RMSSD baseline ready after the 60-day backfill; without backfill, HRV is
  skipped until 14 RMSSD nights.
- Apple Watch only: unchanged behaviour, reason names SDNN.
- Display: `hrvNightlyAverageMs` returns RMSSD when both exist.

## 5. Sources

- Esco MR. A Narrative Review of HRV Metric Selection for Applied Monitoring: RMSSD as the Default Metric for
  Sport and Exercise. J Funct Morphol Kinesiol 2026;11(3):304. doi:10.3390/jfmk11030304.
- Shaffer F, Ginsberg JP. An Overview of Heart Rate Variability Metrics and Norms. Front Public Health 2017;5:258.
- Munoz ML et al. Validity of (Ultra-)Short Recordings for Heart Rate Variability Measurements. PLoS One
  2015;10:e0138921.
- Dial et al. Validation of nocturnal resting heart rate and heart rate variability in consumer wearables.
  Physiol Rep 2025;13:e70527. (Rebuttal by WHOOP authors on like-for-like comparison: PMC12706116.)
- Pulse vs. R-R Interval: Validity and Reliability of the Garmin Elevate v4 Sensor for Ultra-Short HR and HRV
  Monitoring in Healthy Adults. Sensors 2026;26:6549. doi:10.3390/s26206549.
- Miller DJ et al. A Validation of Six Wearable Devices for Estimating Sleep, Heart Rate and HRV in Healthy
  Adults. Sensors 2022;22:6317.
- O'Grady B et al. The Validity of Apple Watch Series 9 and Ultra 2 for Serial Measurements of HRV and Resting
  Heart Rate. Sensors 2024;24:6220.
- Validity of HRV Measured with Apple Watch Series 6 Compared to Laboratory Measures (2025, PMC12031371);
  Hernando D et al. Validation of the Apple Watch for HRV during relax and mental stress. Sensors 2018;18:2619.
- Nuuttila OP et al. Reliability and Sensitivity of Nocturnal HR and HRV in Monitoring Individual Responses to
  Training Load. Int J Sports Physiol Perform 2022;17:1296.
- Nuuttila OP et al. Morning versus Nocturnal HR and HRV Responses to Intensified Training in Recreational
  Runners. Sports Med Open 2024. doi:10.1186/s40798-024-00779-5.
- Evaluation of nocturnal vs. morning measures of heart rate indices in young athletes. 2021 (PMC8730395).
- Doherty C et al. Readiness, recovery, and strain: an evaluation of composite health scores in consumer
  wearables. Transl Exerc Biomed 2025. doi:10.1515/teb-2025-0001.
- Garmin, "Heart Rate Variability Status" (device manuals) and Garmin HRV blog; Terra and HRV4Training analyses of
  Apple Watch overnight sampling (secondary, for how Apple samples, not for validity).

Not read in full in this session (the network blocks the journal hosts): the numbers above come from the
abstracts and indexed full-text excerpts. Before the code change, check the Dial et al. and Esco PDFs for
anything that contradicts §2.
