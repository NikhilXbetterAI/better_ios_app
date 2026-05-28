import SwiftUI

struct PreferredNameStepView: View {
    @Binding var displayName: String?
    let onSubmit: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            let screenHeight = geometry.size.height

            VStack(spacing: 0) {
                heroArea
                    .frame(height: screenHeight * 0.34)

                VStack(spacing: BetterSpacing.small) {
                    Text("What can I call you?")
                        .font(BetterTypography.display)
                        .foregroundStyle(BetterColors.text)
                        .multilineTextAlignment(.center)

                    Text("Optional. We’ll use it in your profile and export filenames.")
                        .font(BetterTypography.body)
                        .foregroundStyle(BetterColors.subtext)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, BetterSpacing.screen)
                .padding(.top, BetterSpacing.large)

                VStack(alignment: .leading, spacing: BetterSpacing.small) {
                    Text("Preferred name")
                        .font(BetterTypography.caption)
                        .foregroundStyle(BetterColors.subtext)

                    TextField("What can I call you?", text: binding)
                        .font(BetterTypography.body)
                        .foregroundStyle(BetterColors.text)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($isFocused)
                        .onSubmit {
                            isFocused = false
                            onSubmit()
                        }
                        .padding(.horizontal, BetterSpacing.medium)
                        .padding(.vertical, 14)
                        .background(BetterColors.cardGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(BetterColors.glassStroke, lineWidth: 1)
                        )
                }
                .padding(.horizontal, BetterSpacing.screen)
                .padding(.top, BetterSpacing.xLarge)

                Spacer(minLength: 0)
                Color.clear.frame(height: 120)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .onAppear { isFocused = true }
    }

    private var heroArea: some View {
        ZStack {
            Circle()
                .fill(BetterColors.brand.opacity(0.12))
                .frame(width: 188, height: 188)

            Circle()
                .stroke(BetterColors.brand.opacity(0.18), lineWidth: 1.5)
                .frame(width: 244, height: 244)

            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(BetterColors.brandGradient)
        }
    }

    private var binding: Binding<String> {
        Binding(
            get: { displayName ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                displayName = trimmed.isEmpty ? nil : trimmed
            }
        )
    }
}
