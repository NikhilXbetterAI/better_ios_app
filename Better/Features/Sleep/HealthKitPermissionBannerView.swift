import SwiftUI

// MARK: - HealthKit data-quality fallback banner

struct HealthKitFallbackBannerView: View {
    let state: HealthKitFallbackState

    var body: some View {
        switch state {
        case .permissionDenied:
            infoBanner(
                icon: "lock.shield",
                iconColor: BetterColors.warning,
                title: "Apple Health Access Denied",
                body: "Better needs permission to read sleep data locally. Open Settings → Better → Health to grant access."
            )
        case .baselineBuilding(let logged, let needed):
            infoBanner(
                icon: "chart.bar.fill",
                iconColor: BetterColors.brand,
                title: "Building Your Baseline",
                body: "Baseline needs \(needed) nights of data. \(logged) of \(needed) nights logged so far.",
                hint: "Insights improve as more sleep data is collected."
            )
        case .noSleepStages:
            infoBanner(
                icon: "moon.haze.fill",
                iconColor: BetterColors.subtext,
                title: "No Sleep Stage Data",
                body: "Only in-bed time was recorded. For full stage analysis wear your Apple Watch to sleep.",
                hint: "Enable Sleep Tracking in the Apple Watch app."
            )
        case .missingNights(let count):
            infoBanner(
                icon: "calendar.badge.minus",
                iconColor: BetterColors.subtext,
                title: "\(count) Night\(count == 1 ? "" : "s") Missing",
                body: "Some nights have no recorded data, which may affect baseline accuracy."
            )
        case .watchNotWorn:
            infoBanner(
                icon: "applewatch.slash",
                iconColor: BetterColors.subtext,
                title: "Apple Watch Not Detected",
                body: "No Apple Watch sleep data was found for this period. Make sure your watch is charged and worn to sleep."
            )
        case .insufficientHistory:
            infoBanner(
                icon: "clock.badge.xmark",
                iconColor: BetterColors.subtext,
                title: "Not Enough History",
                body: "More sleep data is needed to generate meaningful insights."
            )
        }
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
                title: "Apple Health Access",
                body: "Better reads your sleep and biometric data from Apple Health to show personalized insights.",
                buttonLabel: "Continue",
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
                body: "We couldn't find recent sleep data. Make sure you wore your Apple Watch to bed and Sleep Focus was on.",
                hint: "Data will appear after your next synced night."
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
