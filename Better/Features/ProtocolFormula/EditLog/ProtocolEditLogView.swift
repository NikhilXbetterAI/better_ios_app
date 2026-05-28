import SwiftUI

struct ProtocolEditLogView: View {
    @Bindable var viewModel: ProtocolEditLogViewModel
    @State private var showWeekConfirm: Bool = false
    private let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    private let weekdays = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: BetterSpacing.section) {
                    // Month switcher
                    monthHeader

                    // Legend
                    legend

                    // Calendar grid
                    VStack(spacing: 8) {
                        weekdayHeader
                        calendarGrid
                    }
                    .padding(12)
                    .background(ProtocolPalette.surfaceColor)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(ProtocolPalette.borderColor, lineWidth: 1))

                    // Bulk shortcut
                    if !viewModel.isMultiSelectMode, let active = viewModel.activeVersion, !viewModel.selectableVersions.isEmpty {
                        bulkActionButton(active: active)
                    }

                    // Log editor
                    if !viewModel.isMultiSelectMode, let key = viewModel.selectedDateKey {
                        editor(for: key)
                    }
                }
                .padding(BetterSpacing.screen)
            }
            .contentMargins(.bottom, viewModel.isMultiSelectMode ? 100 : 20, for: .scrollContent)
            
            if viewModel.isMultiSelectMode && !viewModel.selectedDateKeys.isEmpty {
                bulkActionBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(ProtocolPalette.backgroundColor.ignoresSafeArea())
        .task { await viewModel.onAppear() }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .confirmationDialog(
            "Mark last 7 days as taken?",
            isPresented: $showWeekConfirm,
            titleVisibility: .visible
        ) {
            Button("Mark 7 days taken", role: .destructive) {
                Task { await viewModel.markPastWeekTakenWithActiveVersion() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will overwrite any existing logs for the past 7 days with the active formula.")
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(viewModel.isMultiSelectMode ? "Cancel" : "Select") {
                    withAnimation {
                        viewModel.toggleMultiSelectMode()
                    }
                }
            }
        }
    }

    private var legend: some View {
        let activeVersions = viewModel.selectableVersions.filter { $0.isActive }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(activeVersions) { version in
                    legendChip(
                        color: ProtocolPalette.versionColor(hex: version.colorHex),
                        label: version.resolvedLabel,
                        style: .filled
                    )
                }
                legendChip(color: ProtocolPalette.dimText, label: "Skipped", style: .ring)
                legendChip(color: ProtocolPalette.faintText, label: "No log", style: .empty)
            }
            .padding(.horizontal, 2)
        }
    }

    private enum LegendStyle { case filled, ring, empty }

    private func legendChip(color: Color, label: String, style: LegendStyle) -> some View {
        HStack(spacing: 6) {
            Group {
                switch style {
                case .filled:
                    Circle().fill(color).frame(width: 8, height: 8)
                case .ring:
                    Circle().stroke(color, lineWidth: 1.5).frame(width: 8, height: 8)
                case .empty:
                    Circle().stroke(color, style: StrokeStyle(lineWidth: 1, dash: [2])).frame(width: 8, height: 8)
                }
            }
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ProtocolPalette.mutedText)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.white.opacity(0.04)))
        .overlay(Capsule().stroke(ProtocolPalette.borderColor, lineWidth: 1))
    }

    private func bulkActionButton(active: ProtocolFormulaVersion) -> some View {
        let color = ProtocolPalette.versionColor(hex: active.colorHex)
        return Button {
            showWeekConfirm = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.system(size: 13, weight: .bold))
                Text("Mark all of this week as \(active.resolvedLabel) taken")
                    .font(.system(size: 13, weight: .bold))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(color.opacity(0.55), lineWidth: 1)
                    )
            )
            .foregroundStyle(color)
        }
        .buttonStyle(.plain)
    }

    private var monthHeader: some View {
        HStack {
            Button { viewModel.previousMonth() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .bold))
                    .padding(8)
                    .background(Circle().fill(Color.white.opacity(0.04)))
            }
            Spacer()
            Text(monthTitle)
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(BetterColors.text)
            Spacer()
            Button { viewModel.nextMonth() } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .bold))
                    .padding(8)
                    .background(Circle().fill(Color.white.opacity(0.04)))
            }
        }
        .foregroundStyle(BetterColors.text)
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
        .padding(.vertical, 4)
    }

    private var calendarGrid: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(viewModel.daysInDisplayedMonth(), id: \.self) { date in
                let key = ProtocolEditLogViewModel.dateKey(for: date)
                let log = viewModel.logs[key]
                Button {
                    if viewModel.isMultiSelectMode {
                        viewModel.toggleDateSelection(key)
                    } else {
                        viewModel.select(dateKey: key)
                    }
                } label: {
                    let isSelected = viewModel.isMultiSelectMode
                        ? viewModel.selectedDateKeys.contains(key)
                        : viewModel.selectedDateKey == key
                    cell(date: date, log: log, isSelected: isSelected)
                }
                .buttonStyle(.plain)
                .disabled(ProtocolEditLogViewModel.isFuture(date))
                .accessibilityLabel(cellAccessibilityLabel(date: date, log: log))
            }
        }
    }

    private func cell(date: Date, log: ProtocolNightLog?, isSelected: Bool) -> some View {
        let day = Calendar.current.component(.day, from: date)
        let isFuture = ProtocolEditLogViewModel.isFuture(date)
        let isToday = Calendar.current.isDateInToday(date)
        let ver = log.flatMap(viewModel.version(for:))
        let verColor = ver.map { ProtocolPalette.versionColor(hex: $0.colorHex) } ?? Color.white.opacity(0.12)
        let status = log?.status

        return VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Text("\(day)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isFuture ? ProtocolPalette.dimText : BetterColors.text)
                
                if viewModel.isMultiSelectMode && isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(ProtocolPalette.goodColor)
                        .offset(x: 10, y: -2)
                }
            }

            HStack(spacing: 3) {
                switch status {
                case .taken:
                    Circle()
                        .fill(verColor)
                        .frame(width: 6, height: 6)
                case .skipped:
                    Circle()
                        .stroke(ProtocolPalette.dimText, lineWidth: 1.2)
                        .frame(width: 6, height: 6)
                default:
                    EmptyView()
                }
                if status == .taken, log?.addins.isEmpty == false {
                    Circle()
                        .fill(ProtocolPalette.addinColor)
                        .frame(width: 6, height: 6)
                }
            }
            .frame(height: 6)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.white.opacity(0.10) : Color.white.opacity(isFuture ? 0.0 : 0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(strokeColor(isSelected: isSelected, isToday: isToday, ver: ver), lineWidth: 1.5)
        )
    }

    private func cellAccessibilityLabel(date: Date, log: ProtocolNightLog?) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .none
        let dateStr = fmt.string(from: date)
        guard let log else { return "\(dateStr), no log" }
        let ver = viewModel.version(for: log)
        let vLabel = ver?.resolvedLabel ?? "unknown version"
        switch log.status {
        case .taken: return "\(dateStr), \(vLabel) taken"
        case .skipped: return "\(dateStr), didn't take"
        case .unknown: return "\(dateStr), no log"
        }
    }

    private func strokeColor(isSelected: Bool, isToday: Bool, ver: ProtocolFormulaVersion?) -> Color {
        if isSelected {
            return ver.map { ProtocolPalette.versionColor(hex: $0.colorHex) } ?? ProtocolPalette.brandColor
        }
        if isToday {
            return ProtocolPalette.brandColor
        }
        return Color.clear
    }

    private func editor(for key: String) -> some View {
        let draftVersion = viewModel.versions.first { $0.id == viewModel.draftVersionID }
        let saveButtonColor = draftVersion.map { ProtocolPalette.versionColor(hex: $0.colorHex) } ?? ProtocolPalette.brandColor
        
        return BetterHealthCard {
            VStack(alignment: .leading, spacing: BetterSpacing.medium) {
                BetterSectionHeader(title: key, subtitle: "Log details")

                Picker("Status", selection: $viewModel.draftStatus) {
                    ForEach(ProtocolFormulaNightStatus.allCases, id: \.self) { status in
                        Text(status.displayLabel).tag(status)
                    }
                }
                .pickerStyle(.segmented)

                if viewModel.draftStatus == .taken {
                    versionGrid
                    addinEditor
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Note")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(ProtocolPalette.mutedText)
                        .textCase(.uppercase)
                    
                    TextEditor(text: $viewModel.draftNote)
                        .frame(minHeight: 80)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                }

                Button {
                    Task { await viewModel.saveDraft() }
                } label: {
                    Text("Save Log")
                        .font(.system(size: 15, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(saveButtonColor))
                        .foregroundStyle(draftVersion == nil ? Color.white : Color.black)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var versionGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Version taken")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(ProtocolPalette.mutedText)
                .textCase(.uppercase)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(viewModel.selectableVersions) { version in
                    let selected = viewModel.draftVersionID == version.id
                    let color = ProtocolPalette.versionColor(hex: version.colorHex)
                    Button {
                        viewModel.selectVersion(version)
                    } label: {
                        VStack(spacing: 5) {
                            Circle()
                                .fill(color)
                                .frame(width: 8, height: 8)
                            Text(version.resolvedLabel)
                                .font(.system(size: 12, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
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

    private var addinEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Add-on supplements")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(ProtocolPalette.addinColor)
                    .textCase(.uppercase)
                Spacer()
            }
            
            HStack(spacing: 8) {
                TextField("e.g. GABA 100mg", text: $viewModel.draftAddinText)
                    .font(.system(size: 13))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 1))
                
                Button("Add") { viewModel.addDraftAddin() }
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8).fill(ProtocolPalette.addinColor))
                    .foregroundStyle(Color.black)
                    .buttonStyle(.plain)
            }
            
            // Supplement quick-add chips
            let recents = viewModel.recentAddins
            if !recents.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(recents) { addin in
                            Button {
                                viewModel.addQuickAddin(addin)
                            } label: {
                                Text("+ \(addin.name)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(ProtocolPalette.mutedText)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color.white.opacity(0.04)))
                                    .overlay(Capsule().stroke(ProtocolPalette.borderColor, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            
            if !viewModel.draftAddins.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(viewModel.draftAddins) { addin in
                            Button {
                                viewModel.removeDraftAddin(addin)
                            } label: {
                                Text("+ \(addin.name) ✕")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(ProtocolPalette.addinColor)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(ProtocolPalette.addinColor.opacity(0.12)))
                                    .overlay(Capsule().stroke(ProtocolPalette.addinColor.opacity(0.35), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(ProtocolPalette.surfaceColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(ProtocolPalette.borderColor, lineWidth: 1)
        )
    }
    private var bulkActionBar: some View {
        VStack(spacing: 12) {
            HStack {
                Text("\(viewModel.selectedDateKeys.count) days selected")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(BetterColors.text)
                Spacer()
            }
            
            HStack(spacing: 10) {
                Menu {
                    ForEach(viewModel.selectableVersions) { version in
                        Button(version.resolvedLabel) {
                            Task {
                                await viewModel.markSelectedDatesTaken(versionID: version.id)
                            }
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Mark Taken")
                    }
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Capsule().fill(ProtocolPalette.goodColor))
                    .foregroundStyle(Color.black)
                }
                
                Button {
                    Task {
                        await viewModel.markSelectedDatesSkipped()
                    }
                } label: {
                    HStack {
                        Image(systemName: "moon.zzz.fill")
                        Text("Skipped")
                    }
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
                    .foregroundStyle(BetterColors.text)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(BetterSpacing.medium)
        .background(Color.black.opacity(0.85))
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(ProtocolPalette.borderColor, lineWidth: 1))
        .padding(BetterSpacing.screen)
        .shadow(color: Color.black.opacity(0.4), radius: 10, y: 5)
    }
}
