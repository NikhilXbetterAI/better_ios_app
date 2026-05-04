import SwiftUI

// MARK: - Heart Rate card matching Heart Rate ExpandableCard in SleepTab.tsx

struct HeartRateCardContent: View {
    let biometrics: NightlyBiometricSummary
    let baseline: SleepBaseline?

    var body: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.large) {
            // Avg / Min / Max row
            HStack {
                Spacer()
                ForEach(hrStats, id: \.label) { stat in
                    VStack(spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(stat.value)
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundStyle(BetterColors.text)
                            Text("BPM")
                                .font(.system(size: 10, design: .rounded))
                                .foregroundStyle(BetterColors.subtext)
                        }
                        Text(stat.label)
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(BetterColors.subtext)
                    }
                    Spacer()
                }
            }

            // HRV divider row
            if let hrv = biometrics.hrvAverage {
                Divider().background(BetterColors.border)
                HRVRow(hrv: hrv, baseline: baseline)
            }

            // SpO2 row
            if let spo2 = biometrics.oxygenSaturationAverage {
                Divider().background(BetterColors.border)
                SpO2Row(spo2: spo2)
            }
        }
    }

    private var hrStats: [(label: String, value: String)] {
        [
            ("Avg", biometrics.heartRateAverage.map { String(format: "%.0f", $0) } ?? "–"),
            ("Min", biometrics.heartRateMinimum.map { String(format: "%.0f", $0) } ?? "–"),
            ("Max", biometrics.heartRateMaximum.map { String(format: "%.0f", $0) } ?? "–"),
        ]
    }
}

// MARK: - HRV inline row

struct HRVRow: View {
    let hrv: Double
    let baseline: SleepBaseline?

    var body: some View {
        HStack {
            Text("Overnight HRV")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.0f", hrv))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(BetterColors.hrv)
                Text("ms")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(BetterColors.subtext)
                if let baselineHRV = baseline?.hrvAverage {
                    let diff = hrv - baselineHRV
                    Text("\(diff >= 0 ? "↑ +" : "↓ ")\(String(format: "%.0f", diff))ms avg")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(diff >= 0 ? BetterColors.success : BetterColors.warning)
                }
            }
        }
    }
}

// MARK: - SpO2 inline row

private struct SpO2Row: View {
    let spo2: Double
    private var percentage: Int { Int(spo2 * 100) }

    var body: some View {
        HStack {
            Text("Blood Oxygen")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(percentage)")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(percentage >= 95 ? BetterColors.success : BetterColors.warning)
                Text("%")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(BetterColors.subtext)
            }
        }
    }
}

// MARK: - Summary row for card header

struct HeartRateSummary: View {
    let biometrics: NightlyBiometricSummary

    var body: some View {
        if let avg = biometrics.heartRateAverage {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.0f", avg))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(BetterColors.text)
                Text("BPM avg")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(BetterColors.subtext)
            }
        } else {
            Text("–")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
        }
    }
}

// MARK: - Respiratory Rate card matching Respiratory Rate card in SleepTab.tsx

struct RespiratoryRateCardContent: View {
    let rate: Double
    let baseline: SleepBaseline?

    var body: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            // Normal range banner
            HStack(spacing: BetterSpacing.small) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Normal Range (12–20 br/min)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(BetterColors.text)
                    Text(rateDescription)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(BetterColors.subtext)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(BetterSpacing.medium)
            .background(BetterColors.hrv.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(BetterColors.hrv.opacity(0.2), lineWidth: 1)
            )

            // Comparison rows
            ForEach(compRows, id: \.label) { row in
                HStack {
                    Text(row.label)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(BetterColors.subtext)
                    Spacer()
                    Text(row.value)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(BetterColors.text)
                }
                .padding(.vertical, BetterSpacing.xSmall)
                Divider().background(BetterColors.border)
            }
        }
    }

    private var rateDescription: String {
        "Your rate of \(String(format: "%.1f", rate)) br/min is \(rate <= 20 ? "healthy" : "elevated"). Elevated respiratory rate can indicate stress or illness."
    }

    private var compRows: [(label: String, value: String)] {
        var rows: [(String, String)] = [("Tonight", String(format: "%.1f br/min", rate))]
        if let avg = baseline?.respiratoryRateAverage {
            rows.append(("\(baseline?.windowDays ?? 30)-Day Avg", String(format: "%.1f br/min", avg)))
        }
        return rows
    }
}
