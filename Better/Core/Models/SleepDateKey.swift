import Foundation

enum SleepDateKey {
    static func calendarDateKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    static func sleepDateKey(forSessionStart startDate: Date, calendar: Calendar = .current) -> String {
        var effectiveDate = startDate
        if calendar.component(.hour, from: startDate) >= 12 {
            effectiveDate = calendar.date(byAdding: .day, value: 1, to: startDate) ?? startDate
        }
        return calendarDateKey(for: effectiveDate, calendar: calendar)
    }

    static func today(calendar: Calendar = .current, now: Date = Date()) -> String {
        calendarDateKey(for: now, calendar: calendar)
    }

    static func date(from key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
