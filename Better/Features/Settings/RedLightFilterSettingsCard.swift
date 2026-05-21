import SwiftUI

struct RedLightFilterSettingsCard: View {
    @Bindable var service: RedLightFilterService
    @State private var showSetup = false
    @State private var lastResult: RedLightFilterToggleResult?

    var body: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.small) {
            HStack(spacing: BetterSpacing.medium) {
                Image(systemName: "moon.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.red.opacity(0.9))
                    .frame(width: 38, height: 38)
                    .background(Color.red.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Red Sleep Mode")
                        .font(BetterTypography.subheadline)
                        .foregroundStyle(BetterColors.text)
                    Text(statusText)
                        .font(BetterTypography.caption)
                        .foregroundStyle(BetterColors.subtext)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            Text("Tint your iPhone red at bedtime using your iPhone's Color Filters and a Better Shortcut.")
                .font(BetterTypography.caption)
                .foregroundStyle(BetterColors.subtext)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: BetterSpacing.small) {
                Button {
                    showSetup = true
                } label: {
                    Text(service.isSetupComplete ? "Edit setup" : "Set up")
                        .font(BetterTypography.subheadline)
                        .foregroundStyle(BetterColors.text)
                        .padding(.horizontal, BetterSpacing.medium)
                        .padding(.vertical, BetterSpacing.small)
                        .background(BetterColors.brand.opacity(0.22), in: Capsule())
                }
                .buttonStyle(.plain)

                if service.isSetupComplete {
                    Button {
                        lastResult = service.toggleSystemRedFilter()
                    } label: {
                        Text("Test Red Sleep Mode")
                            .font(BetterTypography.subheadline)
                            .foregroundStyle(BetterColors.brandLight)
                            .padding(.horizontal, BetterSpacing.medium)
                            .padding(.vertical, BetterSpacing.small)
                            .background(BetterColors.cardSecondary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            if let lastResult, lastResult != .openedShortcut {
                Text(message(for: lastResult))
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(BetterSpacing.large)
        .background(BetterColors.cardGradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(BetterColors.glassStroke, lineWidth: 1)
        )
        .sheet(isPresented: $showSetup) {
            NavigationStack {
                RedLightFilterSetupView(viewModel: RedLightFilterSetupViewModel(service: service))
            }
        }
    }

    private var statusText: String {
        switch service.setupStep {
        case .notStarted: return "Setup not started."
        case .colorTintConfiguredByUser: return "Color tint configured. Add the shortcut next."
        case .shortcutAddedByUser: return "Shortcut added. Triple-click is optional."
        case .accessibilityShortcutExplained: return "Almost there. Test the toggle."
        case .complete: return "Ready. Tap to tint your iPhone."
        }
    }

    private func message(for result: RedLightFilterToggleResult) -> String {
        switch result {
        case .openedShortcut: return ""
        case .setupIncomplete: return "Finish setup before testing."
        case .shortcutsUnavailable: return "The Shortcuts app could not be opened. Make sure it is installed."
        case .invalidURL: return "Better could not build the shortcut link."
        }
    }
}
