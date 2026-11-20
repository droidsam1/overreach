# 0029. Detect unplanned deloads from completed training

Plan looks back over the last year for at least seven complete local days of inactivity or substantially
reduced training. Strength and running are assessed independently. An uninterrupted gap is one period.
Low-load windows use the preceding four weeks as context. Routine-linked strength sessions can also be
compared with targets reconstructed from prior exposures and current prescriptions. The strength plan
stores the routine rotation and frequency. Running is assessed using recorded activities. A watch-only
strength session establishes that training occurred, while matched recordings count once.

Clear periods count automatically. Ambiguous periods can be accepted or dismissed in Plan, and those
decisions are saved with the profile so they survive reloads and backups. Confirmed periods count from
their last day. Today and the forward plan use the same detection. Both omit immediate repeat advice during the
following week, and Today resets its interval signal from the latest completed recovery period.

See the `unplanned-deload` entry in [the evidence register](../evidence.md) for the basis and limits of
the detection thresholds.
