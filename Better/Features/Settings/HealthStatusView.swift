import SwiftUI

struct HealthStatusView: View {
    let isAvailable: Bool
    let lastSync: Date?
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            Text("Health")
                .font(BetterTypography.headline)
                .foregroundStyle(BetterColors.text)

            HStack(spacing: BetterSpacing.medium) {
                Image(systemName: isAvailable ? "heart.fill" : "heart.slash.fill")
                    .foregroundStyle(isAvailable ? BetterColors.success : BetterColors.danger)
                    .frame(width: 38, height: 38)
                    .background((isAvailable ? BetterColors.success : BetterColors.danger).opacity(0.16))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(isAvailable ? "Apple Health Available" : "Apple Health Unavailable")
                        .font(BetterTypography.subheadline)
                        .foregroundStyle(BetterColors.text)
                    Text(lastSync.map { "Last sync \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "No completed sync yet")
                        .font(BetterTypography.caption)
                        .foregroundStyle(BetterColors.subtext)
                }
                Spacer()
                Button("Settings", action: openSettings)
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.brand)
                    .buttonStyle(.plain)
            }
        }
        .padding(BetterSpacing.large)
        .background(BetterColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

