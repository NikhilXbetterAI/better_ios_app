import SwiftUI

struct RedLightFilterSetupView: View {
    @Bindable var viewModel: RedLightFilterSetupViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            BetterColors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: BetterSpacing.section) {
                    header
                    stepCard(
                        number: 1,
                        title: "Make iPhone tint red",
                        body: "Open Settings → Accessibility → Display & Text Size → Color Filters. Turn on Color Filters, choose Color Tint, and drag Intensity and Hue to a deep red.",
                        isComplete: viewModel.step.order >= RedLightFilterSetupStep.colorTintConfiguredByUser.order,
                        primary: ("I configured red tint", { viewModel.confirmColorTintConfigured() }),
                        secondary: ("Open Settings", { viewModel.openAppSettings() }),
                        secondaryHint: "iOS only allows apps to open their own settings page. Navigate to Accessibility manually."
                    )
                    stepCard(
                        number: 2,
                        title: "Add Better shortcut",
                        body: "Add the \"\(RedLightFilterService.shortcutName)\" shortcut from iCloud. It runs the Color Filters toggle when Red Sleep Mode is tapped.",
                        isComplete: viewModel.step.order >= RedLightFilterSetupStep.shortcutAddedByUser.order,
                        primary: ("I added the shortcut", { viewModel.confirmShortcutAdded() }),
                        secondary: ("Get the shortcut", { viewModel.openShortcutInstall() }),
                        secondaryHint: nil
                    )
                    stepCard(
                        number: 3,
                        title: "Enable triple-click (optional)",
                        body: "Settings → Accessibility → Accessibility Shortcut → Color Filters. Triple-clicking the side button will then toggle the same red tint without leaving any app.",
                        isComplete: viewModel.step.order >= RedLightFilterSetupStep.accessibilityShortcutExplained.order,
                        primary: ("Got it", { viewModel.acknowledgeAccessibilityShortcut() }),
                        secondary: nil,
                        secondaryHint: "Recommended, not required."
                    )
                    testCard
                    disclaimer
                }
                .padding(BetterSpacing.screen)
            }
        }
        .navigationTitle("Red Sleep Mode setup")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .font(BetterTypography.subheadline.bold())
                    .foregroundStyle(BetterColors.brand)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.xSmall) {
            Text("Red Sleep Mode")
                .font(BetterTypography.boardDisplay)
                .foregroundStyle(BetterColors.text)
            Text("Better uses your iPhone's Accessibility Color Filter through a Shortcut. One-time setup is required because iOS does not let apps change display color filters directly.")
                .font(BetterTypography.footnote)
                .foregroundStyle(BetterColors.subtext)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var testCard: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            Text("Step 4 · Test toggle")
                .font(BetterTypography.subheadline)
                .foregroundStyle(BetterColors.text)
            Text("This opens the Shortcuts app and runs the toggle. iOS will briefly show Shortcuts before returning to Better.")
                .font(BetterTypography.footnote)
                .foregroundStyle(BetterColors.subtext)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                viewModel.testToggle()
            } label: {
                Text("Test Red Sleep Mode")
                    .font(BetterTypography.headline)
                    .foregroundStyle(BetterColors.text)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, BetterSpacing.medium)
                    .background(BetterColors.brandGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            if let result = viewModel.lastToggleResult {
                switch result {
                case .openedShortcut:
                    Text("Shortcut launched. If your screen did not tint red, edit the shortcut so its only action is Set Color Filters set to Toggle.")
                        .font(BetterTypography.caption)
                        .foregroundStyle(BetterColors.success)
                case .setupIncomplete, .shortcutsUnavailable, .invalidURL:
                    Text(viewModel.recoveryMessage)
                        .font(BetterTypography.caption)
                        .foregroundStyle(BetterColors.warning)
                }
            }
        }
        .padding(BetterSpacing.large)
        .background(BetterColors.cardGradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(BetterColors.glassStroke, lineWidth: 1)
        )
    }

    private var disclaimer: some View {
        Text("iOS does not let apps change display color filters directly. Better uses a Shortcut after you configure the red tint once.")
            .font(BetterTypography.caption)
            .foregroundStyle(BetterColors.subtext)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func stepCard(
        number: Int,
        title: String,
        body: String,
        isComplete: Bool,
        primary: (String, () -> Void),
        secondary: (String, () -> Void)?,
        secondaryHint: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            HStack(spacing: BetterSpacing.small) {
                Text("Step \(number)")
                    .font(BetterTypography.micro)
                    .foregroundStyle(BetterColors.brandLight)
                    .tracking(1.2)
                Spacer()
                if isComplete {
                    Label("Done", systemImage: "checkmark.circle.fill")
                        .font(BetterTypography.micro)
                        .foregroundStyle(BetterColors.success)
                        .labelStyle(.titleAndIcon)
                }
            }
            Text(title)
                .font(BetterTypography.subheadline)
                .foregroundStyle(BetterColors.text)
            Text(body)
                .font(BetterTypography.footnote)
                .foregroundStyle(BetterColors.subtext)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: BetterSpacing.small) {
                Button(action: primary.1) {
                    Text(primary.0)
                        .font(BetterTypography.subheadline)
                        .foregroundStyle(BetterColors.text)
                        .padding(.horizontal, BetterSpacing.medium)
                        .padding(.vertical, BetterSpacing.small)
                        .background(BetterColors.brand.opacity(0.22), in: Capsule())
                }
                .buttonStyle(.plain)

                if let secondary {
                    Button(action: secondary.1) {
                        Text(secondary.0)
                            .font(BetterTypography.subheadline)
                            .foregroundStyle(BetterColors.brandLight)
                            .padding(.horizontal, BetterSpacing.medium)
                            .padding(.vertical, BetterSpacing.small)
                            .background(BetterColors.cardSecondary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            if let secondaryHint {
                Text(secondaryHint)
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.subtext)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(BetterSpacing.large)
        .background(BetterColors.cardGradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(BetterColors.glassStroke, lineWidth: 1)
        )
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        RedLightFilterSetupView(viewModel: RedLightFilterSetupViewModel(service: RedLightFilterService()))
    }
}
#endif
