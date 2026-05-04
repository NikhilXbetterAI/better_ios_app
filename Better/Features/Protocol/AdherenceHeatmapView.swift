import SwiftUI

struct AdherenceHeatmapView: View {
    let adherence: [ProtocolAdherence]

    private var takenKeys: Set<String> {
        Set(adherence.filter(\.taken).map(\.dateKey))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            Text("21-Day History")
                .font(BetterTypography.headline)
                .foregroundStyle(BetterColors.text)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 7), spacing: 7) {
                ForEach(dayOffsets, id: \.self) { offset in
                    let key = dateKey(offset: offset)
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(takenKeys.contains(key) ? BetterColors.success.opacity(0.28) : BetterColors.cardSecondary)
                        .overlay {
                            if takenKeys.contains(key) {
                                Circle().fill(BetterColors.success).frame(width: 7, height: 7)
                            }
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(takenKeys.contains(key) ? BetterColors.success : BetterColors.border, lineWidth: 1)
                        }
                        .frame(height: 30)
                }
            }
        }
        .padding(BetterSpacing.large)
        .background(BetterColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var dayOffsets: [Int] { Array(-20...0) }

    private func dateKey(offset: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

