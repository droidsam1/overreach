# Recovery & Progress performance data

Scope and acceptance criteria are tracked in [the performance epic](https://github.com/droidsam1/overreach/issues/325).
The audit uses the reader and importer code and synthetic fixtures. It uses no personal workouts.

## Running coverage

| Source | Distance and time | Pauses and pace | Heart rate, cadence and terrain |
| --- | --- | --- | --- |
| Apple Health | Workout distance, timer duration, elapsed time from start to end | Workout summaries support whole-activity best times at the target distance. The reader does not load timestamped route or lap data. | Average and maximum workout HR and optional elevation metadata. No lap cadence, environmental readings or confirmed HR sensor read by this app. |
| Garmin | Totals, elapsed time when supplied, and a bounded fetch of recent split records | Optional moving duration and run/walk summary. Split elapsed time can be checked against the full recording. Pace is computed from recorded distance and time. | Summary and optional lap average HR and cadence, optional ascent and descent. Source identifies Garmin Connect. It does not identify which HR sensor recorded the sample. |
| Local planned completion | A completion can reference a recorded workout or be marked manually. A manual completion provides adherence without a recorded time or distance. | No local timing, pause or route series. | No independent HR or cadence measurement. |

Best times use whole workouts at the target distance or continuous runs of adjacent recorded laps with exactly
the target distance within rounding tolerance. Lap totals must reconcile with the workout, including elapsed time.
Whole-activity distances up to 0.5% past the target provide separately labeled elapsed upper bounds. These
results never enter exact-distance changes. Plausibility filters reject unusable split speeds. GPS errors within plausible averages can escape detection because
the app has no GPS track to validate. A watch activity marked as a race remains watch timing. Official chip or
gun results require an official timing source.

Comparable HR needs a steady post-warm-up segment with adequate HR, comparable pace, duration, slope and
environment, and a known sensor. Coverage can be missing even when a watch supplies a plausible average HR.
Use separate comparable cohorts and let missing inputs leave the comparison unavailable.

## Garmin block pilot

Use the original activity FIT from the Garmin Personal API. Sync downloads at most two originals
per sync for known runs in the past 180 days, newest eligible first. It retains only compressed
decoded track measurements in its local cache. A missing or unreadable original is retried
after a week. Transient failures defer remaining downloads without discarding summary data.
Decode timestamped distance, speed, elevation, heart rate and cadence, plus lap triggers and
timer events. A run can begin after an
unrecorded walking warm-up. Join automatic laps within a block and use manual laps, sustained
walks or timer stops as boundaries. Measure the whole block's duration and distance. Use the
steady portion after the initial heart-rate response for the comparison, including short runs.
The initial heuristic allows two- to three-minute windows after 45 seconds of running. It
favors longer eligible windows and breaks ties by earliest start. Pulse does not rank candidates.

Compare pace, duration and the slope profile. Nearby GPS samples in the same direction increase
confidence when routes overlap. Other routes remain eligible with comparable difficulty. Cadence
helps distinguish running from walking and provides context. Consider block order and recovery
before the block. Keep sensor identity independent of the activity recorder. If the FIT does
not identify the heart-rate source, offer a user confirmation and keep unknowns visible.
Summarize at most one comparable observation per session. The pilot allows a descriptive
comparison with one matching session in each period. Trend labels require three distinct
session days in each period and use within-period variability. Treat the result as descriptive
when sleep, recent load or weather differ or are unknown.

The version 1 matching heuristics require no more than 15 s/km between pace midpoints,
1.5 percentage points at each end of the grade band, and 45 seconds between measured windows.
Whole-block duration helps rank alternatives. The measured windows determine duration
compatibility. When a plausible profile maximum is available, exclude a window whose median HR
is at least 90% of that maximum. Without a maximum the estimate describes a stable effort
of unverified intensity. Compare only matching confirmed sensor identities. Matching ranks cohort
coverage first, then GPS overlap. When choosing a block within a cohort, favor overlap in the same direction, then the
same block number or a similar recovery interval. HR values never rank cohorts or blocks.

- [Decode FIT and reconstruct blocks](https://github.com/droidsam1/overreach/issues/337)
- [Sync the original Garmin activity](https://github.com/droidsam1/overreach/issues/338)
- [Surface comparable blocks and trends](https://github.com/droidsam1/overreach/issues/339)
- [Historical weather context](https://github.com/droidsam1/overreach/issues/340)

### Historical weather

Historical weather is optional. With a personal OpenWeather One Call key, send an approximate 0.1° area
and UTC hour for outdoor Garmin runs with a recorded GPS point. Keep original route samples on the device.
History shows estimated temperature, humidity, wind and conditions with attribution. Weather remains
context for interpretation. If it is unavailable, the run detail and performance comparisons still load.

The app shares a persistent budget of 200 requests per UTC day between history and forecasts. It caches
past hours by area and hour, reuses forecasts for 30 minutes, and checks up to 16 runs from the last
14 days after a Garmin sync. For older runs, opening a detail fetches weather when it is available.
OpenWeather's [One Call pricing](https://openweathermap.org/price) includes 1,000 calls per day at no
charge and bills for excess calls. Its default account ceiling can exceed the free allowance. Set the
provider-side daily ceiling to 1,000 or fewer when adding the key. The app's limit applies per install.

The app keeps the key in the device Keychain and attributes OpenWeather in the run detail.
A [Today forecast](https://github.com/droidsam1/overreach/issues/341) can reuse the source and its budget.
Device temperature and recorded ambient weather are candidates for a later FIT parser extension.

## Strength coverage

| Source | Available | Limits |
| --- | --- | --- |
| Local | Saved sets with exercise ID, catalog equipment, kg, reps, set category and optional effort stored as RPE | Exercise ID identifies a variant. An arbitrary load convention change within one exercise ID or an equipment swap with no new exercise ID is unobservable. Completed submaximal singles and max-effort singles have distinct eligibility. |
| Strong CSV | Stable session and set IDs, matched exercise ID, kg converted from the importer's selected unit, reps, set category, optional RPE | The file omits its weight unit and can omit effort or set completion timestamps. Per-hand, per-side and total-load meanings are not encoded. Strong contributes recorded sets, with its own series for a given exercise. |
| Watch strength summary | Time and optional workout-wide wearable data | No load or completed reps that can enter strength performance. |

Use one qualifying observation per session, metric and lift. Warm-ups are excluded. Estimates use one eligible
local effort-adjusted set per session, preserve the source set and equation version, and are labeled as estimates.
Keep equipment and load conventions separate at logging time by using a distinct exercise for each variant.
Recorded sets without effort remain eligible for load and rep records.

## Matching and recomputation

- Apply saved match and separation choices before counting runs, as in [unified history](https://github.com/droidsam1/overreach/issues/40).
  Use one canonical observation for repeats and exclude unresolved ambiguous matches until reviewed.
  The original session reference opens the activity detail.
- Recompute against current saved or synced data. Strong imports are idempotent by stable ID and Garmin sync refreshes source activities.
- Keep accepted rest and strength and running deload history reachable alongside performance, as in [Plan progress](https://github.com/droidsam1/overreach/issues/126).
- The logger's [session achievements](https://github.com/droidsam1/overreach/issues/186) celebrate improvements over prior history.
  The first eligible set in Recovery & Progress establishes a recorded baseline. Equal load comparisons use the logger's kg tolerance.

## Trend pilot replay

Compare medians in equal nonoverlapping calendar windows, with one observation per session and at least three
distinct training days per window. The strength pilot uses two 28-day windows spanning at least 42 days from
first to last observation. A change should exceed twice the larger within-window median absolute deviation,
with a floor of 2% of baseline for strength and 2 bpm for HR. Possible plateau also needs a median change of
at most 2%, all observations within 4% of their own window median, and measurable within-window variation.
Accepted strength deloads and crossed declared block boundaries suppress the strength label. These thresholds
are product heuristics. [Evidence register](../evidence.md#performance-trend-pilot)

| Synthetic replay | Expected result | False flags in fixture |
| --- | --- | --- |
| Improving or declining strength across six weeks | Improving or declining | 0 |
| Normal strength variability | Within variability | 0 |
| Tight, repeatable strength series over six weeks | Possible plateau | 0 |
| Sparse, clustered or identical rounded strength measurements | Insufficient evidence | 0 |
| Exercise variant, load convention or equation change | Insufficient evidence | 0 |
| Accepted strength deload or block change | Insufficient evidence | 0 |
| Run-only deload or ordinary rest day during repeatable strength series | Possible plateau | 0 |
| Lower HR in a comparable running cohort | Improving | 0 |
| Ordinary HR variability | Within variability | 0 |
| Changed HR sensor or sparse HR with repeated imports | Insufficient evidence | 0 |

These fixtures cover expected outputs for known inputs. Device and real-history false-flag rates remain unmeasured.
