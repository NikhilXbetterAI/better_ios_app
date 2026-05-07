import SwiftUI

struct ProfileSettingsView: View {
    @Binding var profile: UserProfile
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            Text("Profile")
                .font(BetterTypography.headline)
                .foregroundStyle(BetterColors.text)

            VStack(spacing: BetterSpacing.medium) {
                preferredNameField
                goalSlider
                baselinePicker
                Toggle("Research Mode", isOn: $profile.isResearchMode)
                    .font(BetterTypography.footnote)
                    .foregroundStyle(BetterColors.text)
                    .tint(BetterColors.brand)
            }

            Button("Save Profile", action: onSave)
                .font(BetterTypography.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, BetterSpacing.medium)
                .background(BetterColors.cardSecondary)
                .foregroundStyle(BetterColors.brand)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .buttonStyle(.plain)
        }
        .padding(BetterSpacing.large)
        .background(BetterColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var preferredNameField: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.xSmall) {
            Text("Preferred Name")
                .font(BetterTypography.footnote)
                .foregroundStyle(BetterColors.text)

            TextField("What can I call you?", text: bindingForDisplayName)
                .font(BetterTypography.body)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .padding(.horizontal, BetterSpacing.medium)
                .padding(.vertical, 12)
                .background(BetterColors.cardSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var goalSlider: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.xSmall) {
            HStack {
                Text("Sleep Goal").font(BetterTypography.footnote).foregroundStyle(BetterColors.text)
                Spacer()
                Text(String(format: "%.1fh", profile.sleepGoalHours))
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.brand)
            }
            Slider(value: $profile.sleepGoalHours, in: 6...10, step: 0.25)
                .tint(BetterColors.brand)
        }
    }

    private var baselinePicker: some View {
        Picker("Baseline Window", selection: $profile.baselineWindowDays) {
            Text("15 days").tag(15)
            Text("30 days").tag(30)
        }
        .pickerStyle(.segmented)
    }

    private var bindingForDisplayName: Binding<String> {
        Binding(
            get: { profile.displayName ?? "" },
            set: { profile.displayName = $0 }
        )
    }
}
