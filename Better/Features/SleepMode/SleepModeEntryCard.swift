import SwiftUI

struct SleepModeEntryCard: View {
    let subtitle: String
    var notificationStatus: SleepModeNotificationStatus = .notScheduled(.unavailable)
    let onStart: () -> Void
    let onSchedule: () -> Void

    var body: some View {
        HStack(spacing: BetterSpacing.medium) {
            Button(action: onStart) {
                HStack(spacing: BetterSpacing.medium) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(BetterColors.brandLight)
                        .frame(width: 38, height: 38)
                        .background(BetterColors.brand.opacity(0.16), in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sleep Mode")
                            .font(BetterTypography.subheadline)
                            .foregroundStyle(BetterColors.text)
                        Text(subtitle)
                            .font(BetterTypography.caption)
                            .foregroundStyle(BetterColors.subtext)
                            .lineLimit(1)
                        if let chipText = statusChipText {
                            Text(chipText)
                                .font(BetterTypography.micro)
                                .foregroundStyle(statusChipColor)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(statusChipColor.opacity(0.14), in: Capsule())
                        }
                    }

                    Spacer(minLength: BetterSpacing.small)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onSchedule) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(BetterColors.text)
                    .frame(width: 36, height: 36)
                    .background(BetterColors.cardSecondary, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit Sleep Mode schedule")
        }
        .padding(BetterSpacing.medium)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(BetterColors.card.opacity(0.86))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(BetterColors.glassStroke, lineWidth: 1)
                )
        )
    }

    private var statusChipText: String? {
        switch notificationStatus {
        case .scheduled(_, let nextDate):
            if let nextDate {
                let formatter = DateFormatter()
                formatter.dateStyle = .none
                formatter.timeStyle = .short
                return "Reminder · \(formatter.string(from: nextDate))"
            }
            return "Reminders on"
        default:
            return nil
        }
    }

    private var statusChipColor: Color {
        switch notificationStatus {
        case .scheduled: return BetterColors.success
        default: return BetterColors.subtext
        }
    }
}

#if DEBUG
#Preview {
    ZStack {
        BetterColors.background.ignoresSafeArea()
        SleepModeEntryCard(
            subtitle: "Tonight at 10:30 PM",
            notificationStatus: .scheduled(count: 7, nextDate: Date().addingTimeInterval(3600)),
            onStart: {},
            onSchedule: {}
        )
        .padding()
    }
}
#endif
