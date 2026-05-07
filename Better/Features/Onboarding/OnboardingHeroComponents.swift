import SwiftUI

// MARK: - Page Dots Indicator

struct PageDotsIndicator: View {
    let count: Int
    let activeIndex: Int
    var activeColor: Color = BetterColors.brand

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == activeIndex ? activeColor : BetterColors.subtext.opacity(0.30))
                    .frame(width: i == activeIndex ? 22 : 6, height: 6)
                    .animation(.spring(response: 0.35, dampingFraction: 0.75), value: activeIndex)
            }
        }
    }
}

// MARK: - Activity Rings Hero

struct ActivityRingsHero: View {
    struct Ring {
        let color: Color
        let targetTrim: Double
        let lineWidth: CGFloat
        let diameter: CGFloat
    }

    let rings: [Ring]
    @State private var animatedTrims: [Double] = []

    var body: some View {
        ZStack {
            ForEach(Array(rings.enumerated()), id: \.offset) { index, ring in
                Circle()
                    .stroke(ring.color.opacity(0.12), lineWidth: ring.lineWidth)
                    .frame(width: ring.diameter, height: ring.diameter)

                Circle()
                    .trim(from: 0, to: index < animatedTrims.count ? animatedTrims[index] : 0)
                    .stroke(
                        AngularGradient(
                            colors: [ring.color, ring.color.opacity(0.55)],
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        ),
                        style: StrokeStyle(lineWidth: ring.lineWidth, lineCap: .round)
                    )
                    .frame(width: ring.diameter, height: ring.diameter)
                    .rotationEffect(.degrees(-90))
            }
        }
        .onAppear {
            animatedTrims = Array(repeating: 0, count: rings.count)
            for (i, ring) in rings.enumerated() {
                withAnimation(
                    .spring(response: 1.0, dampingFraction: 0.7)
                    .delay(Double(i) * 0.18)
                ) {
                    animatedTrims[i] = ring.targetTrim
                }
            }
        }
    }

    static let healthRings: [Ring] = [
        Ring(color: BetterColors.stageDeep, targetTrim: 0.75, lineWidth: 22, diameter: 200),
        Ring(color: BetterColors.heartRate,  targetTrim: 0.55, lineWidth: 22, diameter: 148),
        Ring(color: BetterColors.hrv,        targetTrim: 0.65, lineWidth: 22, diameter: 96),
    ]
}

// MARK: - Sleep Arc View

struct SleepArcView: View {
    let value: Double
    let range: ClosedRange<Double>

    private var fraction: Double {
        min(max((value - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
    }

    private var arcColor: Color {
        value >= 7 && value <= 9 ? BetterColors.success : BetterColors.warning
    }

    var body: some View {
        ZStack {
            // Track arc
            Circle()
                .trim(from: 0.15, to: 0.85)
                .stroke(BetterColors.card, lineWidth: 20)
                .frame(width: 180, height: 180)
                .rotationEffect(.degrees(90))

            // Filled arc
            Circle()
                .trim(from: 0.15, to: max(0.151, 0.15 + fraction * 0.70))
                .stroke(
                    AngularGradient(
                        colors: [arcColor.opacity(0.7), arcColor],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: 20, lineCap: .round)
                )
                .frame(width: 180, height: 180)
                .rotationEffect(.degrees(90))
                .animation(.spring(response: 0.4, dampingFraction: 0.72), value: value)

            // Center label
            VStack(spacing: 2) {
                Text(String(format: "%.1f", value))
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(arcColor)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: value)

                Text("hours")
                    .font(BetterTypography.footnote)
                    .foregroundStyle(BetterColors.subtext)
            }
        }
    }
}
