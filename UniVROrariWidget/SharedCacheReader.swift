import Foundation

enum SharedCacheReader {
    private static let appGroupSuite = "group.it.univr.orari"

    struct CachedLesson: Codable, Identifiable {
        let id: String
        let title: String
        let professor: String
        let room: String
        let building: String
        let date: Date
        let startTime: String
        let endTime: String
    }

    private struct CachePreferences: Codable {
        var selectedCourseID: String?
        var selectedCourseYear: Int
        var selectedAcademicYear: Int?
        var hiddenSubjects: [String]?
    }

    private struct CacheEntry: Codable {
        let key: String
        let savedAt: Date
        let lessons: [CachedLesson]
    }

    static func lessons(for date: Date) -> [CachedLesson] {
        guard let defaults = UserDefaults(suiteName: appGroupSuite) else { return [] }
        let decoder = JSONDecoder()
        guard
            let prefData = defaults.data(forKey: "univr.preferences"),
            let prefs = try? decoder.decode(CachePreferences.self, from: prefData),
            let courseID = prefs.selectedCourseID
        else { return [] }

        let monday = italianMonday(for: date)
        let weekStr = apiDateString(from: monday)
        let year = prefs.selectedAcademicYear ?? currentAcademicYear()
        let cacheKey = "lessons:\(courseID):\(prefs.selectedCourseYear):\(year):\(weekStr)"

        guard
            let cacheData = defaults.data(forKey: "univr.cache.lessons"),
            let entries = try? decoder.decode([CacheEntry].self, from: cacheData),
            let entry = entries.first(where: { $0.key == cacheKey })
        else { return [] }

        let cal = Calendar.current
        let hidden = Set(prefs.hiddenSubjects ?? [])
        return entry.lessons
            .filter { cal.isDate($0.date, inSameDayAs: date) && !hidden.contains($0.title) }
            .sorted { $0.startTime < $1.startTime }
    }

    private static func italianMonday(for date: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        let weekday = cal.component(.weekday, from: date)
        let delta = weekday == 1 ? -6 : (2 - weekday)
        return cal.date(byAdding: .day, value: delta, to: cal.startOfDay(for: date)) ?? date
    }

    private static func currentAcademicYear() -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "it_IT")
        let month = cal.component(.month, from: Date())
        let year = cal.component(.year, from: Date())
        return month >= 8 ? year : (year - 1)
    }

    private static let _apiDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current
        return f
    }()

    private static func apiDateString(from date: Date) -> String {
        _apiDateFormatter.string(from: date)
    }
}
