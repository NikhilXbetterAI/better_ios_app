import SwiftUI

struct HealthStatusView: View {
    let isAvailable: Bool
    let lastSync: Date?
    let isRunningBiomarkerDiagnostic: Bool
    let openSettings: () -> Void
    let runBiomarkerDiagnostic: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            Text("Health")
                .font(BetterTypography.headline)
                .foregroundStyle(BetterColors.text)

            HStack(spacing: BetterSpacing.medium) {
                Image(systemName: isAvailable ? "heart.fill" : "heart.slash.fill")
                    .foregroundStyle(isAvailable ? BetterColors.success : BetterColors.danger)
                    .frame(width: 38, height: 38)
                    .background((isAvailable ? BetterColors.success : BetterColors.danger).opacity(0.16))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(isAvailable ? "Apple Health Available" : "Apple Health Unavailable")
                        .font(BetterTypography.subheadline)
                        .foregroundStyle(BetterColors.text)
                    Text(lastSync.map { "Last sync \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "No completed sync yet")
                        .font(BetterTypography.caption)
                        .foregroundStyle(BetterColors.subtext)
                }
                Spacer()
                Button("Settings", action: openSettings)
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.brand)
                    .buttonStyle(.plain)
            }

            Divider()
                .background(BetterColors.border.opacity(0.5))

            // Support/debug action for missing HRV, resting heart rate, SpO2, or respiratory samples.
            HStack(spacing: BetterSpacing.medium) {
                Image(systemName: "stethoscope")
                    .foregroundStyle(BetterColors.cyan)
                    .frame(width: 38, height: 38)
                    .background(BetterColors.cyan.opacity(0.16))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Biomarker Diagnostic")
                        .font(BetterTypography.subheadline)
                        .foregroundStyle(BetterColors.text)
                    Text("Checks latest sleep night sample counts and sources.")
                        .font(BetterTypography.caption)
                        .foregroundStyle(BetterColors.subtext)
                }
                Spacer()
                Button {
                    runBiomarkerDiagnostic()
                } label: {
                    if isRunningBiomarkerDiagnostic {
                        ProgressView()
                            .tint(BetterColors.brand)
                    } else {
                        Text("Run")
                    }
                }
                .font(BetterTypography.caption)
                .foregroundStyle(BetterColors.brand)
                .buttonStyle(.plain)
                .disabled(isRunningBiomarkerDiagnostic || !isAvailable)
            }
        }
        .padding(BetterSpacing.large)
        .background(BetterColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
