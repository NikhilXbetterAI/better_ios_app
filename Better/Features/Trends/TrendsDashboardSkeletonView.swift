import SwiftUI

/// Loading skeleton for the Trends / Insights tab.
/// Mirrors `SleepDashboardSkeletonView` — uses `.redacted(reason: .placeholder)` + `.shimmering()`.
struct TrendsDashboardSkeletonView: View {
    var body: some View {
        VStack(spacing: BetterSpacing.section) {
            headerSkeleton
            windowPickerSkeleton
            comparisonBannerSkeleton
            overviewCardSkeleton
            explorerCardSkeleton
            smallCardSkeleton
            smallCardSkeleton
            Spacer(minLength: BetterSpacing.xxLarge)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .redacted(reason: .placeholder)
        .shimmering()
    }

    // MARK: - Header

    private var headerSkeleton: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("BETTER SLEEP")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.6)
            Text("Sleep Insights")
                .font(BetterTypography.display)
            Text("Patterns and trends from your sleep history")
                .font(BetterTypography.footnote)
        }
        .padding(.top, 58)
    }

    // MARK: - Window picker (3-segment)

    private var windowPickerSkeleton: some View {
        HStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(BetterColors.cardSecondary)
                    .frame(height: 34)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 3)
            }
        }
        .padding(4)
        .background(BetterColors.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Comparison banner (1 row)

    private var comparisonBannerSkeleton: some View {
        HStack(spacing: BetterSpacing.medium) {
            Circle()
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text("You slept more than your 30D average (7.5h usual).")
                    .font(BetterTypography.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Text("18 nights tracked")
                    .font(BetterTypography.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(BetterSpacing.large)
        .background(BetterColors.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Overview card (sparkline rect + ring circle)

    private var overviewCardSkeleton: some View {
        HStack(alignment: .top, spacing: BetterSpacing.medium) {
            VStack(alignment: .leading, spacing: BetterSpacing.xSmall) {
                Text("SLEEP SCORE TREND")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(BetterColors.cardSecondary)
                    .frame(height: 52)
                Text("18 nights tracked")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            VStack(spacing: BetterSpacing.small) {
                Circle()
                    .frame(width: 72, height: 72)
                Text("Sleep Score")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
            }
        }
        .padding(BetterSpacing.large)
        .background(BetterColors.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Explorer card (~190pt chart area)

    private var explorerCardSkeleton: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            HStack {
                Text("Total Sleep")
                    .font(BetterTypography.headline)
                Spacer()
                Text("hrs")
                    .font(BetterTypography.caption)
            }
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(BetterColors.cardSecondary)
                .frame(height: 190)
        }
        .padding(BetterSpacing.large)
        .background(BetterColors.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Small cards

    private var smallCardSkeleton: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            HStack(spacing: BetterSpacing.medium) {
                Circle()
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Insight Title")
                        .font(BetterTypography.subheadline)
                    Text("Insight summary line goes here")
                        .font(BetterTypography.footnote)
                }
                Spacer()
            }
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(BetterColors.cardSecondary)
                .frame(height: 56)
        }
        .padding(BetterSpacing.large)
        .background(BetterColors.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

#if DEBUG
#Preview {
    ZStack {
        BetterColors.background.ignoresSafeArea()
        ScrollView {
            TrendsDashboardSkeletonView()
                .padding(.horizontal, BetterSpacing.screen)
        }
    }
    .preferredColorScheme(.dark)
}
#endif
