import SwiftUI

struct ProtocolTabView: View {
    @Bindable var viewModel: ProtocolViewModel

    var body: some View {
        ZStack {
            BetterColors.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: BetterSpacing.section) {
                    header
                    primaryProtocolCard
                    AdherenceStreakBannerView(streak: viewModel.adherenceStreak)
                    AdherenceHeatmapView(adherence: viewModel.adherenceHistory)
                    ProtocolImpactChartView(summary: viewModel.impactSummary)
                    itemList
                }
                .padding(BetterSpacing.screen)
            }
        }
        .navigationTitle("Protocol")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.onAppear() }
        .refreshable { await viewModel.loadTodayAdherence() }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: BetterSpacing.xSmall) {
                Text("Protocol")
                    .font(BetterTypography.display)
                    .foregroundStyle(BetterColors.text)
                Text("Evening sleep-support routine")
                    .font(BetterTypography.footnote)
                    .foregroundStyle(BetterColors.subtext)
            }
            Spacer()
            Text("Active")
                .font(BetterTypography.caption)
                .foregroundStyle(BetterColors.success)
                .padding(.horizontal, BetterSpacing.medium)
                .padding(.vertical, BetterSpacing.xSmall)
                .background(BetterColors.success.opacity(0.18))
                .clipShape(Capsule())
        }
    }

    private var primaryProtocolCard: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            HStack(spacing: BetterSpacing.medium) {
                Image(systemName: "pills.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(BetterColors.brand)
                    .frame(width: 48, height: 48)
                    .background(BetterColors.brand.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Better Sleep Formula")
                        .font(BetterTypography.title)
                        .foregroundStyle(BetterColors.text)
                    Text("Take 30-60 min before bed")
                        .font(BetterTypography.footnote)
                        .foregroundStyle(BetterColors.subtext)
                }
            }

            if let item = viewModel.items.first {
                Button {
                    Task { await viewModel.markTaken(item) }
                } label: {
                    Label(viewModel.isTakenToday(item) ? "Taken Tonight" : "Mark as Taken", systemImage: viewModel.isTakenToday(item) ? "checkmark.circle.fill" : "circle")
                        .font(BetterTypography.headline)
                        .foregroundStyle(viewModel.isTakenToday(item) ? Color.black : BetterColors.success)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, BetterSpacing.medium)
                        .background(viewModel.isTakenToday(item) ? BetterColors.success : BetterColors.success.opacity(0.16))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(BetterSpacing.large)
        .background(BetterColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var itemList: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            Text("Ingredients")
                .font(BetterTypography.headline)
                .foregroundStyle(BetterColors.text)
            ForEach(viewModel.items) { item in
                ProtocolItemRowView(item: item, isTaken: viewModel.isTakenToday(item)) {
                    Task { await viewModel.markTaken(item) }
                }
            }
        }
    }
}

#Preview("Protocol") {
    ProtocolTabView(viewModel: ProtocolViewModel(localRepository: AppEnvironment.preview().localRepository))
}
