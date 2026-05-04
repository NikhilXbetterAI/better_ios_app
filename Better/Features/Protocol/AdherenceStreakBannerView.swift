import SwiftUI

struct AdherenceStreakBannerView: View {
    let streak: Int

    var body: some View {
        HStack(spacing: BetterSpacing.medium) {
            Image(systemName: "flame.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(BetterColors.warning)
                .frame(width: 48, height: 48)
                .background(BetterColors.warning.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("\(streak) Day Streak")
                    .font(BetterTypography.title)
                    .foregroundStyle(BetterColors.text)
                Text("Consistency is tracked from cached adherence logs.")
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.subtext)
            }
            Spacer()
        }
        .padding(BetterSpacing.large)
        .background(BetterColors.card)
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(BetterColors.warning.opacity(0.28), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

