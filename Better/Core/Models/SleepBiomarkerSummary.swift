import Foundation

enum SleepBiomarkerSummary {

    // MARK: - Personalised headline (primary path)

    /// Plain-English single-line headline for the biomarker card header.
    ///
    /// When the user has a personal baseline the result is derived from
    /// `reactions` so it always agrees with the synthesis footer below the rows.
    /// Falls back to `headline(biometrics:)` (population thresholds) for new
    /// users who haven't yet accumulated enough nights.
    static func headline(
        reactions: [BiomarkerKey: SleepBiomarkerReaction],
        biometrics: NightlyBiometricSummary?
    ) -> String {
        // Only use personalised copy when we have at least one reaction.
        guard !reactions.isEmpty else {
            return headline(biometrics: biometrics)
        }

        let worse   = reactions.values.filter { $0.direction == .worse }
        let improved = reactions.values.filter { $0.direction == .improved }

        switch (worse.isEmpty, improved.isEmpty) {
        case (true, true):
            // All four in the neutral zone.
            return "Biomarkers were in your usual range"
        case (true, false):
            // At least one improved, none worse.
            return "Some biomarkers shifted favorably"
        case (false, true):
            // At least one worse, none improved — name the loudest signal.
            let name = worse.first.map { Self.displayName(for: $0.key) } ?? "A biomarker"
            return worse.count == 1
                ? "\(name) was outside your usual range"
                : "Some biomarkers were outside your usual range"
        case (false, false):
            // Mixed — some improved, some worse.
            return "Mixed biomarker changes tonight"
        }
    }

    // MARK: - Population-threshold fallback

    /// Fallback headline based on absolute population thresholds. Used when no
    /// personalised baseline reactions are available yet.
    static func headline(biometrics: NightlyBiometricSummary?) -> String {
        guard let bio = biometrics else { return "Biomarker data not available" }

        if let rhr = bio.heartRateMinimum, rhr >= 80 {
            return "Resting heart rate was elevated"
        }
        if let spo2 = bio.oxygenSaturationAverage, spo2 * 100 < 93 {
            return "Blood oxygen was below reference range"
        }
        if let hrv = bio.hrvAverage, hrv < 20 {
            return "Heart rate variability was low"
        }
        if let rr = bio.respiratoryRateAverage, rr < 10 || rr > 20 {
            return "Respiratory rate was outside reference range"
        }

        return "Biomarkers were in reference range"
    }

    // MARK: - Helpers

    /// Maps a `BiomarkerKey` to a human-readable display name without
    /// referencing any `fileprivate` UI-layer types.
    private static func displayName(for key: BiomarkerKey) -> String {
        switch key {
        case .rhr:    return "Resting heart rate"
        case .hrv:    return "Heart rate variability"
        case .spo2:   return "Blood oxygen"
        case .breath: return "Respiratory rate"
        }
    }
}
