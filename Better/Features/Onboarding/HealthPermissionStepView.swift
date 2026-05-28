import SwiftUI

struct HealthPermissionStepView: View {
    let authorizationState: HealthAuthorizationPresentationState
    let isWorking: Bool
    let onConnect: () -> Void

    @State private var rowOpacities: [Double] = [0, 0]
    @State private var rowOffsets: [CGFloat] = [20, 20]
    @State private var syncProgress: Double = 0.15

    var body: some View {
        GeometryReader { geometry in
            let screenHeight = geometry.size.height

            VStack(spacing: 0) {
                // ── Hero: Activity rings ───────────────────────────────────────
                ZStack {
                    ActivityRingsHero(rings: ActivityRingsHero.healthRings)
                }
                .frame(height: screenHeight * 0.38)
                .accessibilityHidden(true)

                // ── Text ──────────────────────────────────────────────────────
                VStack(spacing: BetterSpacing.small) {
                    Text("Apple Health Access")
                        .font(BetterTypography.display)
                        .foregroundStyle(BetterColors.text)
                        .multilineTextAlignment(.center)

                    Text("Sleep stages, heart rate, HRV, oxygen saturation, and respiratory rate power the dashboard. Everything processed locally — your data never leaves this device.")
                        .font(BetterTypography.body)
                        .foregroundStyle(BetterColors.subtext)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, BetterSpacing.screen)
                .padding(.top, BetterSpacing.large)

                // ── Permission rows / sync state ──────────────────────────────
                Group {
                    if isWorking {
                        healthSyncingView
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    } else {
                        permissionRowsCard
                            .transition(.opacity)
                    }
                }
                .animation(.spring(response: 0.45, dampingFraction: 0.82), value: isWorking)
                .padding(.horizontal, BetterSpacing.screen)
                .padding(.top, BetterSpacing.xLarge)

                // ── Status ────────────────────────────────────────────────────
                statusView
                    .padding(.horizontal, BetterSpacing.screen)
                    .padding(.top, BetterSpacing.medium)
                    .animation(.spring(response: 0.4, dampingFraction: 0.82), value: authorizationStateKey)

                Spacer(minLength: 0)
                Color.clear.frame(height: 120)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .onAppear { animateRows() }
    }

    // MARK: - Permission rows card

    private var permissionRowsCard: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            permissionRow(
                "Sleep Analysis",
                "Duration, stages, efficiency, latency, and awakenings",
                "moon.zzz.fill",
                BetterColors.stageDeep
            )
            .opacity(rowOpacities[0])
            .offset(y: rowOffsets[0])

            Divider().overlay(BetterColors.border)

            permissionRow(
                "Heart and Recovery",
                "Overnight heart rate, HRV, oxygen, and respiratory rate",
                "waveform.path.ecg",
                BetterColors.heartRate
            )
            .opacity(rowOpacities[1])
            .offset(y: rowOffsets[1])
        }
        .padding(BetterSpacing.large)
        .background(BetterColors.cardGradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(BetterColors.glassStroke, lineWidth: 1)
        )
    }

    // MARK: - Syncing view

    private var healthSyncingView: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.large) {
            HStack(spacing: BetterSpacing.medium) {
                ZStack {
                    MetricGaugeView(progress: syncProgress, color: BetterColors.brand, lineWidth: 5)
                        .frame(width: 44, height: 44)
                    ProgressView()
                        .controlSize(.small)
                        .tint(BetterColors.brand)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Syncing your health data")
                        .font(BetterTypography.subheadline)
                        .foregroundStyle(BetterColors.text)
                    Text("Reading sleep stages, heart rate, and biometrics from Apple Health…")
                        .font(BetterTypography.footnote)
                        .foregroundStyle(BetterColors.brand)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            VStack(spacing: BetterSpacing.small) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(BetterColors.cardSecondary.opacity(0.8))
                        .frame(height: 14)
                        .redacted(reason: .placeholder)
                        .shimmering()
                }
            }
        }
        .padding(BetterSpacing.large)
        .background(BetterColors.cardGradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(BetterColors.glassStroke, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Syncing your health data from Apple Health")
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                syncProgress = 0.85
            }
        }
    }

    // MARK: - Permission row

    private func permissionRow(_ title: String, _ body: String, _ icon: String, _ color: Color) -> some View {
        HStack(alignment: .top, spacing: BetterSpacing.medium) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(BetterTypography.subheadline)
                    .foregroundStyle(BetterColors.text)
                Text(body)
                    .font(BetterTypography.footnote)
                    .foregroundStyle(BetterColors.subtext)
            }
        }
    }

    // MARK: - Status view (unchanged logic)

    @ViewBuilder
    private var statusView: some View {
        switch authorizationState {
        case .notRequested:
            EmptyView()
        case .healthDataUnavailable:
            OnboardingNoticeView(icon: "exclamationmark.triangle.fill", title: "Apple Health is unavailable on this device.", color: BetterColors.warning)
        case .requestCompleted, .canQueryHealthData:
            OnboardingNoticeView(icon: "checkmark.circle.fill", title: "Apple Health connected successfully.", color: BetterColors.success)
        case .noReadableSleepData:
            OnboardingNoticeView(icon: "moon.zzz", title: "Connected, but no sleep data found yet.", color: BetterColors.brand)
        case .failed(let message):
            OnboardingNoticeView(icon: "exclamationmark.circle.fill", title: message, color: BetterColors.warning)
        }
    }

    private var authorizationStateKey: String {
        switch authorizationState {
        case .notRequested:           return "notRequested"
        case .healthDataUnavailable:  return "unavailable"
        case .requestCompleted:       return "completed"
        case .canQueryHealthData:     return "canQuery"
        case .noReadableSleepData:    return "noData"
        case .failed(let m):          return "failed:\(m)"
        }
    }

    // MARK: - Row stagger animation

    private func animateRows() {
        for i in 0..<2 {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.8).delay(Double(i) * 0.12 + 0.3)) {
                rowOpacities[i] = 1
                rowOffsets[i] = 0
            }
        }
    }
}
