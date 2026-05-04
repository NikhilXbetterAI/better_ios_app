import SwiftUI

struct AlertRowView: View {
    let alert: SleepAlert

    var body: some View {
        HStack(alignment: .top, spacing: BetterSpacing.medium) {
            Image(systemName: iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 36, height: 36)
                .background(iconColor.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(alert.title)
                        .font(alert.isRead ? BetterTypography.footnote : BetterTypography.subheadline)
                        .foregroundStyle(BetterColors.text)
                    Spacer()
                    Text(relativeDate)
                        .font(BetterTypography.caption)
                        .foregroundStyle(BetterColors.subtext)
                }
                Text(alert.body)
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.subtext)
                    .lineLimit(2)
                if let sleepDateKey = alert.sleepDateKey {
                    Text(sleepDateKey)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(BetterColors.brand)
                }
            }

            if !alert.isRead {
                Circle().fill(BetterColors.brand).frame(width: 8, height: 8)
            }
        }
        .padding(BetterSpacing.large)
        .background(BetterColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var iconName: String {
        switch alert.kind {
        case .analysisReady: "checkmark.circle.fill"
        case .lowScore: "chart.line.downtrend.xyaxis"
        case .lowDeepSleep, .lowRemSleep: "moon.zzz.fill"
        case .sleepDebt: "clock.badge.exclamationmark"
        case .highWASO: "bed.double.fill"
        case .lowHRV: "waveform.path.ecg"
        case .lowOxygenSaturation: "lungs.fill"
        case .irregularSchedule: "shuffle"
        case .improvementTrend: "chart.line.uptrend.xyaxis"
        case .missedProtocol: "pills.fill"
        }
    }

    private var iconColor: Color {
        switch alert.severity {
        case 2...: BetterColors.danger
        case 1: BetterColors.warning
        default: BetterColors.brand
        }
    }

    private var relativeDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: alert.createdAt, relativeTo: Date())
    }
}
