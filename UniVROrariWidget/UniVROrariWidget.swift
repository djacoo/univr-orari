import WidgetKit
import SwiftUI

private let appGroupSuite = "group.it.univr.orari"

// MARK: - Lightweight mirror types (must stay in sync with main app Codable models)

fileprivate struct WidgetLesson: Codable, Identifiable {
    let id: String
    let title: String
    let professor: String
    let room: String
    let building: String
    let date: Date
    let startTime: String
    let endTime: String
}

fileprivate struct WidgetLessonsCacheEntry: Codable {
    let key: String
    let savedAt: Date
    let lessons: [WidgetLesson]
}

fileprivate struct WidgetPreferences: Codable {
    var selectedCourseID: String?
    var selectedCourseYear: Int
    var selectedAcademicYear: Int?
}

// MARK: - Helpers

private func italianMonday(for date: Date) -> Date {
    var cal = Calendar(identifier: .gregorian)
    cal.firstWeekday = 2
    let weekday = cal.component(.weekday, from: date)
    let delta = weekday == 1 ? -6 : (2 - weekday)
    return cal.date(byAdding: .day, value: delta, to: cal.startOfDay(for: date)) ?? date
}

private func currentAcademicYear() -> Int {
    var cal = Calendar(identifier: .gregorian)
    cal.locale = Locale(identifier: "it_IT")
    let month = cal.component(.month, from: Date())
    let year  = cal.component(.year, from: Date())
    return month >= 8 ? year : (year - 1)
}

private func minutesSinceMidnight(_ time: String) -> Int {
    let parts = time.split(separator: ":").compactMap { Int($0) }
    guard parts.count >= 2 else { return 0 }
    return parts[0] * 60 + parts[1]
}

private func loadTodayLessons() -> [WidgetLesson] {
    guard let defaults = UserDefaults(suiteName: appGroupSuite) else { return [] }
    let decoder = JSONDecoder()

    guard
        let prefData = defaults.data(forKey: "univr.preferences"),
        let prefs = try? decoder.decode(WidgetPreferences.self, from: prefData),
        let courseID = prefs.selectedCourseID
    else { return [] }

    let academicYear = prefs.selectedAcademicYear ?? currentAcademicYear()
    let weekStart = italianMonday(for: Date())
    let fmt = DateFormatter()
    fmt.locale = Locale(identifier: "en_US_POSIX")
    fmt.dateFormat = "yyyy-MM-dd"
    fmt.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current
    let weekStartStr = fmt.string(from: weekStart)
    let key = "lessons:\(courseID):\(prefs.selectedCourseYear):\(academicYear):\(weekStartStr)"

    guard
        let cacheData = defaults.data(forKey: "univr.cache.lessons"),
        let entries = try? decoder.decode([WidgetLessonsCacheEntry].self, from: cacheData),
        let entry = entries.first(where: { $0.key == key })
    else { return [] }

    return entry.lessons.filter { Calendar.current.isDateInToday($0.date) }
}

// MARK: - Timeline Entry

struct TimetableEntry: TimelineEntry {
    let date: Date
    fileprivate let nextLesson: WidgetLesson?
    fileprivate let upcomingLessons: [WidgetLesson]
    let isNow: Bool
}

// MARK: - Provider

struct TimetableProvider: TimelineProvider {
    func placeholder(in context: Context) -> TimetableEntry {
        TimetableEntry(date: Date(), nextLesson: nil, upcomingLessons: [], isNow: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (TimetableEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TimetableEntry>) -> Void) {
        let entry = makeEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func makeEntry() -> TimetableEntry {
        let lessons = loadTodayLessons()
        let cal = Calendar.current
        let now = Date()
        let currentMins = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        var nextLesson: WidgetLesson?
        var isNow = false
        for lesson in lessons {
            let start = minutesSinceMidnight(lesson.startTime)
            let end   = minutesSinceMidnight(lesson.endTime)
            if currentMins >= start && currentMins < end {
                nextLesson = lesson; isNow = true; break
            }
            if start > currentMins && nextLesson == nil {
                nextLesson = lesson
            }
        }
        let upcoming = lessons.filter { minutesSinceMidnight($0.endTime) > currentMins }
        return TimetableEntry(date: now, nextLesson: nextLesson, upcomingLessons: upcoming, isNow: isNow)
    }
}

// MARK: - Views

struct TimetableWidgetEntryView: View {
    var entry: TimetableEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall:             smallView
        case .systemMedium:            mediumView
        case .accessoryCircular:       circularView
        case .accessoryRectangular:    rectangularView
        default:                       smallView
        }
    }

    private var accentColor: Color { Color(red: 0.776, green: 0.365, blue: 0.239) }
    private var sageColor:   Color { Color(red: 0.247, green: 0.427, blue: 0.365) }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Today", systemImage: "calendar")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(accentColor)

            Spacer()

            if let lesson = entry.nextLesson {
                Text(entry.isNow ? "Now" : lesson.startTime)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(accentColor)
                Text(lesson.title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if !lesson.room.isEmpty {
                    Text(lesson.room)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No more lectures today")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Label("Today's schedule", systemImage: "calendar")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(accentColor)
                Spacer()
                Text(shortDate(from: Date()))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            if entry.upcomingLessons.isEmpty {
                Spacer()
                Text("No more lectures today")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(entry.upcomingLessons.prefix(3)) { lesson in
                    HStack(spacing: 8) {
                        Text(lesson.startTime)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(accentColor)
                            .frame(width: 38, alignment: .leading)
                        Text(lesson.title)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                        Spacer()
                        if !lesson.room.isEmpty {
                            Text(lesson.room)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var circularView: some View {
        ZStack {
            if let lesson = entry.nextLesson {
                VStack(spacing: 2) {
                    Text(lesson.startTime)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(accentColor)
                    Text(lesson.title)
                        .font(.system(size: 8, weight: .medium))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            } else {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.title3)
                    .foregroundStyle(sageColor)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let lesson = entry.nextLesson {
                Text(entry.isNow ? "In progress" : "Next lecture")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(accentColor)
                Text(lesson.title)
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(1)
                Text("\(lesson.startTime)\(lesson.room.isEmpty ? "" : " · \(lesson.room)")")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                Text("No lectures today")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func shortDate(from date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "EEE d MMM"
        return f.string(from: date)
    }
}

// MARK: - Widget

@main
struct UniVROrariWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "UniVROrariWidget", provider: TimetableProvider()) { entry in
            TimetableWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("UniVR Timetable")
        .description("Today's lecture schedule at a glance.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
        ])
    }
}
