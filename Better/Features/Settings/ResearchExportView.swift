import SwiftUI

struct ResearchExportView: View {
    let isResearchMode: Bool
    let isExporting: Bool
    let exportURL: URL?
    let insightSummary: ResearchInsightSummary?
    let onExport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            Text("Research Export")
                .font(BetterTypography.headline)
                .foregroundStyle(BetterColors.text)
            Text("ZIP exports contain derived sleep, protocol, activity, biology, chronotype, and analysis CSVs.")
                .font(BetterTypography.caption)
                .foregroundStyle(BetterColors.subtext)

            if let insightSummary {
                VStack(alignment: .leading, spacing: BetterSpacing.small) {
                    HStack {
                        Label("Research Analysis", systemImage: "chart.xyaxis.line")
                            .font(BetterTypography.subheadline)
                            .foregroundStyle(BetterColors.text)
                        Spacer()
                        Text(insightSummary.confidence.displayName)
                            .font(BetterTypography.caption)
                            .foregroundStyle(BetterColors.subtext)
                    }
                    Text(insightSummary.summary)
                        .font(BetterTypography.caption)
                        .foregroundStyle(BetterColors.subtext)
                    if let confounderNote = insightSummary.confounderNote {
                        Text(confounderNote)
                            .font(BetterTypography.caption)
                            .foregroundStyle(BetterColors.warning)
                    }
                }
                .padding(BetterSpacing.medium)
                .background(BetterColors.cardSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Button(action: onExport) {
                HStack(spacing: BetterSpacing.small) {
                    if isExporting {
                        ProgressView()
                            .tint(BetterColors.text)
                            .controlSize(.small)
                        Text("Preparing export...")
                    } else {
                        Label("Export ZIP", systemImage: "square.and.arrow.down")
                    }
                }
                .font(BetterTypography.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, BetterSpacing.medium)
                .background(isExporting ? BetterColors.cardSecondary : BetterColors.brand)
                .foregroundStyle(BetterColors.text)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isExporting)

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
