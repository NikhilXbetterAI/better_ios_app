import SwiftUI

struct HealthPermissionStepView: View {
    let authorizationState: HealthAuthorizationPresentationState
    let isWorking: Bool
    let onConnect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.xxLarge) {
            OnboardingStepHeader(
                icon: "heart.fill",
                title: "Connect Apple Health",
                body: "Sleep stages, heart rate, HRV, oxygen saturation, and respiratory rate power the dashboard. You can skip this now and connect later in Settings."
            )

            VStack(alignment: .leading, spacing: BetterSpacing.medium) {
                permissionRow("Sleep Analysis", "Sleep duration, stages, efficiency, latency, and awakenings", "moon.zzz.fill")
                permissionRow("Heart and Recovery", "Overnight heart rate, HRV, oxygen, and respiratory rate", "waveform.path.ecg")
            }
            .padding(BetterSpacing.large)
            .background(BetterColors.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            statusView

            Button(action: onConnect) {
                HStack {
                    if isWorking {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "heart.text.square.fill")
                    }
                    Text(isWorking ? "Connecting" : "Connect Apple Health")
                }
                .font(BetterTypography.subheadline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(BetterColors.brand, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isWorking)

            Spacer()
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch authorizationState {
        case .notRequested:
            EmptyView()
        case .healthDataUnavailable:
            OnboardingNoticeView(icon: "exclamationmark.triangle.fill", title: "Apple Health is unavailable on this device.", color: BetterColors.warning)
        case .requestCompleted, .canQueryHealthData:
            OnboardingNoticeView(icon: "checkmark.circle.fill", title: "Apple Health request completed.", color: BetterColors.success)
        case .noReadableSleepData:
            OnboardingNoticeView(icon: "moon.zzz", title: "Connected, but no readable sleep data was found yet.", color: BetterColors.brand)
        case .failed(let message):
            OnboardingNoticeView(icon: "exclamationmark.circle.fill", title: message, color: BetterColors.warning)
        }
    }

    private func permissionRow(_ title: String, _ body: String, _ icon: String) -> some View {
        HStack(alignment: .top, spacing: BetterSpacing.medium) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(BetterColors.brand)
                .frame(width: 34, height: 34)
                .background(BetterColors.brand.opacity(0.13), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(BetterTypography.subheadline).foregroundStyle(BetterColors.text)
                Text(body).font(BetterTypography.footnote).foregroundStyle(BetterColors.subtext)
            }
        }
    }
}
