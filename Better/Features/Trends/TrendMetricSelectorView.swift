import SwiftUI

struct TrendMetricSelectorView: View {
    @Binding var selection: TrendMetric
    let onSelect: (TrendMetric) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BetterSpacing.small) {
                ForEach(TrendMetric.allCases) { metric in
                    Button {
                        selection = metric
                        onSelect(metric)
                    } label: {
                        Text(metric.displayName)
                            .font(BetterTypography.caption)
                            .foregroundStyle(selection == metric ? BetterColors.text : BetterColors.subtext)
                            .padding(.horizontal, BetterSpacing.medium)
                            .padding(.vertical, BetterSpacing.small)
                            .background(selection == metric ? BetterColors.brand.opacity(0.28) : BetterColors.cardSecondary)
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(selection == metric ? BetterColors.brand : BetterColors.border, lineWidth: 1)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

