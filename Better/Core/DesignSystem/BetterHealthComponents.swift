import SwiftUI

struct BetterHealthCard<Content: View>: View {
    var cornerRadius: CGFloat = 24
    var padding: CGFloat = BetterSpacing.large
    var isNested: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isNested ? AnyShapeStyle(BetterColors.cardSecondary) : AnyShapeStyle(BetterColors.cardGradient))
                    .shadow(color: isNested ? .clear : Color.black.opacity(0.48), radius: isNested ? 0 : 24, x: 0, y: isNested ? 0 : 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(isNested ? AnyShapeStyle(BetterColors.border.opacity(0.4)) : AnyShapeStyle(BetterColors.glassStroke), lineWidth: 1.2)
            )
    }
}

struct BetterSectionHeader: View {
    let title: String
    var subtitle: String?
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(BetterTypography.title)
                    .foregroundStyle(BetterColors.text)
                if let subtitle {
                    Text(subtitle)
                        .font(BetterTypography.footnote)
                        .foregroundStyle(BetterColors.subtext)
                }
            }
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.subtext)
            }
        }
    }
}

struct MetricGaugeView: View {
    let progress: Double
    let color: Color
    var lineWidth: CGFloat = 8

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.10), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(
                    AngularGradient(
                        colors: [color, color.opacity(0.5)],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 44, height: 44)
    }
}

struct SparklineView: View {
    let values: [Double]
    let color: Color
    var fill: Bool = true

    var body: some View {
        GeometryReader { proxy in
            let points = normalizedPoints(in: proxy.size)
            ZStack(alignment: .bottomLeading) {
                if fill, points.count > 1 {
                    sparklinePath(points: points)
                        .appending(bottomClosure(for: points, height: proxy.size.height))
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.35), color.opacity(0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                sparklinePath(points: points)
                    .stroke(color, style: StrokeStyle(lineWidth: 2.8, lineCap: .round, lineJoin: .round))
                if let last = points.last {
                    Circle()
                        .fill(color)
                        .frame(width: 10, height: 10)
                        .shadow(color: color.opacity(0.65), radius: 8)
                        .position(last)
                }
            }
        }
        .frame(height: 64)
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 1
        let span = max(maxValue - minValue, 0.001)
        return values.enumerated().map { index, value in
            let x = CGFloat(index) / CGFloat(values.count - 1) * size.width
            let y = size.height - CGFloat((value - minValue) / span) * (size.height - 10) - 5
            return CGPoint(x: x, y: y)
        }
    }

    private func sparklinePath(points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
        }
    }

    private func bottomClosure(for points: [CGPoint], height: CGFloat) -> Path {
        Path { path in
            guard let first = points.first, let last = points.last else { return }
            path.move(to: last)
            path.addLine(to: CGPoint(x: last.x, y: height))
            path.addLine(to: CGPoint(x: first.x, y: height))
            path.closeSubpath()
        }
    }
}

private extension Path {
    func appending(_ other: Path) -> Path {
        var copy = self
        copy.addPath(other)
        return copy
    }
}

struct RangeBandView: View {
    let value: Double?
    let bounds: ClosedRange<Double>
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                HStack(spacing: 3) {
                    BetterColors.danger.opacity(0.28)
                    BetterColors.warning.opacity(0.32)
                    BetterColors.success.opacity(0.30)
                    BetterColors.cyan.opacity(0.28)
                }
                .clipShape(Capsule())

                if let value {
                    let percent = min(max((value - bounds.lowerBound) / (bounds.upperBound - bounds.lowerBound), 0), 1)
                    Circle()
                        .fill(color)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().stroke(BetterColors.text.opacity(0.85), lineWidth: 2))
                        .shadow(color: color.opacity(0.7), radius: 8)
                        .offset(x: max(0, min(proxy.size.width - 18, proxy.size.width * percent - 9)))
                }
            }
        }
        .frame(height: 18)
    }
}

struct FloatingActionButton: View {
    let systemImageName: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImageName)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(BetterColors.text)
                .frame(width: 58, height: 58)
                .background(.ultraThinMaterial, in: Circle())
                .background(BetterColors.cardSecondary.opacity(0.6), in: Circle())
                .overlay(
                    Circle().stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.18), Color.white.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                )
                .shadow(color: .black.opacity(0.36), radius: 16, x: 0, y: 8)
        }
        .buttonStyle(.plain)
    }
}
