import Foundation

public enum ContextMetricGroup: CaseIterable, Sendable {
    case sleep, heart, recovery, load, movement, personal
}

extension ContextPack {
    public func selectingHealthData(health: Bool, cycle: Bool) -> Self {
        selectingMetrics(health ? Set(ContextMetricGroup.allCases) : [], cycle: cycle)
    }

    public func selectingMetrics(_ groups: Set<ContextMetricGroup>, cycle: Bool) -> Self {
        var copy = self
        if !cycle, copy.athlete.cycleTracking != nil {
            copy.athlete.cycleTracking = nil
            // The assessment can include cycle-adjusted baselines and reasons.
            copy.today = nil
        }
        if !groups.contains(.personal) {
            copy.athlete.sex = nil
            copy.athlete.birthYear = nil
            copy.athlete.bodyMassKg = nil
            copy.athlete.maxHeartRate = nil
            copy.athlete.restingHeartRate = nil
            copy.checkIns = []
        }
        // These summaries combine several inputs, including data outside individual metric rows.
        if groups.count != ContextMetricGroup.allCases.count {
            copy.today = nil
            copy.sleepTrainingTiming = nil
        }
        copy.dailyMetrics = dailyMetrics.compactMap { $0.selecting(groups) }
        for index in copy.sessions.indices {
            copy.sessions[index].watch = copy.sessions[index].watch?.selecting(groups)
        }
        if !groups.contains(.movement) { copy.walks = nil }
        if !groups.contains(.heart) {
            copy.walks = copy.walks?.map { walk in
                var row = walk
                row.averageHeartRate = nil
                return row
            }
        }
        if groups.contains(.heart) || groups.contains(.load) {
            copy.strengthRecordings = copy.strengthRecordings?.map { recording in
                var row = recording
                row.watch = recording.watch?.selecting(groups)
                return row
            }
        } else {
            copy.strengthRecordings = nil
        }
        for index in copy.runs.indices {
            if !groups.contains(.heart) {
                copy.runs[index].averageHeartRate = nil
                copy.runs[index].maxHeartRate = nil
            }
            if !groups.contains(.load) {
                copy.runs[index].trainingLoad = nil
                copy.runs[index].aerobicTrainingEffect = nil
                copy.runs[index].anaerobicTrainingEffect = nil
            }
        }
        return copy
    }
}

extension ContextPack.Metrics {
    fileprivate func selecting(_ groups: Set<ContextMetricGroup>) -> Self? {
        var row = Self(date: date, source: source)
        if groups.contains(.sleep) {
            row.lightSleepSeconds = lightSleepSeconds
            row.awakeSeconds = awakeSeconds
            row.sleepSeconds = sleepSeconds
            row.deepSleepSeconds = deepSleepSeconds
            row.remSleepSeconds = remSleepSeconds
            row.sleepScore = sleepScore
        }
        if groups.contains(.heart) {
            row.hrvNightlyHighMs = hrvNightlyHighMs
            row.hrvStatus = hrvStatus
            row.hrvMs = hrvMs
            row.hrvMetric = hrvMetric
            row.hrvBaselineLowMs = hrvBaselineLowMs
            row.hrvBaselineHighMs = hrvBaselineHighMs
            row.restingHeartRate = restingHeartRate
        }
        if groups.contains(.recovery) {
            row.respirationRate = respirationRate
            row.spo2Average = spo2Average
            row.bodyBatteryHigh = bodyBatteryHigh
            row.bodyBatteryLow = bodyBatteryLow
            row.averageStress = averageStress
            row.trainingReadiness = trainingReadiness
            row.recoveryTimeHours = recoveryTimeHours
        }
        if groups.contains(.load) {
            row.trainingStatus = trainingStatus
            row.vo2Max = vo2Max
            row.acuteLoad = acuteLoad
        }
        if groups.contains(.movement) { row.steps = steps }
        return row == Self(date: date, source: source) ? nil : row
    }
}

extension ContextPack.Watch {
    fileprivate func selecting(_ groups: Set<ContextMetricGroup>) -> Self? {
        var row = Self(source: source)
        if groups.contains(.heart) {
            row.averageHeartRate = averageHeartRate
            row.maxHeartRate = maxHeartRate
        }
        if groups.contains(.load) {
            row.trainingLoad = trainingLoad
            row.aerobicTrainingEffect = aerobicTrainingEffect
            row.anaerobicTrainingEffect = anaerobicTrainingEffect
        }
        return row == Self(source: source) ? nil : row
    }
}
