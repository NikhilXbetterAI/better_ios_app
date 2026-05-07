import SwiftUI

struct ResearchModeStepView: View {
    @Binding var isResearchMode: Bool

    @State private var lineProgress: CGFloat = 0
    @State private var lockRotation: Double = 0

    var body: some View {
        GeometryReader { geometry in
            let screenHeight = geometry.size.height

            VStack(spacing: 0) {
                // ── Hero ──────────────────────────────────────────────────────
                heroArea
                    .frame(height: screenHeight * 0.36)

                // ── Text ──────────────────────────────────────────────────────
                VStack(spacing: BetterSpacing.small) {
                    Text("Research mode")
                        .font(BetterTypography.display)
                        .foregroundStyle(BetterColors.text)
                        .multilineTextAlignment(.center)

                    Text("Unlocks CSV export and deeper protocol impact views. Opt-in — you can change it later.")
                        .font(BetterTypography.body)
                        .foregroundStyle(BetterColors.subtext)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, BetterSpacing.screen)
                .padding(.top, BetterSpacing.large)

                // ── Toggle card ───────────────────────────────────────────────
                BetterHealthCard {
                    VStack(alignment: .leading, spacing: BetterSpacing.large) {
                        Toggle(isOn: $isResearchMode) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Enable research mode")
                                    .font(BetterTypography.subheadline)
                                    .foregroundStyle(BetterColors.text)
                                Text("Show export tools and protocol analytics for structured sleep experiments.")
                                    .font(BetterTypography.footnote)
                                    .foregroundStyle(BetterColors.subtext)
                            }
                        }
                        .tint(BetterColors.hrv)

                        Divider().overlay(BetterColors.border)

                        OnboardingValueRow(
                            icon: "square.and.arrow.up",
                            title: "Export on demand",
                            description: "Data stays local unless you explicitly export it."
                        )
                        OnboardingValueRow(
                            icon: "chart.bar.xaxis",
                            title: "Protocol context",
                            description: "Compare adherent and non-adherent nights."
                        )
                    }
                }
                .padding(.horizontal, BetterSpacing.screen)
                .padding(.top, BetterSpacing.xLarge)

                Spacer(minLength: 0)
                Color.clear.frame(height: 120)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .onAppear { startAnimations() }
        .onChange(of: isResearchMode) { _, newValue in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) {
                lockRotation = newValue ? -25 : 0
            }
        }
    }

    // MARK: - Hero

    private var heroArea: some View {
        ZStack {
            // Lock icon (open/closed based on toggle state)
            Image(systemName: isResearchMode ? "lock.open.fill" : "lock.fill")
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(BetterColors.hrv)
                .opacity(0.28)
                .rotationEffect(.degrees(lockRotation))
                .animation(.spring(response: 0.4, dampingFraction: 0.55), value: isResearchMode)
                .offset(y: -44)

            // Canvas chart
            Canvas { context, size in
                let h = size.height
                let w = size.width * lineProgress

                // Protocol line — solid teal, trending up
                let protocolPoints: [CGPoint] = [
                    CGPoint(x: 0,        y: h * 0.70),
                    CGPoint(x: w * 0.25, y: h * 0.52),
                    CGPoint(x: w * 0.50, y: h * 0.36),
                    CGPoint(x: w * 0.75, y: h * 0.28),
                    CGPoint(x: w,        y: h * 0.18),
                ]
                var protocolPath = Path()
                if let first = protocolPoints.first {
                    protocolPath.move(to: first)
                    protocolPoints.dropFirst().forEach { protocolPath.addLine(to: $0) }
                }
                context.stroke(protocolPath, with: .color(BetterColors.hrv), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                // Baseline line — dashed subtext, flat
                let basePoints: [CGPoint] = [
                    CGPoint(x: 0,        y: h * 0.78),
                    CGPoint(x: w * 0.25, y: h * 0.74),
                    CGPoint(x: w * 0.50, y: h * 0.72),
                    CGPoint(x: w * 0.75, y: h * 0.76),
                    CGPoint(x: w,        y: h * 0.70),
                ]
                var basePath = Path()
                if let first = basePoints.first {
                    basePath.move(to: first)
                    basePoints.dropFirst().forEach { basePath.addLine(to: $0) }
                }
                context.stroke(basePath, with: .color(BetterColors.subtext.opacity(0.45)), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [6, 4]))

                // Legend dots
                if w > 10 {
                    context.fill(Path(ellipseIn: CGRect(x: w - 5, y: h * 0.18 - 5, width: 10, height: 10)), with: .color(BetterColors.hrv))
                    context.fill(Path(ellipseIn: CGRect(x: w - 5, y: h * 0.70 - 5, width: 10, height: 10)), with: .color(BetterColors.subtext.opacity(0.5)))
                }
            }
            .frame(width: 240, height: 110)
            .offset(y: 30)
        }
    }

    private func startAnimations() {
        withAnimation(.easeInOut(duration: 1.4).delay(0.2)) {
            lineProgress = 1.0
        }
        lockRotation = isResearchMode ? -25 : 0
    }
}
