import SwiftUI

struct ManualBiologyEntrySheet: View {
    let kind: BiologyMetricKind
    let onSave: (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var inputText: String = ""
    @FocusState private var isFieldFocused: Bool

    private var metric: (title: String, unit: String, placeholder: String, hint: String) {
        switch kind {
        case .vo2Max:
            return ("VO2 Max", "mL/kg/min", "e.g. 42.5", "Typical range: 30–70 mL/kg/min")
        case .hrvBaseline:
            return ("HRV Baseline", "ms", "e.g. 55", "Typical range: 20–100 ms")
        case .restingHeartRateBaseline:
            return ("Resting Heart Rate", "bpm", "e.g. 60", "Typical range: 40–100 bpm")
        case .weight:
            return ("Weight", "kg", "e.g. 75.0", "Enter your weight in kilograms")
        case .leanBodyMass:
            return ("Lean Body Mass", "kg", "e.g. 60.0", "Enter lean mass in kilograms")
        case .bodyFatPercentage:
            return ("Body Fat", "%", "e.g. 18", "Typical range: 8–35%")
        case .bloodOxygen:
            return ("Blood Oxygen", "%", "e.g. 98", "Typical range: 95–100%")
        case .respiratoryRate:
            return ("Respiratory Rate", "br/min", "e.g. 14", "Typical range: 12–20 br/min")
        case .bodyTemperature:
            return ("Body Temperature", "°C", "e.g. 36.6", "Typical range: 36.1–37.2 °C")
        }
    }

    private var parsedValue: Double? {
        Double(inputText.trimmingCharacters(in: .whitespaces))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BetterColors.background.ignoresSafeArea()

                VStack(alignment: .leading, spacing: BetterSpacing.large) {
                    // Description
                    Text("This value will appear on your Biology tab and will be replaced automatically once Apple Health provides data.")
                        .font(BetterTypography.footnote)
                        .foregroundStyle(BetterColors.subtext)
                        .padding(.top, BetterSpacing.small)

                    // Input card
                    VStack(alignment: .leading, spacing: BetterSpacing.medium) {
                        Text("Value")
                            .font(BetterTypography.caption)
                            .foregroundStyle(BetterColors.subtext)
                            .textCase(.uppercase)

                        HStack(alignment: .center, spacing: BetterSpacing.small) {
                            TextField(metric.placeholder, text: $inputText)
                                .keyboardType(.decimalPad)
                                .font(BetterTypography.title)
                                .foregroundStyle(BetterColors.text)
                                .focused($isFieldFocused)

                            Text(metric.unit)
                                .font(BetterTypography.subheadline)
                                .foregroundStyle(BetterColors.subtext)
                        }

                        Divider()
                            .background(BetterColors.cardSecondary)

                        Text(metric.hint)
                            .font(BetterTypography.caption)
                            .foregroundStyle(BetterColors.subtext)
                    }
                    .padding(BetterSpacing.large)
                    .background(BetterColors.card)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    // Save button
                    Button {
                        if let value = parsedValue {
                            onSave(value)
                            dismiss()
                        }
                    } label: {
                        Text("Save")
                            .font(BetterTypography.headline)
                            .foregroundStyle(parsedValue != nil ? BetterColors.text : BetterColors.subtext)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, BetterSpacing.medium)
                            .background(parsedValue != nil ? BetterColors.brand : BetterColors.cardSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .disabled(parsedValue == nil)

                    Spacer()
                }
                .padding(.horizontal, BetterSpacing.screen)
                .padding(.top, BetterSpacing.medium)
            }
            .navigationTitle("Add \(metric.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(BetterColors.subtext)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear { isFieldFocused = true }
    }
}
