import SwiftUI
import UIKit

struct SleepBlackoutView: View {
    let dimsScreen: Bool
    let onExit: () -> Void

    @State private var isPressing = false
    @State private var exitProgress: CGFloat = 0
    @State private var originalBrightness = UIScreen.main.brightness
    @State private var controlsRevealed = false
    @State private var revealTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: BetterSpacing.medium) {
                Spacer()

                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 7)
                        .frame(width: 78, height: 78)
                    Circle()
                        .trim(from: 0, to: exitProgress)
                        .stroke(Color.white.opacity(0.8), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .frame(width: 78, height: 78)
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.46))
                }

                Text("Hold to exit")
                    .font(BetterTypography.caption)
                    .foregroundStyle(Color.white.opacity(0.45))

                if !controlsRevealed && !isPressing {
                    Text("Tap to reveal · Hold 2s to exit")
                        .font(BetterTypography.micro)
                        .foregroundStyle(Color.white.opacity(0.28))
                }

                Spacer()
            }
            .opacity(isPressing || exitProgress > 0 || controlsRevealed ? 1 : 0.55)
        }
        .onTapGesture {
            revealTask?.cancel()
            withAnimation(.easeIn(duration: 0.15)) { controlsRevealed = true }
            revealTask = Task {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.4)) { controlsRevealed = false }
                }
            }
        }
        .onLongPressGesture(
            minimumDuration: 2.0,
            pressing: { pressing in
                isPressing = pressing
                withAnimation(pressing ? .linear(duration: 2.0) : .easeOut(duration: 0.2)) {
                    exitProgress = pressing ? 1 : 0
                }
            },
            perform: onExit
        )
        .onAppear {
            originalBrightness = UIScreen.main.brightness
            if dimsScreen {
                UIScreen.main.brightness = min(originalBrightness, 0.08)
            }
        }
        .onDisappear {
            UIScreen.main.brightness = originalBrightness
        }
    }
}
