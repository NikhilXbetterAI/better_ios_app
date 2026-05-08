import SwiftUI

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BetterSpacing.xLarge) {
                    headerSection
                    dataCollectedSection
                    storageSection
                    notCollectedSection
                    dataRetentionSection
                    exportSection
                    yourRightsSection
                    contactSection
                }
                .padding(BetterSpacing.screen)
                .padding(.bottom, BetterSpacing.xLarge)
            }
            .background(BetterColors.background)
            .navigationTitle("Privacy Policy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(BetterColors.brand)
                }
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.small) {
            Text("Your privacy is fundamental to Better.")
                .font(BetterTypography.title)
                .foregroundStyle(BetterColors.text)
            Text("Last updated: May 2026")
                .font(BetterTypography.caption)
                .foregroundStyle(BetterColors.subtext)
            Text("Better is designed around a simple principle: your health data belongs to you and stays on your device. This policy explains exactly how the app handles your information.")
                .font(BetterTypography.body)
                .foregroundStyle(BetterColors.subtext)
        }
    }

    private var dataCollectedSection: some View {
        policyCard(title: "Data We Read", icon: "heart.text.clipboard", iconColor: BetterColors.heartRate) {
            VStack(alignment: .leading, spacing: BetterSpacing.small) {
                Text("Better reads the following data types from Apple Health with your permission:")
                    .font(BetterTypography.footnote)
                    .foregroundStyle(BetterColors.subtext)
                policyBullet("Sleep Analysis — duration, stages (REM, deep, core), efficiency, latency, awakenings")
                policyBullet("Heart Rate & HRV — overnight and resting measurements")
                policyBullet("Blood Oxygen & Respiratory Rate — from sleep tracking devices")
                policyBullet("Activity — daily steps, calories, exercise minutes, stand hours")
                policyBullet("Body Composition — weight, body fat percentage, wrist temperature")
                policyBullet("Fitness — VO₂ Max estimates")
                Text("Better also stores data you enter directly: protocol check-ins, context logs (caffeine, stress, etc.), and your onboarding answers.")
                    .font(BetterTypography.footnote)
                    .foregroundStyle(BetterColors.subtext)
                    .padding(.top, 2)
            }
        }
    }

    private var storageSection: some View {
        policyCard(title: "How It's Stored", icon: "lock.shield.fill", iconColor: BetterColors.brand) {
            VStack(alignment: .leading, spacing: BetterSpacing.small) {
                policyBullet("All data is stored exclusively on your device — never on a remote server.")
                policyBullet("Sensitive records are encrypted with AES-256-GCM before being written to the local database.")
                policyBullet("The encryption key is stored in iOS Keychain with device-level protection (accessible only when device is unlocked).")
                policyBullet("The database file itself uses iOS Data Protection (FileProtectionType.complete), making it inaccessible while the device is locked.")
            }
        }
    }

    private var notCollectedSection: some View {
        policyCard(title: "What We Never Do", icon: "xmark.shield.fill", iconColor: BetterColors.danger) {
            VStack(alignment: .leading, spacing: BetterSpacing.small) {
                policyBullet("We do not upload your health data to any server.")
                policyBullet("We do not use analytics SDKs, crash reporters, or telemetry services.")
                policyBullet("We do not share your data with third parties.")
                policyBullet("We do not track you across apps or websites.")
                policyBullet("We do not sell your data.")
            }
        }
    }

    private var dataRetentionSection: some View {
        policyCard(title: "Data Retention", icon: "calendar.badge.clock", iconColor: BetterColors.stageDeep) {
            VStack(alignment: .leading, spacing: BetterSpacing.small) {
                policyBullet("Sleep sessions are kept for a 60-day rolling window by default.")
                policyBullet("Protocol and context check-ins are retained for as long as the app is installed.")
                policyBullet("You can delete all locally stored data at any time from Settings → Privacy & Data → Delete all local health data. This resets the app to its initial state.")
                policyBullet("Deleting the app removes all data from your device. Apple Health data is not affected.")
            }
        }
    }

    private var exportSection: some View {
        policyCard(title: "Data Export", icon: "square.and.arrow.up", iconColor: BetterColors.hrv) {
            VStack(alignment: .leading, spacing: BetterSpacing.small) {
                policyBullet("Research Mode (optional, opt-in) enables CSV export of your nightly data.")
                policyBullet("Exports are created locally as ZIP files on your device.")
                policyBullet("You choose where to save or share the file using the standard iOS share sheet.")
                policyBullet("No data is transmitted unless you explicitly choose to share it.")
            }
        }
    }

    private var yourRightsSection: some View {
        policyCard(title: "Your Rights", icon: "person.badge.shield.checkmark", iconColor: BetterColors.success) {
            VStack(alignment: .leading, spacing: BetterSpacing.small) {
                policyBullet("Access — view the data stored by the app in Settings → Privacy & Data.")
                policyBullet("Delete — remove all app data at any time from Settings → Privacy & Data.")
                policyBullet("Revoke — withdraw Apple Health permission at any time in the iOS Health app or Settings.")
                policyBullet("Portability — export your data as CSV from Settings (Research Mode).")
            }
        }
    }

    private var contactSection: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.small) {
            Text("Questions")
                .font(BetterTypography.subheadline)
                .foregroundStyle(BetterColors.text)
            Text("If you have questions about this privacy policy or how Better handles your data, please reach out through the App Store support link on the Better app page.")
                .font(BetterTypography.footnote)
                .foregroundStyle(BetterColors.subtext)
        }
    }

    // MARK: - Helpers

    private func policyCard<Content: View>(title: String, icon: String, iconColor: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            HStack(spacing: BetterSpacing.small) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 30, height: 30)
                    .background(iconColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(title)
                    .font(BetterTypography.subheadline)
                    .foregroundStyle(BetterColors.text)
            }
            content()
        }
        .padding(BetterSpacing.large)
        .background(BetterColors.cardGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(BetterColors.glassStroke, lineWidth: 1)
        )
    }

    private func policyBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: BetterSpacing.small) {
            Text("·")
                .font(BetterTypography.footnote)
                .foregroundStyle(BetterColors.subtext)
                .padding(.top, 1)
            Text(text)
                .font(BetterTypography.footnote)
                .foregroundStyle(BetterColors.subtext)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#if DEBUG
#Preview("Privacy Policy") {
    PrivacyPolicyView()
}
#endif
