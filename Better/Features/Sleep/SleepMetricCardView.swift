import SwiftUI

// MARK: - Expandable card matching ExpandableCard.tsx

struct SleepMetricCard<Summary: View, Content: View>: View {
    let title: String
    let iconName: String
    let iconColor: Color
    @State var isExpanded: Bool
    @ViewBuilder let summary: Summary
    @ViewBuilder let content: Content

    init(
        title: String,
        iconName: String,
        iconColor: Color,
        defaultExpanded: Bool = false,
        @ViewBuilder summary: () -> Summary,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.iconName = iconName
        self.iconColor = iconColor
        self.isExpanded = defaultExpanded
        self.summary = summary()
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header row — always visible
            Button {
                withAnimation(.easeInOut(duration: 0.22)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: BetterSpacing.medium) {
                    Image(systemName: iconName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(iconColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Text(title)
                        .font(BetterTypography.subheadline)
                        .foregroundStyle(BetterColors.text)

                    Spacer()

                    summary

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(BetterColors.subtext)
                }
                .padding(.horizontal, BetterSpacing.large)
                .padding(.vertical, BetterSpacing.medium)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .background(BetterColors.border)

                content
                    .padding(.horizontal, BetterSpacing.large)
                    .padding(.vertical, BetterSpacing.large)
            }
        }
        .background(BetterColors.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(BetterColors.border, lineWidth: 1)
        )
    }
}

// MARK: - Plain (non-expandable) card

struct SleepPlainCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
                .tracking(0.6)

            content
        }
        .padding(BetterSpacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BetterColors.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(BetterColors.border, lineWidth: 1)
        )
    }
}
