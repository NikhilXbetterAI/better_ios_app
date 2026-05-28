import SwiftUI

struct InsightsWeekdayWeekendCard: View {
    let weekdayAvgHours: Double?
    let weekendAvgHours: Double?
    let weekdayCount: Int
    let weekendCount: Int

    @State private var appeared = false
    @State private var hasAnimated = false
    @State private var showInfo = false

    private var maxHours: Double {
        max(weekdayAvgHours ?? 0, weekendAvgHours ?? 0, 5.0)
    }

    private var difference: Double? {
        guard let wd = weekdayAvgHours, let we = weekendAvgHours else { return nil }
        return we - wd
    }

    // MARK: - Computed insight

    /// Short contextual note shown inline on the card
    private var inlineInsight: (text: String, icon: String, color: Color)? {
        guard let diff = difference else { return nil }
        let absMin = Int(abs(diff * 60).rounded())
        if diff >= 1.0 {
            return (
                "Social jet lag detected — you're sleeping \(absMin) min longer on weekends, which can shift your internal clock by Monday.",
                "exclamationmark.circle.fill",
                BetterColors.warning
            )
        } else if diff >= 0.25 {
            return (
                "You sleep \(absMin) more minutes on weekends — a small weekend catch-up that usually has little impact.",
                "moon.fill",
                BetterColors.success
            )
        } else if diff <= -0.25 {
            return (
                "You sleep \(absMin) fewer minutes on weekends than weekdays — check that weekends aren't cutting sleep short.",
                "moon",
                BetterColors.warning
            )
        } else {
            return (
                "Consistent sleep duration across weekdays and weekends — great for circadian stability.",
                "checkmark.circle.fill",
                BetterColors.success
            )
        }
    }

    var body: some View {
        BetterHealthCard {
            VStack(alignment: .leading, spacing: BetterSpacing.medium) {
                header
                barsSection
                if let insight = inlineInsight {
                    inlineInsightBanner(insight)
                }
            }
        }
        .onAppear {
            guard !hasAnimated else { return }
            hasAnimated = true
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.1)) {
                appeared = true
            }
        }
        .sheet(isPresented: $showInfo) {
            WeekdayWeekendInfoSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.dark)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: BetterSpacing.small) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(BetterColors.activity, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("Weekday vs Weekend")
                    .font(BetterTypography.subheadline)
                    .foregroundStyle(BetterColors.text)
                Text("Average sleep duration comparison")
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.subtext)
            }

            Spacer()

            // Info button
            Button {
                showInfo = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(BetterColors.subtext)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Bars

    private var barsSection: some View {
        VStack(spacing: BetterSpacing.medium) {
            sleepBar(
                label: "Weekday",
                hours: weekdayAvgHours,
                count: weekdayCount,
                color: BetterColors.brand
            )
            sleepBar(
                label: "Weekend",
                hours: weekendAvgHours,
                count: weekendCount,
                color: BetterColors.success
            )
        }
    }

    private func sleepBar(label: String, hours: Double?, count: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(BetterColors.text)

                Spacer()

                if let h = hours {
                    Text(formatHours(h))
                        .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(color)
                } else {
                    Text("No data")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(BetterColors.subtext)
                }

                Text("(\(count)n)")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(BetterColors.subtext)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(BetterColors.cardSecondary).frame(height: 10)
                    if let h = hours {
                        let fraction = min(h / maxHours, 1.0)
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [color, color.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(
                                width: max(10, geo.size.width * CGFloat(appeared ? fraction : 0)),
                                height: 10
                            )
                            .animation(.spring(response: 0.75, dampingFraction: 0.78).delay(0.1), value: appeared)
                    }
                }
            }
            .frame(height: 10)
        }
    }

    // MARK: - Inline Insight Banner

    private func inlineInsightBanner(_ insight: (text: String, icon: String, color: Color)) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: insight.icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(insight.color)
                .padding(.top, 1)

            Text(insight.text)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(BetterColors.subtext)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, BetterSpacing.medium)
        .padding(.vertical, BetterSpacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(insight.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(insight.color.opacity(0.18), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private func formatHours(_ hours: Double) -> String {
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        return "\(h)h \(m)m"
    }
}

// MARK: - Info Sheet

private struct WeekdayWeekendInfoSheet: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // Header
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(BetterColors.activity, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Weekday vs Weekend")
                                .font(BetterTypography.title)
                                .foregroundStyle(BetterColors.text)
                            Text("What this tells you about your sleep rhythm")
                                .font(BetterTypography.caption)
                                .foregroundStyle(BetterColors.subtext)
                        }
                    }
                }

                Divider().background(BetterColors.border)

                // What it measures
                infoSection(
                    icon: "ruler",
                    iconColor: BetterColors.brand,
                    title: "What it measures",
                    body: "This compares your average total sleep on weekdays (Mon–Fri) vs weekends (Sat–Sun). Even a 30-minute consistent difference points to a mismatch between your schedule and your body clock."
                )

                // Social jet lag
                infoSection(
                    icon: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                    iconColor: BetterColors.warning,
                    title: "Social jet lag",
                    body: "When you sleep significantly longer on weekends (≥1 hour), your body clock shifts later — similar to flying west. Come Monday, you're waking up at a time that feels like 3–4 AM to your internal clock. Over time, this is linked to fatigue, mood dips, and reduced metabolic health."
                )

                // Good range
                infoSection(
                    icon: "checkmark.seal.fill",
                    iconColor: BetterColors.success,
                    title: "Healthy range",
                    body: "A difference of less than 30 minutes is considered low social jet lag. Aim for a consistent wake time every day — even on weekends — and your circadian rhythm will thank you."
                )

                // Tip
                infoSection(
                    icon: "lightbulb.fill",
                    iconColor: BetterColors.brandLight,
                    title: "Quick tip",
                    body: "If you're a \"weekend recovery sleeper,\" try shifting your weekday bedtime 15 minutes earlier each week rather than sleeping in on weekends. This preserves sleep quantity without disrupting your clock."
                )
            }
            .padding(BetterSpacing.large)
        }
        .background(BetterColors.background)
    }

    private func infoSection(icon: String, iconColor: Color, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 32, height: 32)
                .background(iconColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(BetterTypography.subheadline)
                    .foregroundStyle(BetterColors.text)
                Text(body)
                    .font(BetterTypography.footnote)
                    .foregroundStyle(BetterColors.subtext)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
            }
        }
    }
}
