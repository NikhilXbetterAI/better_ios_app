import SwiftUI

struct ResearchExportView: View {
    let isResearchMode: Bool
    let isExporting: Bool
    let exportURL: URL?
    let onExport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            Text("Research Export")
                .font(BetterTypography.headline)
                .foregroundStyle(BetterColors.text)
            Text("CSV exports contain derived nightly summaries, not raw HealthKit identifiers.")
                .font(BetterTypography.caption)
                .foregroundStyle(BetterColors.subtext)

            Button(action: onExport) {
                Label(isExporting ? "Exporting" : "Export CSV", systemImage: "square.and.arrow.down")
                    .font(BetterTypography.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, BetterSpacing.medium)
                    .background(isResearchMode ? BetterColors.brand : BetterColors.cardSecondary)
                    .foregroundStyle(isResearchMode ? BetterColors.text : BetterColors.subtext)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!isResearchMode || isExporting)

            if let exportURL {
                Text(exportURL.lastPathComponent)
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.success)
            }
        }
        .padding(BetterSpacing.large)
        .background(BetterColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

