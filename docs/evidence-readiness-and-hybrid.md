# Evidence for daily readiness and hybrid planning

Reviewed 2026-11-20. This targeted review supports the [hybrid planning backlog](design/readiness-and-hybrid-planning.md). Use the study population, measurement protocol and outcome to judge applicability. Follow the evidence policy when promoting a finding or heuristic into the rule register. [Evidence policy](adr/0012-evidence-based-rules.md) · [Rule register](evidence.md) · [November evidence review](evidence-review-2026-11.md) · [HRV measurement](adr/0025-hrv-one-series-per-metric.md)

## What several days of low HRV can tell us

Heart rate variability measures how much the time between heartbeats varies. A sustained drop in comparable readings can flag a change in cardiac autonomic regulation. In a training context it can justify considering recovery and asking how the athlete feels. Interpretation depends on the athlete's baseline, the metric and recording conditions, and other events and measurements. Two endurance interventions used individual HRV to guide intensity. A subsequent methodological meta-analysis found uncertain pooled benefits for aerobic capacity and endurance performance versus predetermined training. This supports testing HRV as one input to endurance autoregulation. Transfer to strength prescriptions and the app's specific baseline and traffic-light thresholds requires separate validation. [Kiviniemi et al., endurance intervention](https://pubmed.ncbi.nlm.nih.gov/17849143/) · [Vesterinen et al., recreational runners](https://pubmed.ncbi.nlm.nih.gov/26909534/) · [Manresa-Rocamora et al., meta-analysis](https://doi.org/10.3390/ijerph181910299)

| Observation | Interpretation for a daily recommendation |
| --- | --- |
| HRV drops after a demanding strength session, intervals or a race | Check which event occurred before the change and whether the dose was unusual for this athlete. Acute autonomic recovery varies with intensity and training status. A small post-exercise study measured recovery over hours, so it cannot assign a cause or a duration to a multi-night dip. [Seiler et al.](https://pubmed.ncbi.nlm.nih.gov/17762370/) |
| HRV drops alongside unusual life stress | Daily-life data associate perceived stress with lower HRV. Ask about recent stress when the answer could explain a mismatch or help choose effort. A device stress score alone has limited interpretive value. [Daily-life HRV and psychological stress study](https://pubmed.ncbi.nlm.nih.gov/39032150/) |
| Resting HR rises and the athlete reports new symptoms | Symptoms can drive a different exercise decision. Wearable infection studies suggest deviations can accompany illness, but their selected populations, endpoints and algorithms do not validate illness detection in Overreach. Missing symptoms or stable resting HR leave uncertainty. Use a symptom-led pathway for exercise decisions and graded return. [Mishra et al.](https://www.nature.com/articles/s41551-020-00640-6) · [Quer et al.](https://www.nature.com/articles/s41591-020-1123-x) · [IOC consensus on acute respiratory infection](https://pubmed.ncbi.nlm.nih.gov/35863871/) |
| Sleep duration drops or subjective recovery worsens | Compare sleep duration with the person's usual sleep and ask about energy if it changes the action. Consumer stage estimates have measurement error. Use changes over comparable nights for context and avoid drawing conclusions from a single deep or REM estimate. [Schyvens et al., validation against polysomnography](https://pubmed.ncbi.nlm.nih.gov/40303381/) · [Saw et al., monitoring review](https://bjsm.bmj.com/content/50/5/281) |
| Signals are stable, discordant or sparse | Say which measurements were stable or unavailable. Investigate changes in device, protocol, travel, alcohol, sleep, illness and optional reported cycle context when they matter. Keep explanations qualitative while the series is short. HRV can fall with different physiological responses, including in elite training cases. [Plews et al.](https://pubmed.ncbi.nlm.nih.gov/23852425/) · [Cycle-aware design](design/cycle-aware-training.md) |

### Apply every available metric according to its role

- Use comparable HRV and resting HR series for deviations from personal range, and sleep duration and subjective state for corroboration. Track time of measurement, valid sample count and the age of the latest point. Test long-window versus recent-window overlap, baseline contamination, missing-data behavior and device changes. Garmin nocturnal RMSSD and Apple SDNN have different definitions and measurement contexts. Preserve their provenance and separate series.
- Interpret steps and walking as activity context on complete days. Use recorded workout volume, intensity and impact separately. Use VO₂max estimates and race predictions as longer-term context when useful, alongside actual recent performances. A midday step total is an incomplete observation.
- Display respiration and SpO₂ when the source and quality justify it. Establish device-specific validation, repeatability and the intended use before either can enter a recommendation. Review sleep-stage data, sleep score, Body Battery, device stress, readiness/status, acute load and recovery time as estimates or vendor-derived context. Audit which fields the connectors actually populate. An opaque score may reuse HRV, sleep and activity, so counting it independently could inflate corroboration.
- Timeline association comes first. Align each night's reading to its documented sleep period and exposures preceding that period. Use event markers and observed changes with dates. For repeated observations, describe how often a change followed comparable sessions and its magnitude and uncertainty. A formal analysis needs lag definitions, repeated days, missingness, calendar effects and stress/sleep confounding. A one-week chart supports an explanation of timing. It supplies little information for a reliable correlation or causal attribution.

## Concurrent training and running plans

| Decision | What the research supports | Product implication to test |
| --- | --- | --- |
| Combine endurance and strength | Schumann et al. found little average interference with muscle size or maximal strength, with more attenuation for explosive strength, particularly within the same session. Other syntheses report some lower-body strength differences in subgroups or protocols. Results vary by athlete, outcome and dose. [Schumann et al.](https://pmc.ncbi.nlm.nih.gov/articles/PMC8891239/) · [Sex and training-status analysis](https://pmc.ncbi.nlm.nih.gov/articles/PMC10933151/) | Protect the priority stimulus. Keep hypertrophy, maximal strength, power and endurance outcomes distinct. Where practical, separate hard running and hard lower-body power work. Treat spacing as an adjustable scheduling choice. The ≥3-hour subgroup finding is not a universal recovery interval. |
| Order same-day sessions and avoid acute fatigue | Sequence research has reported advantages for lower-limb strength with resistance before endurance, with limited evidence for a consistent VO₂max difference. A hard second workout can be constrained by fatigue from the first regardless of long-term interference. [Sequence meta-analysis](https://pubmed.ncbi.nlm.nih.gov/36776981/) | Put the goal-critical session where it can be performed well. If both are key, propose spacing or moving one. Consider heavy sets, hard eccentric work, failure, intervals, hills and recent tolerance. Avoid fixed muscle-group recovery clocks. |
| Use strength to support running | Strength can improve running economy in some middle- and long-distance runners, with effects dependent on method, running speed and population. Evidence for one prescription optimizing a target time or preventing pain is indirect. [Concurrent running trial](https://pubmed.ncbi.nlm.nih.gov/34767655/) · [Llanos-Lagos et al.](https://pubmed.ncbi.nlm.nih.gov/38165636/) | Propose strength work the athlete can recover from while preserving key endurance sessions. Treat heavy or explosive work as potential tools where experience and schedule support them. |
| Adapt professional running practice | World-class data describe substantial low-intensity work and changing race-specific work across the season. Intensity distribution depends on whether zones use pace or physiological thresholds and on what is counted. A recreational 5 km training study tested different distributions, with individual variation. Recent event-specific review highlights limited evidence specific to elite 5000 m preparation. [Kenneally et al.](https://pubmed.ncbi.nlm.nih.gov/32449500/) · [Recreational 5 km mesocycle trial](https://doi.org/10.1249/MSS.0000000000001599) · [World-class practice review](https://pmc.ncbi.nlm.nih.gov/articles/PMC8975965/) · [Elite 5000 m review](https://pmc.ncbi.nlm.nih.gov/articles/PMC13611246/) | Use purpose, progression, easy/hard structure, race-specific preparation and individual history. Evaluate taper for an actual event. Treat the elite mileage, zone proportions, double-threshold days and taper parameters as research inputs whose transfer must be tested. [Endurance taper meta-analysis](https://pubmed.ncbi.nlm.nih.gov/37163550/) |
| Track biomechanical exposure | Tendons adapt to repeated loading. Bone stress has different determinants, including accumulated loading and individual health context. Gait changes alter where load is applied and surrogate outcomes vary with the task. HRV and watch cadence cannot quantify tissue capacity or identify a specific injured structure. [Kongsgaard et al., resistance training intervention](https://pubmed.ncbi.nlm.nih.gov/17524067/) · [Tibial load meta-analysis](https://pubmed.ncbi.nlm.nih.gov/35708887/) · [Bone stress Delphi consensus](https://pubmed.ncbi.nlm.nih.gov/39638438/) | Track running distance, pace, hills and surface where recorded, plyometric or other impact exposure, hard lower-body work and pain reports. Use those observations to explain load choices. Review symptom-sensitive pathways with a clinician. Technique changes and tissue-specific prescriptions require evidence beyond a watch metric. |
| Flag unfamiliar loads | In a 5,205-runner cohort, a single-session distance increase relative to the longest run in the prior 30 days was associated with overuse injury. A randomized novice program based on the weekly 10% rule did not reduce injury incidence. The study designs and exposure definitions differ. [Frandsen et al., cohort](https://bjsm.bmj.com/content/early/2025/07/07/bjsports-2024-109380) · [Buist et al., randomized trial](https://pure.rug.nl/ws/files/2727628/Buist_2008_Am_J_Sports_Med.pdf) | Compare the proposed session with recent comparable long runs and surface uncertainty after breaks or partial data. Avoid universal percentage limits and risk probabilities. Keep running impact, endurance workload and strength exposure visible in their original units. |

The product needs three different checks. **Readiness** asks what effort makes sense today. **Scheduling** checks whether a workout conflicts with a priority session or race. **Progression** checks whether the requested training advances the goal within recent tolerated exposure. A normal reading cannot substitute for the scheduling and progression checks. Fixed durations, reduced set counts, ordering preferences and session-spacing defaults are product heuristics unless directly supported for the context.

## Review protocol for future rules

This initial review prioritizes decisions needed for the first implementation. Before shipping automatic programming, run a reproducible search for each question, record the last search date and screen the references of included studies. Use PubMed and SPORTDiscus for sport and physiology research, cross-check with CENTRAL or trial registries for interventions, and use official consensus and device validation sources. Search from inception for foundational protocols and refresh recent studies before release. Record search strings, inclusion criteria and reasons for excluding conflicting findings.

| Question | Search concepts and outcomes |
| --- | --- |
| Which data help with today's recommendation? | HRV-guided or autoregulated training, nocturnal RMSSD, SDNN, sensor validity, post-session recovery, illness, life stress and subjective monitoring. Compare readiness decisions and downstream training outcomes. Extract baseline protocol, lag, signal dependencies and missing-data rules. |
| How should a hybrid week be built? | Concurrent resistance and endurance, session order and spacing, acute fatigue, training status and dose. Extract outcomes separately for hypertrophy, maximal strength, explosive power, running economy and race performance. Compare trained and novice populations and document representation by sex and age. |
| What can transfer from professional plans? | 5000 m/5 km, 10 km and longer events, training logs, session purpose, intensity distribution, periodization, taper and return after interruption. Separate observational practice from causal trials. Compare by experience, event, starting volume and available days. |
| What mechanical and symptom context can guide decisions? | Bone stress, tendon adaptation, eccentric load, hills, impact, pain monitoring, return to running, load progression and gait retraining. Separate biomechanical surrogate outcomes from soreness, pain, injury, return and performance. |

For each supported finding, extract comparison, effect and uncertainty, population, bias, measurement method and implications for the proposed rule. Record when evidence is indirect or disagrees across populations. For each heuristic, define its parameters, uncertainty, fallback and failure cases. Replay realistic histories and include expert review of cases involving symptoms, races and interacting lower-body demands. Track rule evidence and decision confidence independently in test fixtures and user-facing explanations.

## Candidate hybrid planning rules

A targeted literature update on 2026-11-22 used the concepts `concurrent strength endurance training power`,
`resistance training acute running economy`, `recreational runners intensity distribution trial`,
`novice runners distance progression injury` and `running taper performance`. Prefer studies with a
comparator and a training or performance outcome. Use cohort work to characterize exposure and
observational elite practice to generate hypotheses. Treat mixed-sport taper evidence, small trained
samples and evidence from running-only programs as indirect for recreational hybrid athletes.

- **Strength and endurance adaptations.** Concurrent training can develop both capacities. The 2026
  umbrella review supports combining them in recreational athletes. The earlier pooled explosive
  strength result supports checking where hard sessions are placed. These findings vary by outcome
  and establish no minimum separation for an individual. [Umbrella review](https://pubmed.ncbi.nlm.nih.gov/41762427/) · [Schumann et al.](https://pubmed.ncbi.nlm.nih.gov/34757594/)
- **Acute session quality.** A small within-runner study reported worse next-day high-intensity
  running after combined strength and endurance sessions, with effects depending on order. Protect
  key efforts from preceding high lower-body demands. Treat same-day and adjacent-day checks as
  scheduling heuristics. [Doma and Deakin](https://pubmed.ncbi.nlm.nih.gov/23724883/)
- **Easy and hard running.** Both groups in a recreational 10 km randomized trial improved under
  different intensity distributions. Favor familiar easy work for the bulk of the plan and reserve
  harder work for a specific purpose supported by the athlete's history. Leave zone percentages
  unset when the intensity basis or coverage is unknown. [Muñoz et al.](https://pubmed.ncbi.nlm.nih.gov/23752040/)
- **Race preparation.** Pooled endurance studies favor reducing volume and retaining familiar intensity
  before competition. A small crossover in trained 1500 m runners found variable effects from raising
  the intensity of the final intervals. Use a volume reduction as the first taper candidate for an
  athlete with an established schedule and a priority race. Treat timing and the size of the reduction
  as configuration to validate for each event and training history. [Wang et al.](https://doi.org/10.1371/journal.pone.0282838) · [Spilsbury et al.](https://pubmed.ncbi.nlm.nih.gov/30608885/)

### Template inputs and decisions

Read available training days, the current plan and protected lifts, race date and priority, goal type,
recent completed runs and strength work, and athlete-reported symptoms. Summarize running time and
distance, known intensity exposure and the longest recent comparable run. Separately retain hard
lower-body sets and recorded effort, hills, surface and impact work where known. Mark missing fields
as unknown. Use the [exposure evidence above](#concurrent-training-and-running-plans) to explain an
unfamiliar session without producing an injury score or estimating tissue capacity.

1. Keep completed sessions and explicitly protected sessions fixed. Check symptom guidance first.
   Use the athlete's stated priority to rank an editable run or lift. When priorities are equal or
   missing and two key sessions collide, ask which to protect before moving either.
2. Build from sessions the athlete has actually tolerated. Compare duration, distance and effort
   separately. With sparse history, retain existing commitments and ask for a familiar session before
   proposing a progression dose. A candidate default is to increase one running demand at a time.
3. Where a key run or leg session competes with another hard lower-body session on the same or an
   adjacent day, first look for an available slot for the lower-priority session. Check the new
   neighbors before offering a move. If none fits, offer to reduce or defer the lower-priority work.
   Preserve the original calendar until the athlete accepts a change.
4. Use familiar easy work for a completion goal, preserve stable tolerated exposure for a
   symptom-sensitive goal, and add event-specific work for a time goal only when recent performance
   supports its intensity. Derive target pace for display from goal distance and time. Set training
   pace from current performance. For a priority race with established exposure, offer reduced
   pre-race volume while retaining familiar effort. With sparse exposure, defer numeric taper targets.

Each candidate change should include the original and proposed slots, competing sessions, the protected
priority, the intended adaptation, evidence keys and what remains uncertain. The spacing and progression
defaults above are product heuristics. Keep them explicit in fixtures.

### Cases for historical replay

Use data available before each proposal date. Replay days in order with the saved calendar, source
coverage and symptoms as then known. Check both the proposed action and its explanation.

| Goal or conflict | Known inputs | Expected first proposal |
| --- | --- | --- |
| Finish a first 5 km | Two available running days, a familiar 15-minute walk/run and no recent hard running | Start with the familiar easy session. Progress duration only after comparable sessions are logged and tolerated. |
| Return to 5 km without pain | Recent tolerated easy outing, next-day symptom report missing | Hold the dose and ask once for relevant symptom context. If pain returns or affects gait, use the symptom pathway and suppress automatic progression. |
| Race 5 km in 15 minutes | Recent 5 km in 19 minutes and consistent easy running | Display 3:00/km as goal pace. Anchor any quality session to present performance and communicate uncertainty about timing and feasibility. |
| Preserve priority squat day | Heavy squats Tuesday, low-priority intervals Tuesday, Thursday available with compatible neighbors | Keep squats Tuesday and offer Thursday for intervals. Recheck with Thursday unavailable and expect an easy replacement or deferral. |
| Priority race and two hard leg sessions | Sunday race, Friday intervals, Saturday heavy legs, both editable, established running schedule | Protect the race. Offer earlier or reduced work after checking available slots and avoid rescheduling both hard sessions together. |

For each case remove run effort, recent history or strength muscle mappings in turn. Replay with a
duplicated activity, an explicit rest day and a skipped response. Record per case the expected and
observed action, coverage, unnecessary prompts, skipped proposals and adverse suggestions such as a
hard session despite reported warning symptoms or a move into another protected slot. Compare against
the existing schedule behavior. The cases are review fixtures. Running them against actual histories
and review by a running coach and a sports clinician remain release gates for automatic programming.
