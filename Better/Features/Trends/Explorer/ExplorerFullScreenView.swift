import SwiftUI
import UIKit

/// Full-screen chart presented when the user taps "Expand" in the Explorer card.
/// Forces landscape orientation on appear and restores portrait on dismiss.
/// Layout: compact top bar (metric pills + window picker + Done) above a chart
/// that fills all remaining screen height — like a stock trading terminal.
struct ExplorerFullScreenView: View {
    @Bindable var viewModel: TrendsViewModel
    @Environment(\.dismiss) private var dismiss

    /// Which metric slot is being edited (0 = primary, 1 = compare-1, 2 = compare-2).
    @State private var showMetricSheet = false
    @State private var editingSlot = 0
    /// Guards against the portrait↔landscape loop caused by UIKit re-mounting the
    /// view during the orientation-change layout pass. Once set, forceLandscape()
    /// won't fire again for the lifetime of this presentation.
    @State private var landscapeRequested = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                BetterColors.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    topBar
                        .padding(.horizontal, 16)
                        .frame(height: 52)

                    Divider()
                        .background(BetterColors.border)

                    ExplorerChartView(
                        points: viewModel.chartPoints,
                        secondaryPoints: viewModel.secondaryChartPoints,
                        tertiaryPoints: viewModel.tertiaryChartPoints,
                        primaryMetric: viewModel.selectedMetric,
                        secondaryMetric: viewModel.secondaryMetric,
                        tertiaryMetric: viewModel.tertiaryMetric,
                        chartHeight: max(120, proxy.size.height - 52 - 24)
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showMetricSheet) {
            MetricSelectorSheet(viewModel: viewModel, slot: editingSlot)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.dark)
        }
        // Use .task instead of onAppear so:
        // 1. The task is auto-cancelled if the view disappears early — callback
        //    can never fire after dismiss and trigger the loop.
        // 2. We delay ~400ms to let the fullScreenCover presentation animation
        //    complete before requesting rotation. Calling setNeedsUpdateOfSupported-
        //    InterfaceOrientations() mid-animation causes UIKit to remount the
        //    view hierarchy, which re-fires onAppear/onDisappear in a loop.
        // 3. landscapeRequested guards against the rare case where UIKit still
        //    triggers a re-mount after the delay (seen on some iOS 17/18 builds).
        .task {
            guard !landscapeRequested else { return }
            landscapeRequested = true
            try? await Task.sleep(for: .milliseconds(400))
            forceLandscape()
        }
        .onDisappear {
            // Reset flag so a fresh presentation works correctly.
            landscapeRequested = false
            forcePortrait()
        }
    }

    // MARK: - Orientation helpers

    private func forceLandscape() {
        AppDelegate.orientationLock = .landscape
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape)) { _ in }
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }

    private func forcePortrait() {
        AppDelegate.orientationLock = .portrait
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { _ in }
        // setNeedsUpdateOfSupportedInterfaceOrientations() tells UIKit to re-query
        // the delegate immediately — without this the rotation request is silently dropped.
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 8) {
            // Primary metric pill (always present)
            metricPill(
                label: viewModel.selectedMetric.displayName,
                color: BetterColors.brand,
                slot: 0
            )

            // Compare 1 pill
            if let sec = viewModel.secondaryMetric {
                metricPill(label: sec.displayName, color: BetterColors.success, slot: 1)
            } else {
                addMetricButton(slot: 1, label: "+ Compare")
            }

            // Compare 2 pill — only after compare-1 is chosen
            if viewModel.secondaryMetric != nil {
                if let tert = viewModel.tertiaryMetric {
                    metricPill(label: tert.displayName, color: BetterColors.warning, slot: 2)
                } else {
                    addMetricButton(slot: 2, label: "+ Compare 2")
                }
            }

            Spacer()

            // Compact window picker
            windowPicker

            // Done button — restore portrait BEFORE dismissing so the
            // rotation completes while the view is still the active scene.
            Button {
                forcePortrait()
                dismiss()
            } label: {
                Text("Done")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(BetterColors.brand)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(BetterColors.brand.opacity(0.15), in: Capsule())
                    .overlay(Capsule().stroke(BetterColors.brand.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Metric pills

    private func metricPill(label: String, color: Color, slot: Int) -> some View {
        Button {
            editingSlot = slot
            showMetricSheet = true
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                Text(label)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(BetterColors.text)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(BetterColors.subtext)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.14), in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.28), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func addMetricButton(slot: Int, label: String) -> some View {
        Button {
            editingSlot = slot
            showMetricSheet = true
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(BetterColors.cardSecondary, in: Capsule())
                .overlay(Capsule().stroke(BetterColors.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Window Picker

    private var windowPicker: some View {
        HStack(spacing: 3) {
            ForEach(TrendWindow.allCases) { window in
                Button {
                    Task { await viewModel.selectWindow(window) }
                } label: {
                    Text(window.displayName)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(viewModel.selectedWindow == window ? .black : BetterColors.subtext)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            viewModel.selectedWindow == window ? BetterColors.brand : Color.clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(BetterColors.cardSecondary, in: Capsule())
    }
}

// MARK: - Metric Selector Sheet

/// Bottom sheet for selecting a metric for a given comparison slot.
private struct MetricSelectorSheet: View {
    @Bindable var viewModel: TrendsViewModel
    let slot: Int
    @Environment(\.dismiss) private var dismiss

    private var slotColor: Color {
        switch slot {
        case 0: BetterColors.brand
        case 1: BetterColors.success
        default: BetterColors.warning
        }
    }

    private var slotLabel: String {
        switch slot {
        case 0: "Primary Metric"
        case 1: "Compare 1"
        default: "Compare 2"
        }
    }

    private var currentSelection: TrendMetric? {
        switch slot {
        case 0: viewModel.selectedMetric
        case 1: viewModel.secondaryMetric
        default: viewModel.tertiaryMetric
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    // "None" option for slots 1 and 2
                    if slot > 0 {
                        metricRow(metric: nil)
                        Divider().padding(.leading, 16)
                    }
                    ForEach(TrendMetric.allCases) { metric in
                        // Hide metrics already selected in other slots
                        let isUsedElsewhere = isConflict(metric)
                        if !isUsedElsewhere {
                            metricRow(metric: metric)
                            Divider().padding(.leading, 16)
                        }
                    }
                }
            }
            .navigationTitle(slotLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(slotColor)
                }
            }
        }
    }

    private func isConflict(_ metric: TrendMetric) -> Bool {
        if slot == 0 { return false }
        if slot == 1 { return metric == viewModel.selectedMetric }
        return metric == viewModel.selectedMetric || metric == viewModel.secondaryMetric
    }

    private func select(_ metric: TrendMetric?) {
        switch slot {
        case 0:
            if let m = metric { viewModel.selectMetric(m) }
        case 1:
            viewModel.selectSecondaryMetric(metric)
        default:
            viewModel.selectTertiaryMetric(metric)
        }
        dismiss()
    }

    @ViewBuilder
    private func metricRow(metric: TrendMetric?) -> some View {
        Button {
            select(metric)
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(currentSelection == metric ? slotColor : BetterColors.border)
                    .frame(width: 8, height: 8)

                Text(metric?.displayName ?? "None")
                    .font(BetterTypography.subheadline)
                    .foregroundStyle(BetterColors.text)

                Spacer()

                if currentSelection == metric || (metric == nil && currentSelection == nil && slot > 0) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(slotColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
