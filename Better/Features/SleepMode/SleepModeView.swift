import SwiftUI
import UIKit

struct SleepModeView: View {
    @Bindable var viewModel: SleepModeViewModel
    var redLightService: RedLightFilterService? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var moonFloating = false
    @State private var showRedSetup = false

    var body: some View {
        ZStack {
            SleepModeBackdrop(stage: viewModel.stage)

            switch viewModel.stage {
            case .intro:
                introContent
            case .breathing:
                breathingContent
            case .blackout:
                SleepBlackoutView(
                    dimsScreen: viewModel.settings.dimScreenDuringBlackout,
                    onExit: endSession
                )
            }

            if viewModel.redOverlayEnabled && viewModel.stage != .blackout {
                // `.multiply` darkens rather than covers, keeping text/icons readable
                // under the tint. Excluded from `.blackout` — that stage hides all UI.
                Color.red
                    .opacity(0.48)
                    .blendMode(.multiply)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .sheet(isPresented: $showRedSetup) {
            if let redLightService {
                NavigationStack {
                    RedLightFilterSetupView(viewModel: RedLightFilterSetupViewModel(service: redLightService))
                }
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(viewModel.stage == .blackout)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            viewModel.start()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private var introContent: some View {
        VStack(spacing: BetterSpacing.xLarge) {
            topBar(title: "Start Sleep Mode", subtitle: "Wind down without adding stimulation")

            Spacer(minLength: 12)

            VStack(spacing: BetterSpacing.large) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(BetterColors.brandLight)
                    .frame(width: 86, height: 86)
                    .background {
                        ZStack {
                            Circle().fill(BetterColors.brand.opacity(0.18))
                            Circle().fill(RadialGradient(colors: [BetterColors.brand.opacity(0.22), .clear], center: .center, startRadius: 0, endRadius: 60))
                        }
                    }
                    .clipShape(Circle())
                    .offset(y: moonFloating ? -8 : 8)
                    .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: moonFloating)
                    .onAppear { moonFloating = true }

                VStack(spacing: BetterSpacing.small) {
                    Text("Better can remind you at bedtime. Tap the reminder to start Sleep Mode.")
                        .font(BetterTypography.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(BetterColors.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("If Better is already open at bedtime, it can enter Sleep Mode automatically.")
                        .font(BetterTypography.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(BetterColors.subtext)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, BetterSpacing.screen)

            VStack(spacing: BetterSpacing.small) {
                SleepModeIntroStep(icon: "wind", title: "Breathe", detail: "Follow a slow 3-4-7 rhythm.")
                SleepModeIntroStep(icon: "circle.lefthalf.filled", title: "Darken", detail: "Move into a low-stimulation blackout screen.")
                SleepModeIntroStep(icon: "hand.tap.fill", title: "Hold to exit", detail: "A long press prevents accidental wakeups.")
            }
            .padding(.horizontal, BetterSpacing.screen)

            if let redLightService {
                RedLightFilterToggleRow(
                    isSetupComplete: redLightService.isSetupComplete,
                    overlayEnabled: $viewModel.redOverlayEnabled,
                    onTapSystemToggle: {
                        _ = redLightService.toggleSystemRedFilter()
                    },
                    onTapSetup: { showRedSetup = true }
                )
                .padding(.horizontal, BetterSpacing.screen)
            }

            Spacer(minLength: 12)

            VStack(spacing: BetterSpacing.small) {
                Button {
                    viewModel.startBreathing()
                } label: {
                    Label("Start Wind Down", systemImage: "moon.zzz.fill")
                        .font(BetterTypography.headline)
                        .foregroundStyle(BetterColors.text)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, BetterSpacing.medium)
                        .background(BetterColors.brandGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    viewModel.enterBlackout()
                } label: {
                    Label("Skip to Blackout", systemImage: "moon.fill")
                        .font(BetterTypography.subheadline)
                        .foregroundStyle(BetterColors.subtext)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, BetterSpacing.small)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, BetterSpacing.screen)
            .padding(.bottom, BetterSpacing.xLarge)
        }
    }

    private var breathingContent: some View {
        VStack(spacing: 0) {
            topBar(title: "Wind Down", subtitle: "Breathe with the light")

            BreathingLightView(targetRounds: viewModel.settings.breathingRounds) {
                if viewModel.settings.blackoutAfterBreathing {
                    viewModel.enterBlackout()
                } else {
                    endSession()
                }
            }

            Button {
                viewModel.enterBlackout()
            } label: {
                Text("Skip to Blackout")
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.subtext)
            }
            .buttonStyle(.plain)
            .padding(.bottom, BetterSpacing.xLarge)
        }
    }

    private func topBar(title: String, subtitle: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: BetterSpacing.xSmall) {
                Text("SLEEP MODE")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(BetterColors.brandLight)
                    .tracking(1.6)
                Text(title)
                    .font(BetterTypography.title)
                    .foregroundStyle(BetterColors.text)
                Text(subtitle)
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.subtext)
            }

            Spacer()

            Button(action: endSession) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(BetterColors.text)
                    .frame(width: 36, height: 36)
                    .background(BetterColors.cardSecondary, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close Sleep Mode")
        }
        .padding(.horizontal, BetterSpacing.screen)
        .padding(.top, BetterSpacing.xxLarge)
    }

    private func endSession() {
        viewModel.end()
        dismiss()
    }
}

private struct SleepModeIntroStep: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: BetterSpacing.medium) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(BetterColors.brandLight)
                .frame(width: 38, height: 38)
                .background(BetterColors.cardSecondary, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(BetterTypography.subheadline)
                    .foregroundStyle(BetterColors.text)
                Text(detail)
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.subtext)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(BetterSpacing.medium)
        .background(BetterColors.card.opacity(0.82), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(BetterColors.glassStroke, lineWidth: 1)
        )
    }
}

private struct SleepModeBackdrop: View {
    let stage: SleepModeStage

    var body: some View {
        ZStack {
            BetterColors.background.ignoresSafeArea()
            RadialGradient(
                colors: [accent.opacity(0.28), accent.opacity(0.08), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 460
            )
            .ignoresSafeArea()
        }
    }

    private var accent: Color {
        switch stage {
        case .intro:
            BetterColors.brandLight
        case .breathing:
            Color(red: 0.18, green: 0.78, blue: 0.72)
        case .blackout:
            .black
        }
    }
}

#if DEBUG
#Preview {
    SleepModeView(viewModel: SleepModeViewModel())
}
#endif
