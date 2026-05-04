import SwiftUI

// MARK: - HealthKit permission states banner

struct HealthKitPermissionBannerView: View {
    let state: HealthAuthorizationPresentationState
    let onConnect: () -> Void

    var body: some View {
        switch state {
        case .notRequested:
            connectBanner(
                icon: "heart.fill",
                iconColor: BetterColors.heartRate,
                title: "Connect Apple Health",
                body: "Better reads your sleep and biometric data from Apple Health to show personalized insights.",
                buttonLabel: "Connect",
                buttonAction: onConnect
            )

        case .healthDataUnavailable:
            infoBanner(
                icon: "exclamationmark.circle",
                iconColor: BetterColors.warning,
                title: "Apple Health Unavailable",
                body: "This device does not support Apple Health. Sleep tracking requires an iPhone."
            )

        case .requestCompleted, .canQueryHealthData:
            EmptyView()

        case .noReadableSleepData:
            infoBanner(
                icon: "moon.zzz",
                iconColor: BetterColors.brand,
                title: "No Sleep Data Found",
                body: "No sleep data was found in Apple Health. Make sure your Apple Watch is tracking sleep or add sleep data in the Health app.",
                hint: "Try wearing your watch to sleep and check again after syncing."
            )

        case .failed(let message):
            infoBanner(
                icon: "wifi.slash",
                iconColor: BetterColors.warning,
                title: "Sync Error",
                body: message
            )
        }
    }

    // MARK: - Banner styles

    private func connectBanner(
        icon: String,
        iconColor: Color,
        title: String,
        body: String,
        buttonLabel: String,
        buttonAction: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            HStack(spacing: BetterSpacing.medium) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 44, height: 44)
                    .background(iconColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(BetterTypography.subheadline)
                        .foregroundStyle(BetterColors.text)
                    Text(body)
                        .font(BetterTypography.footnote)
                        .foregroundStyle(BetterColors.subtext)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button(action: buttonAction) {
                Text(buttonLabel)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(BetterColors.brand, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(BetterSpacing.large)
        .background(BetterColors.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(BetterColors.brand.opacity(0.3), lineWidth: 1)
        )
    }

    private func infoBanner(
        icon: String,
        iconColor: Color,
        title: String,
        body: String,
        hint: String? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: BetterSpacing.medium) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 36, height: 36)
                .background(iconColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(BetterTypography.subheadline)
                    .foregroundStyle(BetterColors.text)
                Text(body)
                    .font(BetterTypography.footnote)
                    .foregroundStyle(BetterColors.subtext)
                    .fixedSize(horizontal: false, vertical: true)
                if let hint {
                    Text(hint)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(BetterColors.subtext.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
        }
        .padding(BetterSpacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BetterColors.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(BetterColors.border, lineWidth: 1)
        )
    }
}

// MARK: - No-data empty state

struct SleepNoDataView: View {
    let authorizationState: HealthAuthorizationPresentationState
    let onConnect: () -> Void

    var body: some View {
        VStack(spacing: BetterSpacing.xxLarge) {
            Image(systemName: "moon.stars")
                .font(.system(size: 52, weight: .thin))
                .foregroundStyle(BetterColors.brand.opacity(0.6))

            VStack(spacing: BetterSpacing.small) {
                Text("No Sleep Data Yet")
                    .font(BetterTypography.title)
                    .foregroundStyle(BetterColors.text)
                Text("Sleep data will appear here after your first synced night.")
                    .font(BetterTypography.body)
                    .foregroundStyle(BetterColors.subtext)
                    .multilineTextAlignment(.center)
            }

            HealthKitPermissionBannerView(state: authorizationState, onConnect: onConnect)
        }
        .padding(.horizontal, BetterSpacing.screen)
    }
}
