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
    var hiddenSubjects: [String]?
}

// MARK: - Live Activity attributes (must stay in sync with LectureActivityAttributes in AppModel)

struct LectureActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable, Hashable {
            case live, upcoming, idle, allDone
        }
        let phase: Phase
        let lessonTitle: String
        let room: String
        let startTime: String
        let endTime: String
        let startDate: Date
        let endDate: Date
        let isDarkMode: Bool
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

    let hiddenSubjects = Set(prefs.hiddenSubjects ?? [])
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

    let today = entry.lessons.filter { Calendar.current.isDateInToday($0.date) }
    if hiddenSubjects.isEmpty { return today }
    return today.filter { !hiddenSubjects.contains($0.title) }
}

// MARK: - Timeline Entry

struct TimetableEntry: TimelineEntry {
    let date: Date
    fileprivate let nextLesson: WidgetLesson?
    fileprivate let upcomingLessons: [WidgetLesson]
    let isNow: Bool
    let minutesToNext: Int?
}

// MARK: - Provider

struct TimetableProvider: TimelineProvider {
    func placeholder(in context: Context) -> TimetableEntry {
        TimetableEntry(date: Date(), nextLesson: nil, upcomingLessons: [], isNow: false, minutesToNext: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (TimetableEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TimetableEntry>) -> Void) {
        let entry = makeEntry()
        // Refresh at the boundary of the next lesson or every 5 minutes
        var refreshDate = Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date()
        if let next = entry.nextLesson, !entry.isNow {
            let startMins = minutesSinceMidnight(next.startTime)
            let cal = Calendar.current
            let now = Date()
            var comps = cal.dateComponents([.year, .month, .day], from: now)
            comps.hour = startMins / 60
            comps.minute = startMins % 60
            if let lessonStart = cal.date(from: comps), lessonStart > now {
                refreshDate = min(refreshDate, lessonStart)
            }
        }
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }

    private func makeEntry() -> TimetableEntry {
        let lessons = loadTodayLessons()
        let cal = Calendar.current
        let now = Date()
        let currentMins = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        var nextLesson: WidgetLesson?
        var isNow = false
        var minutesToNext: Int?
        for lesson in lessons {
            let start = minutesSinceMidnight(lesson.startTime)
            let end   = minutesSinceMidnight(lesson.endTime)
            if currentMins >= start && currentMins < end {
                nextLesson = lesson; isNow = true; break
            }
            if start > currentMins && nextLesson == nil {
                nextLesson = lesson
                minutesToNext = start - currentMins
            }
        }
        let upcoming = lessons.filter { minutesSinceMidnight($0.endTime) > currentMins }
        return TimetableEntry(date: now, nextLesson: nextLesson, upcomingLessons: upcoming, isNow: isNow, minutesToNext: minutesToNext)
    }
}

// MARK: - Color constants

private let widgetAccent = Color(red: 0.388, green: 0.400, blue: 0.945)   // indigo #6366F1
private let widgetGreen  = Color(red: 0.204, green: 0.831, blue: 0.600)   // green  #34D399

// MARK: - Dynamic Island helper views

private struct PulsingDot: View {
    let color: Color
    @State private var on = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 5, height: 5)
            .opacity(on ? 0.25 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    on = true
                }
            }
    }
}

private struct DIExpandedLeading: View {
    let phase: LectureActivityAttributes.ContentState.Phase
    let accent: Color
    let lessonTitle: String
    let pillLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                if phase == .live {
                    PulsingDot(color: widgetGreen)
                } else if phase == .allDone {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(widgetGreen)
                }
                Text(pillLabel)
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(accent)
                    .tracking(1.0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background(Capsule().fill(accent.opacity(0.14)))

            if phase == .allDone {
                Text("No more lectures")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Text(lessonTitle)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
            }
        }
        .padding(.leading, 2)
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

    // MARK: Small — next/current lecture, ultra-high priority

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(widgetAccent)
                Text("UniVR")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(widgetAccent)
                Spacer()
                Text(shortDate())
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if let lesson = entry.nextLesson {
                // Status badge
                statusBadge(lesson: lesson)
                    .padding(.bottom, 4)

                Text(lesson.title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                if !lesson.room.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "mappin")
                            .font(.system(size: 8))
                        Text(lesson.room)
                            .font(.system(size: 9))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                }
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(widgetGreen)
                    .padding(.bottom, 2)
                Text("All done")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("No more lectures")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    @ViewBuilder
    private func statusBadge(lesson: WidgetLesson) -> some View {
        if entry.isNow {
            HStack(spacing: 4) {
                Circle()
                    .fill(widgetGreen)
                    .frame(width: 6, height: 6)
                Text("NOW")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(widgetGreen)
            }
        } else if let mins = entry.minutesToNext {
            Text(mins < 60 ? "IN \(mins)m" : lesson.startTime)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(widgetAccent)
        } else {
            Text(lesson.startTime)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(widgetAccent)
        }
    }

    // MARK: Medium — today's schedule at a glance

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(widgetAccent)
                Text("Today")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(widgetAccent)
                Spacer()
                Text(shortDate())
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            if entry.upcomingLessons.isEmpty {
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(widgetGreen)
                    Text("No more lectures today")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                Spacer(minLength: 6)
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(entry.upcomingLessons.prefix(3)) { lesson in
                        mediumRow(lesson: lesson)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    @ViewBuilder
    private func mediumRow(lesson: WidgetLesson) -> some View {
        let isActive = entry.isNow && entry.nextLesson?.id == lesson.id
        HStack(spacing: 8) {
            // Active indicator or time
            if isActive {
                Circle()
                    .fill(widgetGreen)
                    .frame(width: 6, height: 6)
                    .padding(.leading, 1)
            }
            Text(lesson.startTime)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(isActive ? widgetGreen : widgetAccent)
                .frame(width: 36, alignment: .leading)
            Text(lesson.title)
                .font(.system(size: 11, weight: isActive ? .bold : .semibold))
                .foregroundStyle(isActive ? Color.primary : Color.primary.opacity(0.85))
                .lineLimit(1)
            Spacer()
            if !lesson.room.isEmpty {
                Text(lesson.room)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Accessory Circular

    private var circularView: some View {
        ZStack {
            if let lesson = entry.nextLesson {
                VStack(spacing: 1) {
                    if entry.isNow {
                        Circle()
                            .fill(widgetGreen)
                            .frame(width: 5, height: 5)
                    } else {
                        Text(lesson.startTime)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(widgetAccent)
                    }
                    Text(lesson.title)
                        .font(.system(size: 8, weight: .medium))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            } else {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(widgetGreen)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    // MARK: Accessory Rectangular

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let lesson = entry.nextLesson {
                HStack(spacing: 5) {
                    if entry.isNow {
                        Circle()
                            .fill(widgetGreen)
                            .frame(width: 5, height: 5)
                        Text("In progress")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(widgetGreen)
                    } else {
                        Text(entry.minutesToNext.map { $0 < 60 ? "In \($0)m" : "Next" } ?? "Next")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(widgetAccent)
                    }
                }
                Text(lesson.title)
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(1)
                Text("\(lesson.startTime)–\(lesson.endTime)\(lesson.room.isEmpty ? "" : " · \(lesson.room)")")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(widgetGreen)
                    .font(.system(size: 12))
                Text("No more lectures")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func shortDate() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "EEE d MMM"
        return f.string(from: Date())
    }
}

// MARK: - Live Activity Lock Screen View

private struct LectureLockScreenView: View {
    let context: ActivityViewContext<LectureActivityAttributes>
    @State private var pulsing = false

    private var isDark: Bool { context.state.isDarkMode }
    private var phase: LectureActivityAttributes.ContentState.Phase { context.state.phase }
    private var accent: Color { phase == .live || phase == .allDone ? widgetGreen : widgetAccent }

    // MARK: Adaptive colors — use @Environment(\.colorScheme) directly;
    // works correctly because we don't set activityBackgroundTint (which would lock the rendering context to dark)

    private var primaryText: Color {
        isDark ? .white : Color(red: 0.07, green: 0.07, blue: 0.09)
    }
    private var secondaryText: Color {
        isDark ? .white.opacity(0.50) : Color(red: 0.07, green: 0.07, blue: 0.09).opacity(0.55)
    }
    private var mutedText: Color {
        isDark ? .white.opacity(0.32) : Color(red: 0.07, green: 0.07, blue: 0.09).opacity(0.32)
    }
    private var trackColor: Color {
        isDark ? .white.opacity(0.09) : .black.opacity(0.08)
    }
    private var glowOpacity: Double { isDark ? 0.18 : 0.09 }
    private var circleRingOpacity: Double { isDark ? 0.14 : 0.20 }
    private var moonOpacity: Double { isDark ? 0.45 : 0.65 }

    private var bgColor: Color {
        let isGreen = phase == .live || phase == .allDone
        if isDark {
            return isGreen
                ? Color(red: 0.02, green: 0.07, blue: 0.05)
                : Color(red: 0.04, green: 0.04, blue: 0.11)
        } else {
            return isGreen
                ? Color(red: 0.92, green: 0.98, blue: 0.95)
                : Color(red: 0.95, green: 0.95, blue: 0.99)
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            bgColor
                .ignoresSafeArea()

            RadialGradient(
                colors: [accent.opacity(glowOpacity), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 130
            )

            if phase == .allDone {
                allDoneLayout
            } else {
                normalLayout
            }
        }
        .activitySystemActionForegroundColor(primaryText)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
    }

    // MARK: All Done layout

    private var allDoneLayout: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(widgetGreen.opacity(circleRingOpacity))
                    .frame(width: 46, height: 46)
                Image(systemName: "checkmark")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(widgetGreen)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("All wrapped up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(primaryText)
                Text("No more lectures today")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(secondaryText)
            }

            Spacer()

            Image(systemName: "moon.stars.fill")
                .font(.system(size: 22))
                .foregroundStyle(widgetGreen.opacity(moonOpacity))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    // MARK: Normal layout (live / upcoming / idle)

    private var pillLabel: String {
        switch phase {
        case .live:     return "IN PROGRESS"
        case .upcoming: return "STARTING SOON"
        case .idle:     return "NEXT · \(context.state.startTime)"
        case .allDone:  return ""
        }
    }

    private var timerLabel: String {
        switch phase {
        case .live:            return "remaining"
        case .upcoming, .idle: return "to start"
        case .allDone:         return ""
        }
    }

    private var timerTarget: Date {
        phase == .live ? context.state.endDate : context.state.startDate
    }

    private var normalLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 5) {
                        if phase == .live {
                            Circle()
                                .fill(accent)
                                .frame(width: 5, height: 5)
                                .opacity(pulsing ? 0.25 : 1.0)
                        }
                        Text(pillLabel)
                            .font(.system(size: 8, weight: .black))
                            .foregroundStyle(accent)
                            .tracking(1.0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(Capsule().fill(accent.opacity(0.13)))

                    Text(context.state.lessonTitle)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(primaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if !context.state.room.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.fill")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(accent.opacity(0.8))
                            Text(context.state.room)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(secondaryText)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(timerInterval: Date()...timerTarget, countsDown: true)
                        .font(.system(size: 26, weight: .black))
                        .foregroundStyle(accent)
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(minWidth: 78, alignment: .trailing)
                    Text(timerLabel)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(mutedText)
                        .tracking(0.6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, phase == .live ? 10 : 14)

            if phase == .live {
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(trackColor)
                        .frame(height: 4)
                    ProgressView(
                        timerInterval: context.state.startDate...context.state.endDate,
                        countsDown: false
                    ) { EmptyView() } currentValueLabel: { EmptyView() }
                    .progressViewStyle(.linear)
                    .tint(widgetGreen)
                    .clipShape(Capsule())
                }
                .frame(height: 4)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
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
            let phase = context.state.phase
            let accent: Color = (phase == .live || phase == .allDone) ? widgetGreen : widgetAccent
            let timerTarget = phase == .live ? context.state.endDate : context.state.startDate
            let timerLabel: String = phase == .live ? "remaining" : "to start"

            let pillLabel: String = {
                switch phase {
                case .live:     return "IN PROGRESS"
                case .upcoming: return "STARTING SOON"
                case .idle:     return "NEXT · \(context.state.startTime)"
                case .allDone:  return "ALL DONE"
                }
            }()

            return DynamicIsland {
                // Expanded — leading
                DynamicIslandExpandedRegion(.leading) {
                    DIExpandedLeading(
                        phase: phase,
                        accent: accent,
                        lessonTitle: context.state.lessonTitle,
                        pillLabel: pillLabel
                    )
                }

                // Expanded — trailing
                DynamicIslandExpandedRegion(.trailing) {
                    if phase == .allDone {
                        Image(systemName: "moon.stars.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(widgetGreen.opacity(0.55))
                            .symbolEffect(.pulse, options: .repeating)
                            .padding(.trailing, 2)
                    } else {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(timerInterval: Date()...timerTarget, countsDown: true)
                                .font(.system(size: 22, weight: .black))
                                .foregroundStyle(accent)
                                .monospacedDigit()
                                .contentTransition(.numericText(countsDown: true))
                                .multilineTextAlignment(.trailing)
                                .frame(minWidth: 68, alignment: .trailing)
                            Text(timerLabel)
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.32))
                                .tracking(0.5)
                        }
                        .padding(.trailing, 2)
                    }
                }

                // Expanded — bottom
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        Rectangle()
                            .fill(.white.opacity(0.07))
                            .frame(height: 0.5)

                        if phase == .allDone {
                            HStack(spacing: 5) {
                                Text("See you tomorrow")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.36))
                                Spacer()
                                Image(systemName: "sparkles")
                                    .font(.system(size: 10))
                                    .foregroundStyle(widgetGreen.opacity(0.5))
                            }
                        } else {
                            VStack(spacing: 7) {
                                HStack(spacing: 6) {
                                    if !context.state.room.isEmpty {
                                        HStack(spacing: 4) {
                                            Image(systemName: "mappin.fill")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundStyle(accent)
                                            Text(context.state.room)
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundStyle(.white.opacity(0.82))
                                        }
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(Capsule().fill(.white.opacity(0.07)))
                                    }
                                    Spacer()
                                    Text("\(context.state.startTime) – \(context.state.endTime)")
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.30))
                                }

                                if phase == .live {
                                    ZStack(alignment: .leading) {
                                        Capsule()
                                            .fill(.white.opacity(0.08))
                                            .frame(height: 3)
                                        ProgressView(
                                            timerInterval: context.state.startDate...context.state.endDate,
                                            countsDown: false
                                        ) { EmptyView() } currentValueLabel: { EmptyView() }
                                        .progressViewStyle(.linear)
                                        .tint(widgetGreen)
                                        .clipShape(Capsule())
                                    }
                                    .frame(height: 3)
                                }
                            }
                        }
                    }
                    .padding(.top, 2)
                    .padding(.horizontal, 2)
                }
            } compactLeading: {
                switch phase {
                case .live:
                    Image(systemName: "waveform")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(widgetGreen)
                        .symbolEffect(.variableColor.iterative.reversing, options: .repeating)
                case .upcoming:
                    Image(systemName: "hourglass.tophalf.filled")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(widgetAccent)
                        .symbolEffect(.pulse, options: .repeating)
                case .idle:
                    Image(systemName: "timer")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(widgetAccent)
                case .allDone:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(widgetGreen)
                        .symbolEffect(.bounce, options: .nonRepeating)
                }
            } compactTrailing: {
                if phase == .allDone {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(widgetGreen.opacity(0.65))
                } else {
                    Text(timerInterval: Date()...timerTarget, countsDown: true)
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(accent)
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                        .frame(maxWidth: 54)
                }
            } minimal: {
                switch phase {
                case .live:
                    ZStack {
                        ProgressView(
                            timerInterval: context.state.startDate...context.state.endDate,
                            countsDown: false
                        ) { EmptyView() } currentValueLabel: { EmptyView() }
                        .progressViewStyle(.circular)
                        .tint(widgetGreen)
                        .scaleEffect(1.05)
                        Image(systemName: "waveform")
                            .font(.system(size: 6, weight: .bold))
                            .foregroundStyle(widgetGreen)
                            .symbolEffect(.variableColor.iterative.reversing, options: .repeating)
                    }
                case .allDone:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(widgetGreen)
                case .upcoming:
                    Image(systemName: "hourglass.tophalf.filled")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(widgetAccent)
                        .symbolEffect(.pulse, options: .repeating)
                case .idle:
                    Image(systemName: "timer")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(widgetAccent)
                }
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
