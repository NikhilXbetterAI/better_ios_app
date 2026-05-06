import SwiftUI

struct ContextCheckInView: View {
    @Environment(\.dismiss) private var dismiss

    let sleepDateKey: String
    let existingEntry: SleepContextEntry?
    let onSave:  (SleepContextEntry) -> Void
    let onClear: (() -> Void)?

    // MARK: - Local state (mirrors SleepContextEntry fields)
    @State private var caffeineLate:    TriState = .unknown
    @State private var alcohol:         TriState = .unknown
    @State private var workout:         TriState = .unknown
    @State private var lateMeal:        TriState = .unknown
    @State private var highStress:      TriState = .unknown
    @State private var screenTimeLate:  TriState = .unknown
    @State private var nap:             TriState = .unknown
    @State private var travel:          TriState = .unknown
    @State private var perceivedQuality: PerceivedSleepQuality? = nil
    @State private var morningEnergy:    MorningEnergy? = nil
    @State private var notes:            String = ""
    @State private var showNotesField    = false
    @State private var showClearConfirm  = false

    var body: some View {
        NavigationStack {
            ZStack {
                BetterColors.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: BetterSpacing.section) {
                        eveningSection
                        morningSection
                        notesSection
                        disclaimer
                    }
                    .padding(BetterSpacing.screen)
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { dismiss() }
                        .foregroundStyle(BetterColors.subtext)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { commitAndDismiss() }
                        .foregroundStyle(BetterColors.brand)
                        .fontWeight(.semibold)
                }
                if existingEntry != nil {
                    ToolbarItem(placement: .bottomBar) {
                        Button(role: .destructive) {
                            showClearConfirm = true
                        } label: {
                            Label("Clear check-in", systemImage: "trash")
                                .font(BetterTypography.footnote)
                                .foregroundStyle(BetterColors.danger)
                        }
                    }
                }
            }
            .onAppear(perform: loadExistingEntry)
            .confirmationDialog(
                "Clear this check-in?",
                isPresented: $showClearConfirm,
                titleVisibility: .visible
            ) {
                Button("Clear", role: .destructive) {
                    onClear?()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All context fields for this night will be removed.")
            }
        }
    }

    // MARK: - Sections

    private var eveningSection: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            sectionHeader(
                title: "Before Sleep",
                subtitle: "What happened the evening before this night?"
            )

            let rows: [(String, String, Binding<TriState>)] = [
                ("cup.and.saucer.fill", "Caffeine after 2 pm",    $caffeineLate),
                ("wineglass.fill",      "Alcohol",                 $alcohol),
                ("figure.run",          "Workout",                 $workout),
                ("fork.knife",          "Late meal (within 2 hrs)", $lateMeal),
                ("brain.head.profile",  "High stress",             $highStress),
                ("iphone",              "Screen time after 9 pm",  $screenTimeLate),
                ("zzz",                 "Nap during the day",      $nap),
                ("airplane",            "Travel",                  $travel),
            ]

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    triStateRow(icon: row.0, label: row.1, state: row.2)
                    if index < rows.count - 1 {
                        Divider().padding(.leading, 44)
                    }
                }
            }
            .background(BetterColors.card)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var morningSection: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            sectionHeader(
                title: "Morning",
                subtitle: "How did you feel when you woke up?"
            )

            VStack(spacing: BetterSpacing.medium) {
                // Perceived quality
                VStack(alignment: .leading, spacing: BetterSpacing.small) {
                    Text("How rested did you feel?")
                        .font(BetterTypography.footnote)
                        .foregroundStyle(BetterColors.text)
                    HStack(spacing: BetterSpacing.xSmall) {
                        ForEach(PerceivedSleepQuality.allCases) { q in
                            qualityButton(
                                label: q.displayName,
                                emoji: q.emoji,
                                isSelected: perceivedQuality == q
                            ) { perceivedQuality = perceivedQuality == q ? nil : q }
                        }
                    }
                }

                Divider()

                // Morning energy
                VStack(alignment: .leading, spacing: BetterSpacing.small) {
                    Text("Energy level")
                        .font(BetterTypography.footnote)
                        .foregroundStyle(BetterColors.text)
                    HStack(spacing: BetterSpacing.xSmall) {
                        ForEach(MorningEnergy.allCases) { e in
                            qualityButton(
                                label: e.displayName,
                                emoji: e.emoji,
                                isSelected: morningEnergy == e
                            ) { morningEnergy = morningEnergy == e ? nil : e }
                        }
                    }
                }
            }
            .padding(BetterSpacing.large)
            .background(BetterColors.card)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showNotesField.toggle() }
            } label: {
                HStack {
                    Label("Optional notes", systemImage: "pencil")
                        .font(BetterTypography.footnote)
                        .foregroundStyle(BetterColors.subtext)
                    Spacer()
                    Image(systemName: showNotesField ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12))
                        .foregroundStyle(BetterColors.subtext)
                }
                .padding(BetterSpacing.large)
                .background(BetterColors.card)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            if showNotesField {
                TextField("Anything else worth noting…", text: $notes, axis: .vertical)
                    .font(BetterTypography.footnote)
                    .foregroundStyle(BetterColors.text)
                    .lineLimit(3, reservesSpace: true)
                    .padding(BetterSpacing.large)
                    .background(BetterColors.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private var disclaimer: some View {
        Text("Context entries help identify associations in your own data. They are not shared with anyone and do not constitute medical advice.")
            .font(BetterTypography.caption)
            .foregroundStyle(BetterColors.subtext)
            .multilineTextAlignment(.leading)
    }

    // MARK: - Reusable sub-views

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(BetterTypography.headline)
                .foregroundStyle(BetterColors.text)
            Text(subtitle)
                .font(BetterTypography.caption)
                .foregroundStyle(BetterColors.subtext)
        }
    }

    private func triStateRow(icon: String, label: String, state: Binding<TriState>) -> some View {
        HStack(spacing: BetterSpacing.medium) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(BetterColors.brand)
                .frame(width: 28, alignment: .center)

            Text(label)
                .font(BetterTypography.footnote)
                .foregroundStyle(BetterColors.text)

            Spacer()

            // Yes / No / — toggle
            HStack(spacing: 6) {
                triButton("Yes", selected: state.wrappedValue == .yes,  color: BetterColors.success) {
                    state.wrappedValue = state.wrappedValue == .yes ? .unknown : .yes
                }
                triButton("No", selected: state.wrappedValue == .no, color: BetterColors.danger) {
                    state.wrappedValue = state.wrappedValue == .no ? .unknown : .no
                }
            }
        }
        .padding(.horizontal, BetterSpacing.large)
        .padding(.vertical, 12)
    }

    private func triButton(_ label: String, selected: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(BetterTypography.caption)
                .fontWeight(selected ? .semibold : .regular)
                .foregroundStyle(selected ? Color.black : BetterColors.subtext)
                .frame(width: 40, height: 28)
                .background(selected ? color : BetterColors.cardSecondary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: selected)
    }

    private func qualityButton(label: String, emoji: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(emoji).font(.title2)
                Text(label)
                    .font(BetterTypography.caption)
                    .foregroundStyle(isSelected ? Color.black : BetterColors.subtext)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, BetterSpacing.small)
            .background(isSelected ? BetterColors.brand : BetterColors.cardSecondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    // MARK: - Helpers

    private var navigationTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        if let date = SleepDateKey.date(from: sleepDateKey) {
            return "Check-in · \(formatter.string(from: date))"
        }
        return "Sleep Check-in"
    }

    private func loadExistingEntry() {
        guard let entry = existingEntry else { return }
        caffeineLate   = TriState(entry.caffeineLate)
        alcohol        = TriState(entry.alcohol)
        workout        = TriState(entry.workout)
        lateMeal       = TriState(entry.lateMeal)
        highStress     = TriState(entry.highStress)
        screenTimeLate = TriState(entry.screenTimeLate)
        nap            = TriState(entry.nap)
        travel         = TriState(entry.travel)
        perceivedQuality = entry.perceivedSleepQuality
        morningEnergy    = entry.morningEnergy
        notes            = entry.notes ?? ""
        if !notes.isEmpty { showNotesField = true }
    }

    private func commitAndDismiss() {
        let now = Date()
        let entry = SleepContextEntry(
            id: existingEntry?.id ?? UUID(),
            sleepDateKey: sleepDateKey,
            caffeineLate:   caffeineLate.boolValue,
            alcohol:        alcohol.boolValue,
            workout:        workout.boolValue,
            lateMeal:       lateMeal.boolValue,
            highStress:     highStress.boolValue,
            screenTimeLate: screenTimeLate.boolValue,
            nap:            nap.boolValue,
            travel:         travel.boolValue,
            perceivedSleepQuality: perceivedQuality,
            morningEnergy:         morningEnergy,
            notes:    notes.isEmpty ? nil : notes,
            createdAt: existingEntry?.createdAt ?? now,
            updatedAt: now
        )
        onSave(entry)
        dismiss()
    }
}

// MARK: - TriState helper

/// Local view-only enum so we have a clear yes/no/unknown without conflating nil with false.
private enum TriState: Equatable {
    case yes, no, unknown

    init(_ bool: Bool?) {
        switch bool {
        case true:  self = .yes
        case false: self = .no
        case nil:   self = .unknown
        }
    }

    var boolValue: Bool? {
        switch self {
        case .yes:     true
        case .no:      false
        case .unknown: nil
        }
    }
}

#Preview("Check-in — Empty") {
    ContextCheckInView(
        sleepDateKey: "2025-06-12",
        existingEntry: nil,
        onSave: { _ in },
        onClear: nil
    )
}

#Preview("Check-in — Prefilled") {
    let entry = SleepContextEntry(
        sleepDateKey: "2025-06-12",
        caffeineLate: true,
        alcohol: false,
        workout: true,
        highStress: nil
    )
    ContextCheckInView(
        sleepDateKey: "2025-06-12",
        existingEntry: entry,
        onSave: { _ in },
        onClear: {}
    )
}
