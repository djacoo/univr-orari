import Foundation

enum DateHelpers {
    static let italianCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "it_IT")
        calendar.firstWeekday = 2
        return calendar
    }()

    static let dayMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.dateFormat = "EEEE d MMMM"
        return formatter
    }()

    static let weekdayShortFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.dateFormat = "EEE d"
        return formatter
    }()

    static let apiDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current
        return formatter
    }()

    static func monday(for date: Date) -> Date {
        let weekday = italianCalendar.component(.weekday, from: date)
        let delta = weekday == 1 ? -6 : (2 - weekday)
        return italianCalendar.date(byAdding: .day, value: delta, to: startOfDay(for: date)) ?? date
    }

    static func startOfDay(for date: Date) -> Date {
        italianCalendar.startOfDay(for: date)
    }

    static func addWeeks(_ offset: Int, to date: Date) -> Date {
        italianCalendar.date(byAdding: .day, value: 7 * offset, to: date) ?? date
    }

    static func currentAcademicYear(referenceDate: Date = Date()) -> Int {
        let month = italianCalendar.component(.month, from: referenceDate)
        let year = italianCalendar.component(.year, from: referenceDate)
        return month >= 8 ? year : (year - 1)
    }
}
