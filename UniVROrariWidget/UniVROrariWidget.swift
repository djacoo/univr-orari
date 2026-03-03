import WidgetKit
import SwiftUI
import ActivityKit

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

// MARK: - Live Activity attributes (must stay in sync with LectureActivityAttributes in AppModel)

struct LectureActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let lessonTitle: String
        let room: String
        let endTime: String
        let endDate: Date
    }
    let courseName: String
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

// MARK: - Timetable Widget Views

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

// MARK: - Live Activity Lock Screen View

private struct LectureLockScreenView: View {
    let context: ActivityViewContext<LectureActivityAttributes>
    private var accentColor: Color { Color(red: 0.776, green: 0.365, blue: 0.239) }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(accentColor)

            VStack(alignment: .leading, spacing: 3) {
                Text(context.state.lessonTitle)
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if !context.state.room.isEmpty {
                        Label(context.state.room, systemImage: "mappin")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Text("Until \(context.state.endTime)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(timerInterval: Date()...context.state.endDate, countsDown: true)
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundStyle(accentColor)
                .multilineTextAlignment(.trailing)
                .frame(minWidth: 60, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .activityBackgroundTint(.black.opacity(0.55))
        .activitySystemActionForegroundColor(.white)
    }
}

// MARK: - Timetable Widget

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

// MARK: - Live Activity Widget

struct UniVROrariLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LectureActivityAttributes.self) { context in
            LectureLockScreenView(context: context)
        } dynamicIsland: { context in
            let accent = Color(red: 0.776, green: 0.365, blue: 0.239)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.lessonTitle, systemImage: "books.vertical.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: Date()...context.state.endDate, countsDown: true)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(accent)
                        .multilineTextAlignment(.trailing)
                        .frame(minWidth: 54, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        if !context.state.room.isEmpty {
                            Label(context.state.room, systemImage: "mappin")
                        }
                        Spacer()
                        Text("Until \(context.state.endTime)")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "books.vertical.fill")
                    .foregroundStyle(accent)
                    .font(.system(size: 12, weight: .semibold))
            } compactTrailing: {
                Text(timerInterval: Date()...context.state.endDate, countsDown: true)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(accent)
                    .frame(maxWidth: 56)
            } minimal: {
                Image(systemName: "books.vertical.fill")
                    .foregroundStyle(accent)
            }
            .widgetURL(URL(string: "univr://timetable"))
        }
    }
}

// MARK: - Widget Bundle

@main
struct UniVROrariWidgets: WidgetBundle {
    var body: some Widget {
        UniVROrariWidget()
        UniVROrariLiveActivity()
    }
}
