import SwiftUI

/// A compact 3-column (7D / 30D / 60D) average table for one or two metrics.
/// Intentionally not wrapped in `BetterHealthCard` — uses a flat container
/// to avoid card-in-card nesting.
struct PeriodComparisonTableView: View {
    let averages: [TrendWindow: [TrendMetric: Double]]
    let primaryMetric: TrendMetric
    let secondaryMetric: TrendMetric?

    private var orderedWindows: [TrendWindow] { [.week, .month, .threeMonths] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            Divider()
                .background(BetterColors.border)
            metricsRows
        }
        .background(BetterColors.cardSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(BetterColors.border.opacity(0.6), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Header row

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text("Average")
                .font(BetterTypography.caption)
                .foregroundStyle(BetterColors.mutedText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)

            ForEach(orderedWindows) { window in
                Text(window.displayName)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(BetterColors.subtext)
                    .frame(width: 64, alignment: .trailing)
            }
            .padding(.trailing, 12)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Metric rows

    private var metricsRows: some View {
        Group {
            metricRow(metric: primaryMetric, accentColor: BetterColors.brand)
            if let secondary = secondaryMetric {
                Divider()
                    .background(BetterColors.border.opacity(0.5))
                    .padding(.leading, 12)
                metricRow(metric: secondary, accentColor: BetterColors.cyan)
            }
        }
    }

    private func metricRow(metric: TrendMetric, accentColor: Color) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle()
                    .fill(accentColor)
                    .frame(width: 6, height: 6)
                Text(metric.displayName)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(BetterColors.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 12)

            ForEach(orderedWindows) { window in
                Text(cellValue(for: metric, window: window))
                    .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(averages[window]?[metric] != nil ? BetterColors.text : BetterColors.mutedText)
                    .frame(width: 64, alignment: .trailing)
            }
            .padding(.trailing, 12)
        }
        .padding(.vertical, 10)
    }

    // MARK: - Value formatting

    private func cellValue(for metric: TrendMetric, window: TrendWindow) -> String {
        guard let value = averages[window]?[metric] else { return "—" }
        return formatTableValue(value, metric: metric)
    }

    private func formatTableValue(_ value: Double, metric: TrendMetric) -> String {
        switch metric {
        case .totalSleep, .longestRestorativeBlock, .deepSleep, .remSleep:
            // value is in hours (e.g. 6.83 → "6h50m")
            let totalMin = Int(value * 60)
            let h = totalMin / 60
            let m = totalMin % 60
            if h > 0 { return "\(h)h\(m)m" }
            return "\(m)m"
        case .score:
            return "\(Int(value.rounded()))"
        case .hrv:
            return String(format: "%.0f", value)
        case .waso, .latency:
            return "\(Int(value.rounded()))m"
        case .respiratoryRate:
            return String(format: "%.1f", value)
        case .oxygenSaturation:
            return String(format: "%.0f%%", value)
        }
    }
}
