import SwiftUI
import UIKit

struct BreathingLightView: View {
    let targetRounds: Int
    let onComplete: () -> Void

    @State private var engine: BreathingSequenceEngine

    init(targetRounds: Int = 3, onComplete: @escaping () -> Void) {
        self.targetRounds = max(1, targetRounds)
        self.onComplete = onComplete
        _engine = State(initialValue: BreathingSequenceEngine(targetRounds: max(1, targetRounds)))
    }

    var body: some View {
        VStack(spacing: BetterSpacing.xLarge) {
            Spacer(minLength: 16)

            breathingOrb

            VStack(spacing: BetterSpacing.small) {
                HStack(spacing: BetterSpacing.xSmall) {
                    ForEach(0..<targetRounds, id: \.self) { round in
                        Capsule()
                            .fill(round < engine.completedRounds ? engine.currentStep.color : Color.white.opacity(0.12))
                            .frame(width: round == engine.completedRounds ? 34 : 22, height: 6)
                            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: engine.completedRounds)
                    }
                }
                Text("Round \(min(engine.completedRounds + 1, targetRounds)) of \(targetRounds)")
                    .font(BetterTypography.footnote)
                    .foregroundStyle(BetterColors.subtext)
            }

            Spacer(minLength: 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: targetRounds) { await runSequence() }
    }

    private var breathingOrb: some View {
        ZStack {
            Circle()
                .fill(engine.currentStep.color.opacity(0.15))
                .frame(width: 286, height: 286)
                .blur(radius: 30)

            Circle()
                .stroke(engine.currentStep.color.opacity(0.18), lineWidth: 18)
                .frame(width: 222, height: 222)
                .scaleEffect(engine.currentStep.ringScale)
                .animation(.easeInOut(duration: Double(engine.currentStep.seconds)), value: engine.phaseID)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.95),
                            engine.currentStep.color.opacity(0.92),
                            engine.currentStep.color.opacity(0.52)
                        ],
                        center: .center,
                        startRadius: 4,
                        endRadius: 100
                    )
                )
                .frame(width: 154, height: 154)
                .scaleEffect(engine.currentStep.orbScale)
                .shadow(color: engine.currentStep.color.opacity(0.46), radius: 34)
                .animation(.easeInOut(duration: Double(engine.currentStep.seconds)), value: engine.phaseID)

            VStack(spacing: BetterSpacing.xSmall) {
                Text(engine.currentStep.title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(BetterColors.text)
                    .frame(height: 34)
                Text("\(engine.secondsRemaining)")
                    .font(.system(size: 58, weight: .bold, design: .rounded))
                    .foregroundStyle(BetterColors.text)
                    .monospacedDigit()
                    .frame(width: 96, height: 68)
                Text("3-4-7")
                    .font(BetterTypography.caption)
                    .foregroundStyle(engine.currentStep.color)
            }
        }
        .frame(width: 320, height: 320)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(engine.currentStep.title), \(engine.secondsRemaining) seconds remaining")
    }

    private func runSequence() async {
        while !Task.isCancelled && !engine.isComplete {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            if engine.tick() {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            }
        }
        if !Task.isCancelled {
            onComplete()
        }
    }
}

struct BreathingSequenceEngine {
    private(set) var stepIndex = 0
    private(set) var secondsRemaining: Int
    private(set) var completedRounds = 0
    let targetRounds: Int

    init(targetRounds: Int) {
        self.targetRounds = max(1, targetRounds)
        self.secondsRemaining = Self.steps[0].seconds
    }

    var currentStep: BreathingStep {
        Self.steps[stepIndex]
    }

    var phaseID: Int {
        completedRounds * Self.steps.count + stepIndex
    }

    var isComplete: Bool {
        completedRounds >= targetRounds
    }

    @discardableResult
    mutating func tick() -> Bool {
        if secondsRemaining > 1 {
            secondsRemaining -= 1
            return false
        }

        advanceStep()
        return true
    }

    private mutating func advanceStep() {
        if stepIndex == Self.steps.count - 1 {
            stepIndex = 0
            completedRounds += 1
        } else {
            stepIndex += 1
        }
        secondsRemaining = Self.steps[stepIndex].seconds
    }

    private static let steps: [BreathingStep] = [
        BreathingStep(title: "Inhale", seconds: 3, orbScale: 1.24, ringScale: 1.04, color: Color(red: 0.18, green: 0.78, blue: 0.72)),
        BreathingStep(title: "Hold", seconds: 4, orbScale: 1.12, ringScale: 1.12, color: Color(red: 1.0, green: 0.67, blue: 0.24)),
        BreathingStep(title: "Exhale", seconds: 7, orbScale: 0.72, ringScale: 0.88, color: Color(red: 0.30, green: 0.52, blue: 1.0))
    ]
}

struct BreathingStep {
    let title: String
    let seconds: Int
    let orbScale: CGFloat
    let ringScale: CGFloat
    let color: Color
}

#if DEBUG
#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        BreathingLightView(targetRounds: 4) {}
    }
}
#endif
