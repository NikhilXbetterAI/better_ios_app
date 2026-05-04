import SwiftUI

struct TrendWindowPickerView: View {
    @Binding var selection: TrendWindow
    let onSelect: (TrendWindow) -> Void

    var body: some View {
        HStack(spacing: BetterSpacing.small) {
            ForEach(TrendWindow.allCases) { window in
                Button {
                    selection = window
                    onSelect(window)
                } label: {
                    Text(window.displayName)
                        .font(BetterTypography.caption)
                        .foregroundStyle(selection == window ? BetterColors.text : BetterColors.subtext)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, BetterSpacing.small)
                        .background(selection == window ? BetterColors.brand : BetterColors.cardSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(BetterColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

