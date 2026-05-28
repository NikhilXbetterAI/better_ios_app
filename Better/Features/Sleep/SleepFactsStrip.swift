import SwiftUI

/// Compact hero summary: Total sleep · Bedtime · Wake.
/// Bedtime and wake can flip to minutes-vs-usual deltas when baseline data is ready
/// (≥ dashboardMinimumValidNights). An arrow icon hints the interaction is available.
struct SleepFactsStrip: View {
    let session: SleepSession
    let baseline: SleepBaseline?

    @State private var flippedClock: Set<Clock> = []

    enum Clock: Hashable { case bed, wake }

    /// True when baseline has enough nights for a meaningful delta comparison.
    private var baselineReady: Bool {
        (baseline?.validNights ?? 0) >= BaselineEngine.dashboardMinimumValidNights
    }

    // MARK: - Body

    var body: some View {
        clockRow
    }

    // MARK: - Total Sleep · Bedtime · Wake row

    private var clockRow: some View {
        HStack(spacing: BetterSpacing.small) {
            totalCell
            clockCell(.bed)
            clockCell(.wake)
        }
    }

    @ViewBuilder
    private func clockCell(_ clock: Clock) -> some View {
        let isFlipped = flippedClock.contains(clock)
        let canFlip = clockBaselineMinute(clock) != nil
        let tint = clock == .bed ? BetterColors.brandLight : BetterColors.warning

        Button {
            guard canFlip else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                if isFlipped { flippedClock.remove(clock) } else { flippedClock.insert(clock) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: clock == .bed ? "moon.zzz.fill" : "sunrise.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 22, height: 22)
                        .background(tint.opacity(0.12), in: Circle())
                    Text(clock == .bed ? "Bedtime" : "Wake")
                        .font(BetterTypography.micro.bold())
                        .foregroundStyle(BetterColors.subtext)
                        .tracking(0.5)
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    // Affordance: shows when baseline is ready, hinting the cell is tappable
                    if canFlip {
                        Image(systemName: isFlipped ? "clock.fill" : "arrow.left.arrow.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(tint.opacity(isFlipped ? 0.9 : 0.45))
                            .animation(.easeInOut(duration: 0.2), value: isFlipped)
                    }
                }
                Text(isFlipped ? clockDeltaText(clock) : clockTimeText(clock))
                    .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(clockTextColor(clock, flipped: isFlipped))
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, BetterSpacing.medium)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.black)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(BetterColors.glassStroke, lineWidth: 1)
            )
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(tint.opacity(isFlipped ? 0.95 : 0.45))
                    .frame(height: 3)
                    .padding(.horizontal, 16)
                    .offset(y: -1)
            }
        }
        .buttonStyle(.plain)
        .opacity(canFlip || !isFlipped ? 1 : 0.7)
    }

    private var totalCell: some View {
        let mins = Int(session.totalSleepTime / 60)
        let text = mins >= 60 ? "\(mins / 60)h \(mins % 60)m" : "\(mins)m"
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "bed.double.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(BetterColors.brandLight)
                    .frame(width: 22, height: 22)
                    .background(BetterColors.brandLight.opacity(0.12), in: Circle())
                Text("Total")
                    .font(BetterTypography.micro.bold())
                    .foregroundStyle(BetterColors.subtext)
                    .tracking(0.5)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            Text(text)
                .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(BetterColors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, BetterSpacing.medium)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [BetterColors.brand.opacity(0.50), Color.white.opacity(0.04)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .overlay(alignment: .bottom) {
            Capsule()
                .fill(BetterColors.brand)
                .frame(height: 3)
                .padding(.horizontal, 16)
                .offset(y: -1)
        }
    }

    private func clockTimeText(_ clock: Clock) -> String {
        clockDate(clock).formatted(date: .omitted, time: .shortened)
    }

    private func clockDate(_ clock: Clock) -> Date {
        switch clock {
        case .bed:  return session.inBedStartDate ?? session.startDate
        case .wake: return session.displayWakeDate
        }
    }

    private func clockBaselineMinute(_ clock: Clock) -> Double? {
        // Guard: require ≥ dashboardMinimumValidNights so the delta is
        // based on a real sample, not a single-night "baseline".
        guard let baseline, baselineReady else { return nil }
        switch clock {
        case .bed:  return baseline.bedtimeMinuteAverage
        case .wake: return baseline.wakeMinuteAverage
        }
    }

    private func signedClockDiffMinutes(_ clock: Clock) -> Double? {
        guard let baselineMin = clockBaselineMinute(clock) else { return nil }
        let comps = Calendar.current.dateComponents([.hour, .minute], from: clockDate(clock))
        let actual = Double((comps.hour ?? 0) * 60 + (comps.minute ?? 0))
        var diff = actual - baselineMin
        diff = diff.truncatingRemainder(dividingBy: 1440)
        if diff > 720 { diff -= 1440 }
        if diff < -720 { diff += 1440 }
        return diff
    }

    private func clockDeltaText(_ clock: Clock) -> String {
        guard let diff = signedClockDiffMinutes(clock) else { return "—" }
        let rounded = Int(diff.rounded())
        if abs(rounded) < 1 { return "On time" }
        let direction = rounded < 0 ? "earlier" : "later"
        return "\(abs(rounded))m \(direction)"
    }

    private func clockTextColor(_ clock: Clock, flipped: Bool) -> Color {
        guard flipped, let diff = signedClockDiffMinutes(clock) else { return BetterColors.text }
        return abs(diff) <= 10 ? BetterColors.text : BetterColors.subtext
    }
}
