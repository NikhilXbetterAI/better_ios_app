import SwiftUI

struct ConnectedDevicesView: View {
    let sources: [SleepSource]

    var body: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            Text("Connected Sources")
                .font(BetterTypography.headline)
                .foregroundStyle(BetterColors.text)

            if sources.isEmpty {
                Text("Sources appear after recent sleep samples are readable from Apple Health.")
                    .font(BetterTypography.footnote)
                    .foregroundStyle(BetterColors.subtext)
            } else {
                ForEach(sources) { source in
                    HStack(spacing: BetterSpacing.medium) {
                        Image(systemName: source.name.localizedCaseInsensitiveContains("watch") ? "applewatch" : "heart.text.square.fill")
                            .foregroundStyle(BetterColors.brand)
                            .frame(width: 34, height: 34)
                            .background(BetterColors.brand.opacity(0.18))
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.name)
                                .font(BetterTypography.footnote)
                                .foregroundStyle(BetterColors.text)
                            Text(source.productType ?? source.bundleIdentifier ?? "Connected")
                                .font(BetterTypography.caption)
                                .foregroundStyle(BetterColors.subtext)
                        }
                        Spacer()
                    }
                }
            }
        }
        .padding(BetterSpacing.large)
        .background(BetterColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

