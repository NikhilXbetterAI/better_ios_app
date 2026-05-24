import SwiftUI

/// Shown at launch when `AppEnvironment.live()` fails — typically a SwiftData
/// migration error on a partly-corrupted store. Replaces the prior
/// `fatalError(...)` so users can recover the install without reinstalling.
struct BootRecoveryView: View {
    let error: Error
    let onResetLocalData: () -> Void

    @State private var didConfirmReset = false

    var body: some View {
        ZStack {
            BetterColors.background.ignoresSafeArea()
            VStack(spacing: BetterSpacing.large) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(.orange)

                Text("Couldn't open Better")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(BetterColors.text)
                    .multilineTextAlignment(.center)

                Text("Better's local database couldn't be opened. This usually happens after an interrupted update. You can reset Better's local data to recover — your Apple Health data is not affected.")
                    .font(.callout)
                    .foregroundStyle(BetterColors.text.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Text(error.localizedDescription)
                    .font(.caption.monospaced())
                    .foregroundStyle(BetterColors.text.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .lineLimit(4)

                if didConfirmReset {
                    Button(role: .destructive) {
                        onResetLocalData()
                    } label: {
                        Text("Reset Local Data")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .padding(.horizontal)
                } else {
                    Button {
                        didConfirmReset = true
                    } label: {
                        Text("Reset Local Data…")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.bordered)
                    .padding(.horizontal)
                }
            }
            .padding()
        }
    }
}
