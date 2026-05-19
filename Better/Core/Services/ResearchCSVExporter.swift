import Foundation
import OSLog

nonisolated struct ResearchCSVExporter: Sendable {
    private let logger = Logger(subsystem: "Better", category: "ResearchCSVExporter")

    func writeZIP(
        package: ResearchExportPackage,
        displayName: String? = nil,
        fileManager: FileManager = .default
    ) throws -> URL {
        let startStamp = Self.dateStamp(package.rangeStart)
        let endStamp = Self.dateStamp(package.rangeEnd)
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("BetterSleep_Export_\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }

        var files: [(name: String, data: Data)] = [
            ("nightly_research_rows.csv", Data(nightlyRowsCSV(package.nightlyRows).utf8)),
            ("protocol_effect_summary.csv", Data(protocolSummaryCSV(package.protocolSummaries).utf8)),
            ("export_metadata.csv", Data(metadataCSV(package).utf8))
        ]
        files += chronotypeFiles(for: package)

        let zipURL = fileManager.temporaryDirectory
            .appendingPathComponent("\(Self.filenameStem(base: "BetterSleep", displayName: displayName))_\(startStamp)_to_\(endStamp).zip")
        if fileManager.fileExists(atPath: zipURL.path) {
            try fileManager.removeItem(at: zipURL)
        }
        logger.debug("CSV export row count=\(package.nightlyRows.count, privacy: .public)")
        let zipData = try StoredZIPWriter.archive(files: files)
        try zipData.write(to: zipURL, options: .atomic)
        return zipURL
    }

    func nightlyRowsCSV(_ rows: [NightlyResearchRow]) -> String {
        let header = [
            "sleep_date",
            "sleep_start_iso",
            "sleep_end_iso",
            "data_quality",
            "total_sleep_hrs",
            "in_bed_hrs",
            "efficiency_pct",
            "deep_hrs",
            "rem_hrs",
            "core_hrs",
            "awake_hrs",
            "waso_min",
            "latency_min",
            "sleep_score",
            "duration_score",
            "efficiency_score",
            "rem_score",
            "deep_score",
            "hrv_avg",
            "hrv_median",
            "heart_rate_avg",
            "heart_rate_min",
            "heart_rate_max",
            "resp_rate_avg",
            "spo2_avg_pct",
            "spo2_min_pct",
            "steps",
            "active_energy_kcal",
            "exercise_min",
            "stand_hours",
            "distance_m",
            "activity_status",
            "is_jet_lagged",
            "activity_note",
            "protocol_taken_any",
            "protocol_ids_taken",
            "protocol_names_taken",
            "protocol_taken_at_iso",
            "protocol_to_sleep_min",
            "baseline_total_sleep_delta_hrs",
            "baseline_efficiency_delta_pct",
            "baseline_waso_delta_min",
            "baseline_latency_delta_min",
            "baseline_hrv_delta",
            "source_names",
            "baseline_window_used",
            "baseline_total_sleep_minutes",
            "duration_vs_baseline_minutes",
            "protocol_usage_status",
            "protocol_taken",
            "protocol_name",
            "protocol_timing",
            "data_quality_status",
            "comparison_confidence",
            // Context fields (Phase 3) — appended at end for backward compatibility
            "caffeine_late",
            "alcohol",
            "workout",
            "late_meal",
            "high_stress",
            "screen_time_late",
            "nap",
            "travel",
            "perceived_sleep_quality",
            "morning_energy",
            "context_notes_present",
            "context_completion_status",
            // Sleep continuity fields (schema v2) — appended at end for backward compatibility
            "restorative_sleep_hrs",
            "longest_restorative_block_hrs",
            "longest_restorative_block_min",
            "sleep_continuity_category",
            "sleep_block_count",
            "meaningful_awake_count",
            "sleep_block_durations_min",
            "sleep_block_start_iso",
            "sleep_block_end_iso"
        ]

        let body = rows.map { row in
            csvRow([
                row.sleepDateKey,
                Self.iso(row.sleepStart),
                Self.iso(row.sleepEnd),
                row.dataQuality.rawValue,
                Self.number(row.totalSleepHours),
                Self.number(row.inBedHours),
                Self.number(row.efficiencyPercent),
                Self.number(row.deepHours),
                Self.number(row.remHours),
                Self.number(row.coreHours),
                Self.number(row.awakeHours),
                Self.number(row.wasoMinutes),
                Self.number(row.latencyMinutes),
                Self.number(row.sleepScore),
                Self.number(row.durationScore),
                Self.number(row.efficiencyScore),
                Self.number(row.remScore),
                Self.number(row.deepScore),
                Self.number(row.hrvAverage),
                Self.number(row.hrvMedian),
                Self.number(row.heartRateAverage),
                Self.number(row.heartRateMinimum),
                Self.number(row.heartRateMaximum),
                Self.number(row.respiratoryRateAverage),
                Self.number(row.oxygenSaturationAveragePercent),
                Self.number(row.oxygenSaturationMinimumPercent),
                Self.number(row.steps, fractionDigits: 0),
                Self.number(row.activeEnergyKcal, fractionDigits: 0),
                Self.number(row.exerciseMinutes, fractionDigits: 0),
                Self.number(row.standHours),
                Self.number(row.distanceMeters, fractionDigits: 0),
                row.activityStatus?.rawValue ?? "",
                row.isJetLagged ? "true" : "false",
                row.activityNote ?? "",
                row.protocolTakenAny ? "true" : "false",
                row.protocolIDsTaken.joined(separator: "|"),
                row.protocolNamesTaken.joined(separator: "|"),
                row.protocolTakenAt.map(Self.iso).joined(separator: "|"),
                row.minutesFromProtocolToSleep.map { Self.number($0, fractionDigits: 0) }.joined(separator: "|"),
                Self.number(row.baselineTotalSleepDeltaHours),
                Self.number(row.baselineEfficiencyDeltaPercent),
                Self.number(row.baselineWASODeltaMinutes),
                Self.number(row.baselineLatencyDeltaMinutes),
                Self.number(row.baselineHRVDelta),
                row.sourceNames.joined(separator: "|"),
                row.baselineWindowUsed.map(String.init) ?? "NA",
                Self.number(row.baselineTotalSleepMinutes),
                Self.number(row.durationVsBaselineMinutes),
                row.protocolUsageStatus.rawValue,
                row.protocolTaken.map { $0 ? "true" : "false" } ?? "unknown",
                row.protocolName ?? "",
                row.protocolTiming ?? "",
                row.dataQualityStatus,
                row.comparisonConfidence.rawValue,
                // Context fields
                Self.tristate(row.caffeineLate),
                Self.tristate(row.alcohol),
                Self.tristate(row.workout),
                Self.tristate(row.lateMeal),
                Self.tristate(row.highStress),
                Self.tristate(row.screenTimeLate),
                Self.tristate(row.nap),
                Self.tristate(row.travel),
                row.perceivedSleepQuality ?? "",
                row.morningEnergy ?? "",
                row.contextNotesPresent.map { $0 ? "true" : "false" } ?? "",
                row.contextCompletionStatus ?? "",
                // Sleep continuity fields
                Self.number(row.restorativeSleepHours),
                Self.number(row.longestRestorativeBlockHours),
                Self.number(row.longestRestorativeBlockMinutes),
                row.sleepContinuityCategory ?? "",
                row.sleepBlockCount.map(String.init) ?? "0",
                row.meaningfulAwakeCount.map(String.init) ?? "0",
                row.sleepBlockDurationsMinutes?.map { Self.number($0, fractionDigits: 0) }.joined(separator: "|") ?? "",
                row.sleepBlockStartDates?.map(Self.iso).joined(separator: "|") ?? "",
                row.sleepBlockEndDates?.map(Self.iso).joined(separator: "|") ?? ""
            ])
        }

        return ([csvRow(header)] + body).joined(separator: "\n")
    }

    func protocolSummaryCSV(_ summaries: [ProtocolEffectSummary]) -> String {
        let header = [
            "protocol_id",
            "protocol_name",
            "taken_nights",
            "missed_nights",
            "sleep_diff_hrs",
            "score_diff",
            "efficiency_diff_pct",
            "waso_diff_min",
            "latency_diff_min",
            "hrv_diff",
            "jet_lag_adjusted_sleep_diff_hrs",
            "early_timing_sleep_diff_hrs",
            "optimal_timing_sleep_diff_hrs",
            "late_timing_sleep_diff_hrs",
            "confidence",
            "caveats"
        ]

        let body = summaries.map { summary in
            csvRow([
                summary.protocolID,
                summary.protocolName,
                String(summary.takenNightCount),
                String(summary.missedNightCount),
                Self.number(summary.sleepDifferenceHours),
                Self.number(summary.scoreDifference),
                Self.number(summary.efficiencyDifferencePercent),
                Self.number(summary.wasoDifferenceMinutes),
                Self.number(summary.latencyDifferenceMinutes),
                Self.number(summary.hrvDifference),
                Self.number(summary.jetLagAdjustedSleepDifferenceHours),
                Self.number(summary.earlyTimingSleepDelta),
                Self.number(summary.optimalTimingSleepDelta),
                Self.number(summary.lateTimingSleepDelta),
                summary.confidence.rawValue,
                summary.caveats.joined(separator: "|")
            ])
        }

        return ([csvRow(header)] + body).joined(separator: "\n")
    }

    func chronotypeSummaryCSV(_ result: ChronotypeCalculationResult) -> String {
        let header = [
            "status",
            "bucket",
            "corrected_midpoint_min",
            "workday_midpoint_min",
            "free_day_midpoint_min",
            "workday_median_sleep_hrs",
            "free_day_median_sleep_hrs",
            "weekly_average_sleep_hrs",
            "valid_nights",
            "workday_nights",
            "free_day_nights",
            "excluded_nights",
            "excluded_too_short",
            "excluded_too_long",
            "excluded_poor_data_quality",
            "excluded_travel_or_jetlag",
            "excluded_invalid_timing",
            "confidence",
            "optimal_window_start_min",
            "optimal_window_end_min",
            "optimal_window_duration_hrs",
            "missing_requirements",
            "window_days",
            "window_start_iso",
            "window_end_iso"
        ]

        let estimate = result.estimate
        let excluded = result.excludedCountsByReason
        let body = csvRow([
            result.status.rawValue,
            estimate?.bucket.rawValue ?? "",
            estimate.map { String($0.correctedMidpointMinute) } ?? "",
            estimate.map { String($0.workdayMidpointMinute) } ?? "",
            estimate.map { String($0.freeDayMidpointMinute) } ?? "",
            estimate.map { Self.number($0.workdayMedianDuration / 3_600) } ?? "",
            estimate.map { Self.number($0.freeDayMedianDuration / 3_600) } ?? "",
            estimate.map { Self.number($0.weeklyAverageDuration / 3_600) } ?? "",
            String(result.validNightCount),
            String(result.workdayNightCount),
            String(result.freeDayNightCount),
            String(excluded.values.reduce(0, +)),
            String(excluded[.tooShort] ?? 0),
            String(excluded[.tooLong] ?? 0),
            String(excluded[.poorDataQuality] ?? 0),
            String(excluded[.travelOrJetLag] ?? 0),
            String(excluded[.invalidTiming] ?? 0),
            estimate?.confidence.rawValue ?? ComparisonConfidence.unavailable.rawValue,
            estimate.map { String($0.optimalSleepWindow.startMinute) } ?? "",
            estimate.map { String($0.optimalSleepWindow.endMinute) } ?? "",
            estimate.map { Self.number($0.optimalSleepWindow.duration / 3_600) } ?? "",
            result.missingRequirements.map(\.rawValue).joined(separator: "|"),
            String(result.windowDays),
            Self.iso(result.windowStart),
            Self.iso(result.windowEnd)
        ])

        return [csvRow(header), body].joined(separator: "\n")
    }

    func metadataCSV(_ package: ResearchExportPackage) -> String {
        let rows = [
            ["key", "value"],
            ["schema_version", ResearchExportPackage.schemaVersion],
            ["generated_at_iso", Self.iso(package.generatedAt)],
            ["range_start_iso", Self.iso(package.rangeStart)],
            ["range_end_iso", Self.iso(package.rangeEnd)],
            ["baseline_window_days", String(package.baselineWindowDays)],
            ["baseline_valid_nights", String(package.baselineValidNights)],
            ["is_research_mode", package.isResearchMode ? "true" : "false"],
            ["nightly_row_count", String(package.nightlyRows.count)],
            ["chronotype_status", package.chronotypeResult?.status.rawValue ?? ""],
            ["chronotype_valid_nights", package.chronotypeResult.map { String($0.validNightCount) } ?? "0"],
            ["insight_summary", package.insightSummary.summary],
            ["insight_confidence", package.insightSummary.confidence.rawValue],
            ["insight_best_protocol", package.insightSummary.bestProtocolName ?? ""],
            ["insight_best_sleep_diff_hrs", Self.number(package.insightSummary.bestProtocolSleepDifferenceHours)],
            ["null_convention", "NA indicates measurement was unavailable for that night; empty string indicates field does not apply"]
        ]

        return rows.map(csvRow).joined(separator: "\n")
    }
}

nonisolated private extension ResearchCSVExporter {
    func csvRow(_ values: [String]) -> String {
        values.map(Self.escape).joined(separator: ",")
    }

    nonisolated static func escape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") else {
            return value
        }

        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    nonisolated static func number(_ value: Double?, fractionDigits: Int = 2) -> String {
        guard let value else { return "NA" }
        return String(format: "%.\(fractionDigits)f", value)
    }

    nonisolated static func number(_ value: Double, fractionDigits: Int = 2) -> String {
        String(format: "%.\(fractionDigits)f", value)
    }

    /// Serialises a `Bool?` tristate as `"true"`, `"false"`, or `"unknown"`.
    /// An empty string is reserved for fields that do not apply to the row at all.
    nonisolated static func tristate(_ value: Bool?) -> String {
        switch value {
        case true:  "true"
        case false: "false"
        case nil:   "unknown"
        }
    }

    private static let isoFormatter: ISO8601DateFormatter = ISO8601DateFormatter()

    private static let dateStampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    nonisolated static func iso(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }

    nonisolated static func dateStamp(_ date: Date) -> String {
        dateStampFormatter.string(from: date)
    }

    nonisolated static func filenameStem(base: String, displayName: String?) -> String {
        guard let displayName = displayName?.trimmedNonEmpty else {
            return base
        }

        let folded = displayName.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
        let allowed = CharacterSet.alphanumerics
        var components: [String] = []
        var current = ""

        for scalar in folded.unicodeScalars {
            if allowed.contains(scalar) {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                components.append(current)
                current = ""
            }
        }

        if !current.isEmpty {
            components.append(current)
        }

        let normalized = components.joined(separator: "-")
        return normalized.isEmpty ? base : "\(base)_\(normalized)"
    }

    func chronotypeFiles(for package: ResearchExportPackage) -> [(name: String, data: Data)] {
        guard let chronotypeResult = package.chronotypeResult else { return [] }
        return [("chronotype_summary.csv", Data(chronotypeSummaryCSV(chronotypeResult).utf8))]
    }
}

nonisolated private enum StoredZIPWriter {
    struct CentralDirectoryEntry {
        var name: String
        var crc32: UInt32
        var size: UInt32
        var localHeaderOffset: UInt32
    }

    static func archive(files: [(name: String, data: Data)]) throws -> Data {
        var output = Data()
        var centralDirectory: [CentralDirectoryEntry] = []

        for file in files {
            guard let nameData = file.name.data(using: .utf8) else { continue }
            let offset = UInt32(output.count)
            let crc = CRC32.checksum(file.data)
            let size = UInt32(file.data.count)

            output.appendUInt32LE(0x04034B50)
            output.appendUInt16LE(20)
            output.appendUInt16LE(0x0800)
            output.appendUInt16LE(0)
            output.appendUInt16LE(0)
            output.appendUInt16LE(0)
            output.appendUInt32LE(crc)
            output.appendUInt32LE(size)
            output.appendUInt32LE(size)
            output.appendUInt16LE(UInt16(nameData.count))
            output.appendUInt16LE(0)
            output.append(nameData)
            output.append(file.data)

            centralDirectory.append(
                CentralDirectoryEntry(
                    name: file.name,
                    crc32: crc,
                    size: size,
                    localHeaderOffset: offset
                )
            )
        }

        let centralDirectoryOffset = UInt32(output.count)
        for entry in centralDirectory {
            guard let nameData = entry.name.data(using: .utf8) else { continue }
            output.appendUInt32LE(0x02014B50)
            output.appendUInt16LE(20)
            output.appendUInt16LE(20)
            output.appendUInt16LE(0x0800)
            output.appendUInt16LE(0)
            output.appendUInt16LE(0)
            output.appendUInt16LE(0)
            output.appendUInt32LE(entry.crc32)
            output.appendUInt32LE(entry.size)
            output.appendUInt32LE(entry.size)
            output.appendUInt16LE(UInt16(nameData.count))
            output.appendUInt16LE(0)
            output.appendUInt16LE(0)
            output.appendUInt16LE(0)
            output.appendUInt16LE(0)
            output.appendUInt32LE(0)
            output.appendUInt32LE(entry.localHeaderOffset)
            output.append(nameData)
        }

        let centralDirectorySize = UInt32(output.count) - centralDirectoryOffset
        output.appendUInt32LE(0x06054B50)
        output.appendUInt16LE(0)
        output.appendUInt16LE(0)
        output.appendUInt16LE(UInt16(centralDirectory.count))
        output.appendUInt16LE(UInt16(centralDirectory.count))
        output.appendUInt32LE(centralDirectorySize)
        output.appendUInt32LE(centralDirectoryOffset)
        output.appendUInt16LE(0)

        return output
    }
}

nonisolated private enum CRC32 {
    static let table: [UInt32] = (0..<256).map { i in
        var crc = UInt32(i)
        for _ in 0..<8 {
            crc = (crc & 1) == 1 ? (0xEDB88320 ^ (crc >> 1)) : (crc >> 1)
        }
        return crc
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = table[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

nonisolated private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        append(UInt8(value & 0x00FF))
        append(UInt8((value & 0xFF00) >> 8))
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        append(UInt8(value & 0x000000FF))
        append(UInt8((value & 0x0000FF00) >> 8))
        append(UInt8((value & 0x00FF0000) >> 16))
        append(UInt8((value & 0xFF000000) >> 24))
    }
}
