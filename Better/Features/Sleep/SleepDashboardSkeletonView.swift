import SwiftUI

struct SleepDashboardSkeletonView: View {
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: BetterSpacing.medium) {
                headerSkeleton
                    .padding(.horizontal, BetterSpacing.screen)
                
                scoreCardSkeleton
                    .padding(.horizontal, BetterSpacing.screen)
                
                metricCardSkeleton(height: 180)
                    .padding(.horizontal, BetterSpacing.screen)
                
                metricCardSkeleton(height: 120)
                    .padding(.horizontal, BetterSpacing.screen)
                
                Spacer(minLength: BetterSpacing.xxLarge)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, BetterSpacing.screen)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        .redacted(reason: .placeholder)
        .shimmering()
    }
    
    private var headerSkeleton: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("BETTER SLEEP")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                
                Text("Tonight's Sleep")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                
                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Today, Jan 1")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            
            Spacer()
            
            Circle()
                .frame(width: 36, height: 36)
        }
    }
    
    private var scoreCardSkeleton: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            HStack(spacing: BetterSpacing.medium) {
                Circle()
                    .frame(width: 36, height: 36)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text("Sleep Score")
                        .font(BetterTypography.subheadline)
                    Text("85")
                        .font(BetterTypography.title)
                }
                Spacer()
            }
            
            HStack(alignment: .center, spacing: BetterSpacing.large) {
                Circle()
                    .frame(width: 120, height: 120)
                
                VStack(spacing: BetterSpacing.small) {
                    metricRowSkeleton()
                    metricRowSkeleton()
                    metricRowSkeleton()
                    metricRowSkeleton()
                    
                    Divider().background(BetterColors.border)
                    
                    metricRowSkeleton()
                    metricRowSkeleton()
                }
            }
        }
        .padding(BetterSpacing.large)
        .background(BetterColors.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
    
    private func metricCardSkeleton(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            HStack(spacing: BetterSpacing.medium) {
                Circle()
                    .frame(width: 36, height: 36)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text("Metric Title")
                        .font(BetterTypography.subheadline)
                    Text("Metric Summary")
                        .font(BetterTypography.footnote)
                }
                Spacer()
                Image(systemName: "chevron.up")
                    .font(.system(size: 14, weight: .semibold))
            }
            
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(BetterColors.cardSecondary)
                .frame(height: height)
        }
        .padding(BetterSpacing.large)
        .background(BetterColors.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
    
    private func metricRowSkeleton() -> some View {
        HStack {
            Text("Label")
                .font(.system(size: 12, design: .rounded))
            Spacer()
            Text("Value")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
    }
}

#Preview {
    ZStack {
        BetterColors.background.ignoresSafeArea()
        SleepDashboardSkeletonView()
    }
    .preferredColorScheme(.dark)
}
