import SwiftUI

struct AlertDetailSheet: View {
    let alert: SleepAlert
    let onMarkRead: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                BetterColors.background.ignoresSafeArea()
                VStack(alignment: .leading, spacing: BetterSpacing.large) {
                    Label(alert.kind.displayName, systemImage: "bell.fill")
                        .font(BetterTypography.caption)
                        .foregroundStyle(BetterColors.brand)
                    Text(alert.title)
                        .font(BetterTypography.title)
                        .foregroundStyle(BetterColors.text)
                    Text(alert.body)
                        .font(BetterTypography.body)
                        .foregroundStyle(BetterColors.subtext)
                    Spacer()
                    Button {
                        onMarkRead()
                        dismiss()
                    } label: {
                        Text(alert.isRead ? "Done" : "Mark Read")
                            .font(BetterTypography.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, BetterSpacing.medium)
                            .background(BetterColors.brand)
                            .foregroundStyle(BetterColors.text)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(BetterSpacing.screen)
            }
            .navigationTitle("Alert")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

