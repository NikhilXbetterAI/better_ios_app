import Foundation

nonisolated enum SleepDateKey {
    // Sleep-date keys must be Gregorian regardless of the user's preferred calendar
    // (e.g. Buddhist on th_TH would otherwise yield year 2569 instead of 2026).
    private static func gregorian(matching calendar: Calendar) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = calendar.timeZone
        return c
    }

    static func calendarDateKey(for date: Date, calendar: Calendar = .current) -> String {
        let cal = gregorian(matching: calendar)
        let components = cal.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    static func sleepDateKey(forSessionStart startDate: Date, calendar: Calendar = .current) -> String {
        let cal = gregorian(matching: calendar)
        var effectiveDate = startDate
        if cal.component(.hour, from: startDate) >= 12 {
            effectiveDate = cal.date(byAdding: .day, value: 1, to: startDate) ?? startDate
        }
        return calendarDateKey(for: effectiveDate, calendar: cal)
    }

    static func today(calendar: Calendar = .current, now: Date = Date()) -> String {
        calendarDateKey(for: now, calendar: calendar)
    }

    static func date(from key: String, calendar: Calendar = .current) -> Date? {
        let cal = gregorian(matching: calendar)
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return cal.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
