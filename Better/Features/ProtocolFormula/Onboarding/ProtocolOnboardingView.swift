import SwiftUI

struct ProtocolOnboardingView: View {
    @Bindable var viewModel: ProtocolOnboardingViewModel
    let onCompleted: () -> Void
    private let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)
    private let weekdays = ["M", "T", "W", "T", "F", "S", "S"]

    @State private var currentStep: Int = 1

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BetterSpacing.section) {
                stepIndicator
                
                switch currentStep {
                case 1:
                    welcomeStep
                case 2:
                    paintHistoryStep
                case 3:
                    currentActiveStep
                default:
                    welcomeStep
                }
            }
            .padding(BetterSpacing.screen)
        }
        .background(ProtocolPalette.backgroundColor.ignoresSafeArea())
        .task { await viewModel.onAppear() }
        .onChange(of: viewModel.isCompleted) { _, completed in
            if completed { onCompleted() }
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Step indicator dots

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(1...3, id: \.self) { step in
                Capsule()
                    .fill(step == currentStep ? ProtocolPalette.brandColor : Color.white.opacity(0.12))
                    .frame(width: step == currentStep ? 24 : 8, height: 8)
            }
            Spacer()
        }
    }

    // MARK: - Step 1: Welcome Screen

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.large) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Sleep Protocol Tracking")
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(BetterColors.text)
                Text("Optimize your sleep by measuring supplement formulas against your baseline.")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ProtocolPalette.mutedText)
            }

            VStack(spacing: 16) {
                featureBenefitRow(
                    icon: "flask.fill",
                    color: ProtocolPalette.brandColor,
                    title: "Controlled versions",
                    desc: "Track changes to supplements, timing, or dosage under distinct versions (V1, V2, etc.)."
                )
                featureBenefitRow(
                    icon: "chart.bar.xaxis",
                    color: ProtocolPalette.goodColor,
                    title: "Baseline comparison",
                    desc: "Measure improvements and sleep lifts relative to your custom baseline sleep period."
                )
                featureBenefitRow(
                    icon: "calendar.badge.checkmark",
                    color: ProtocolPalette.mutedText,
                    title: "Edit history",
                    desc: "Correct any night's log and keep a full audit trail of changes."
                )
            }
            .padding(.vertical, 8)

            Button {
                withAnimation { currentStep = 2 }
            } label: {
                Text("Next: Paint History")
                    .font(.system(size: 15, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(ProtocolPalette.brandColor))
                    .foregroundStyle(Color.black)
            }
            .buttonStyle(.plain)
        }
    }

    private func featureBenefitRow(icon: String, color: Color, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(BetterColors.text)
                Text(desc)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(ProtocolPalette.dimText)
            }
        }
    }

    // MARK: - Step 2: Paint History

    private var paintHistoryStep: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Paint history ranges")
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(BetterColors.text)
                Text("Tap a start date on the calendar, then tap an end date to apply a version to that range.")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(ProtocolPalette.mutedText)
            }
            
            versionSelector
            calendarCard
            summaryCard
            
            HStack(spacing: BetterSpacing.small) {
                Button {
                    withAnimation { currentStep = 1 }
                } label: {
                    Text("Back")
                        .font(.system(size: 15, weight: .bold))
                        .padding(.vertical, 12)
                        .padding(.horizontal, 24)
                        .background(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1.5))
                        .foregroundStyle(BetterColors.text)
                }
                .buttonStyle(.plain)
                
                Button {
                    withAnimation { currentStep = 3 }
                } label: {
                    Text("Next: Active Formula")
                        .font(.system(size: 15, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(ProtocolPalette.brandColor))
                        .foregroundStyle(Color.black)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var versionSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select version to paint")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(ProtocolPalette.dimText)
                .textCase(.uppercase)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(viewModel.versions) { version in
                    let selected = viewModel.selectedVersionID == version.id
                    let color = ProtocolPalette.versionColor(hex: version.colorHex)
                    Button {
                        viewModel.selectVersion(version)
                    } label: {
                        VStack(spacing: 4) {
                            Circle()
                                .fill(color)
                                .frame(width: 8, height: 8)
                            Text(version.resolvedLabel)
                                .font(.system(size: 12, weight: .bold))
                            Text("\(viewModel.paintedCount(for: version)) nights")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(ProtocolPalette.dimText)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(selected ? color.opacity(0.12) : Color.white.opacity(0.03))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(selected ? color : Color.white.opacity(0.08), lineWidth: 1.5)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(BetterColors.text)
                }
            }
        }
    }

    private var calendarCard: some View {
        BetterHealthCard {
            VStack(alignment: .leading, spacing: BetterSpacing.medium) {
                monthHeader
                weekdayHeader
                
                LazyVGrid(columns: columns, spacing: 5) {
                    ForEach(viewModel.daysInDisplayedMonth(), id: \.self) { date in
                        Button {
                            viewModel.tapDate(date)
                        } label: {
                            calendarCell(date)
                        }
                        .buttonStyle(.plain)
                        .disabled(ProtocolOnboardingViewModel.isFuture(date))
                    }
                }
                
                if let start = viewModel.pendingRangeStartKey {
                    HStack {
                        Text("Range started \(start). Tap an end date.")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(ProtocolPalette.addinColor)
                        Spacer()
                        Button("Cancel") { viewModel.clearSelectedRangeStart() }
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(ProtocolPalette.badColor)
                    }
                }
            }
        }
    }

    private var monthHeader: some View {
        HStack {
            Button { viewModel.previousMonth() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .padding(8)
                    .background(Circle().fill(Color.white.opacity(0.04)))
            }
            Spacer()
            Text(monthTitle)
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(BetterColors.text)
            Spacer()
            Button { viewModel.nextMonth() } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .padding(8)
                    .background(Circle().fill(Color.white.opacity(0.04)))
            }
        }
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: viewModel.displayedMonth)
    }

    private var weekdayHeader: some View {
        HStack {
            ForEach(weekdays, id: \.self) { day in
                Text(day)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(ProtocolPalette.dimText)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func calendarCell(_ date: Date) -> some View {
        let day = Calendar.current.component(.day, from: date)
        let version = viewModel.version(forDate: date)
        let isPending = viewModel.pendingRangeStartKey == ProtocolOnboardingViewModel.dateKey(for: date)
        let isFuture = ProtocolOnboardingViewModel.isFuture(date)
        let color = version.map { ProtocolPalette.versionColor(hex: $0.colorHex) } ?? Color.white.opacity(0.12)
        
        return VStack(spacing: 4) {
            Text("\(day)")
                .font(.system(size: 12, weight: isPending ? .black : .bold))
                .foregroundStyle(isFuture ? ProtocolPalette.dimText : BetterColors.text)
            Circle()
                .fill(version != nil ? color : Color.clear)
                .frame(width: 5, height: 5)
        }
        .frame(maxWidth: .infinity, minHeight: 40)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(version.map { ProtocolPalette.versionColor(hex: $0.colorHex).opacity(0.10) } ?? Color.white.opacity(isFuture ? 0.0 : 0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isPending ? ProtocolPalette.addinColor : Color.clear, lineWidth: 1.5)
        )
    }

    private var summaryCard: some View {
        BetterHealthCard {
            VStack(alignment: .leading, spacing: 8) {
                BetterSectionHeader(title: "History Summary")
                ForEach(viewModel.versions) { version in
                    HStack {
                        VersionChip(version: version, size: .xs)
                        Spacer()
                        Text("\(viewModel.paintedCount(for: version)) nights")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(ProtocolPalette.mutedText)
                    }
                }
            }
        }
    }

    // MARK: - Step 3: Current Active Formula

    private var currentActiveStep: some View {
        let activeVer = viewModel.versions.first { $0.id == viewModel.currentVersionID }
        let saveButtonColor = activeVer.map { ProtocolPalette.versionColor(hex: $0.colorHex) } ?? ProtocolPalette.brandColor
        
        return VStack(alignment: .leading, spacing: BetterSpacing.large) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Select active formula")
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(BetterColors.text)
                Text("Which version are you taking tonight?")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(ProtocolPalette.mutedText)
            }

            VStack(spacing: 8) {
                ForEach(viewModel.versions) { version in
                    let isCurrent = viewModel.currentVersionID == version.id
                    let color = ProtocolPalette.versionColor(hex: version.colorHex)
                    Button {
                        viewModel.setCurrentVersion(version)
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(color)
                                .frame(width: 8, height: 8)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(version.resolvedLabel)
                                    .font(.system(size: 15, weight: .black))
                                if !version.formulaText.isEmpty {
                                    Text(version.formulaText)
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(ProtocolPalette.mutedText)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(isCurrent ? color.opacity(0.12) : Color.white.opacity(0.03))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(isCurrent ? color : Color.white.opacity(0.08), lineWidth: 1.5)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(BetterColors.text)
                }
            }

            HStack(spacing: BetterSpacing.small) {
                Button {
                    withAnimation { currentStep = 2 }
                } label: {
                    Text("Back")
                        .font(.system(size: 15, weight: .bold))
                        .padding(.vertical, 12)
                        .padding(.horizontal, 24)
                        .background(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1.5))
                        .foregroundStyle(BetterColors.text)
                }
                .buttonStyle(.plain)
                
                Button {
                    Task { await viewModel.finish() }
                } label: {
                    Text("Finish and Start")
                        .font(.system(size: 15, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(saveButtonColor))
                        .foregroundStyle(activeVer == nil ? Color.white : Color.black)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
