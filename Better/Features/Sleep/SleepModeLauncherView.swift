import SwiftUI
import Combine

/// Compact "Open Sleep Mode" button rendered in the Sleep dashboard hero.
/// Only visible when `SleepModeScheduleService.shouldShowLauncher` returns true
/// (during an active scheduled interval, or after 20:00 local time).
struct SleepModeLauncherView: View {
    let schedule: SleepModeSchedule
    let onOpen: () -> Void

    @State private var now: Date = Date()
    @State private var pulse: Bool = false

    private let ticker = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var isActiveNow: Bool {
        SleepModeScheduleService.currentInterval(for: schedule, now: now) != nil
    }

    private var isVisible: Bool {
        SleepModeScheduleService.shouldShowLauncher(schedule: schedule, now: now)
    }

    var body: some View {
        Group {
            if isVisible {
                button
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: isVisible)
        .onReceive(ticker) { value in now = value }
    }

    @ViewBuilder
    private var button: some View {
        Button(action: onOpen) {
            HStack(spacing: BetterSpacing.medium) {
                Image(systemName: isActiveNow ? "moon.stars.fill" : "moon.zzz.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(BetterColors.brandLight)
                    .frame(width: 40, height: 40)
                    .background(BetterColors.brand.opacity(0.18), in: Circle())
                    .shadow(color: BetterColors.brandLight.opacity(isActiveNow ? 0.35 : 0), radius: 6)
                    .scaleEffect(isActiveNow && pulse ? 1.08 : 0.96)
                    .opacity(isActiveNow && pulse ? 1.0 : 0.75)

                VStack(alignment: .leading, spacing: 2) {
                    Text(isActiveNow ? "Sleep Mode is on" : "Open Sleep Mode")
                        .font(BetterTypography.subheadline.bold())
                        .foregroundStyle(BetterColors.text)
                    Text(isActiveNow ? "Tap to return to the wind-down screen" : "Wind down with breathing & blackout")
                        .font(BetterTypography.caption)
                        .foregroundStyle(BetterColors.subtext)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BetterColors.subtext)
            }
            .padding(BetterSpacing.medium)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(BetterColors.glassStroke, lineWidth: 1)
                )
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}
