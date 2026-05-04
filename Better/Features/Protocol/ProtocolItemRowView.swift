import SwiftUI

struct ProtocolItemRowView: View {
    let item: ProtocolItem
    let isTaken: Bool
    let onMarkTaken: () -> Void

    var body: some View {
        HStack(spacing: BetterSpacing.medium) {
            Circle()
                .fill(Color(hex: item.colorHex ?? "#6366F1"))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(BetterTypography.subheadline)
                    .foregroundStyle(BetterColors.text)
                Text(item.benefit)
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.subtext)
                    .lineLimit(2)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: BetterSpacing.xSmall) {
                Text(item.dose)
                    .font(BetterTypography.caption)
                    .foregroundStyle(Color(hex: item.colorHex ?? "#6366F1"))
                Button {
                    if !isTaken { onMarkTaken() }
                } label: {
                    Image(systemName: isTaken ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(isTaken ? BetterColors.success : BetterColors.subtext)
                        .accessibilityLabel(isTaken ? "\(item.name) taken" : "Mark \(item.name) taken")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(BetterSpacing.large)
        .background(BetterColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

