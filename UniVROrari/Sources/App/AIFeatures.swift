import AppIntents
import Foundation
import FoundationModels
import NaturalLanguage
import SwiftUI

// MARK: - Shared helpers for intent data loading
// Reads from the same app group UserDefaults as the widget, so works even when the app is backgrounded.

private let aiAppGroup = "group.it.univr.orari"

private struct IntentPrefs: Codable {
    var selectedCourseID: String?
    var selectedCourseYear: Int
    var selectedAcademicYear: Int?
    var hiddenSubjects: [String]?
}

private struct IntentCacheEntry: Codable {
    let key: String
    let savedAt: Date
    let lessons: [Lesson]
}

private func aiCurrentAcademicYear() -> Int {
    let cal = Calendar(identifier: .gregorian)
    let m = cal.component(.month, from: Date())
    let y = cal.component(.year, from: Date())
    return m >= 8 ? y : y - 1
}

private func aiMondayOf(_ date: Date) -> Date {
    var cal = Calendar(identifier: .gregorian)
    cal.firstWeekday = 2
    let wd = cal.component(.weekday, from: date)
    let delta = wd == 1 ? -6 : 2 - wd
    return cal.date(byAdding: .day, value: delta, to: cal.startOfDay(for: date)) ?? date
}

private func aiLoadLessons(for date: Date) -> [Lesson] {
    guard let defaults = UserDefaults(suiteName: aiAppGroup) else { return [] }
    let decoder = JSONDecoder()
    guard
        let prefData = defaults.data(forKey: "univr.preferences"),
        let prefs = try? decoder.decode(IntentPrefs.self, from: prefData),
        let courseID = prefs.selectedCourseID
    else { return [] }

    let monday = aiMondayOf(date)
    let fmt = DateFormatter()
    fmt.locale = Locale(identifier: "en_US_POSIX")
    fmt.dateFormat = "yyyy-MM-dd"
    fmt.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current
    let weekStr = fmt.string(from: monday)
    let year = prefs.selectedAcademicYear ?? aiCurrentAcademicYear()
    let cacheKey = "lessons:\(courseID):\(prefs.selectedCourseYear):\(year):\(weekStr)"

    guard
        let cacheData = defaults.data(forKey: "univr.cache.lessons"),
        let entries = try? decoder.decode([IntentCacheEntry].self, from: cacheData),
        let entry = entries.first(where: { $0.key == cacheKey })
    else { return [] }

    let cal = Calendar.current
    let hidden = Set(prefs.hiddenSubjects ?? [])
    return entry.lessons
        .filter { cal.isDate($0.date, inSameDayAs: date) && !hidden.contains($0.title) }
        .sorted { $0.startTime < $1.startTime }
}

private func aiMins(_ time: String) -> Int {
    let p = time.split(separator: ":").compactMap { Int($0) }
    return p.count >= 2 ? p[0] * 60 + p[1] : 0
}

// MARK: - Next Lecture Intent

struct NextLectureIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Lecture"
    static var description = IntentDescription("Find out what your next or current lecture is")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let today = aiLoadLessons(for: Date())
        guard !today.isEmpty else {
            return .result(dialog: "No lectures found. Open the app to make sure your schedule is loaded.")
        }

        let cal = Calendar.current
        let now = Date()
        let currentMins = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)

        if let live = today.first(where: {
            aiMins($0.startTime) <= currentMins && currentMins < aiMins($0.endTime)
        }) {
            let room = live.room.isEmpty ? "" : " in \(live.room)"
            let rem = aiMins(live.endTime) - currentMins
            let remStr = rem >= 60 ? "\(rem / 60)h \(rem % 60)m" : "\(rem) min"
            return .result(dialog: "\(live.title)\(room) is in progress — \(remStr) remaining.")
        }

        if let next = today.first(where: { aiMins($0.startTime) > currentMins }) {
            let room = next.room.isEmpty ? "" : " in \(next.room)"
            let wait = aiMins(next.startTime) - currentMins
            let waitStr = wait >= 60 ? "\(wait / 60)h \(wait % 60)m" : "\(wait) min"
            return .result(dialog: "\(next.title) starts at \(next.startTime)\(room) — in \(waitStr).")
        }

        return .result(dialog: "No more lectures today.")
    }
}

// MARK: - Tomorrow Schedule Intent

struct TomorrowScheduleIntent: AppIntent {
    static var title: LocalizedStringResource = "Tomorrow's Schedule"
    static var description = IntentDescription("Get a summary of tomorrow's lectures")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let lessons = aiLoadLessons(for: tomorrow)

        guard !lessons.isEmpty else {
            return .result(dialog: "No lectures tomorrow.")
        }

        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US")
        fmt.dateFormat = "EEEE"
        let dayName = fmt.string(from: tomorrow)

        if lessons.count == 1 {
            let l = lessons[0]
            let room = l.room.isEmpty ? "" : " in \(l.room)"
            return .result(dialog: "On \(dayName) you have one lecture: \(l.title) at \(l.startTime)\(room).")
        }

        let listed = lessons.prefix(3).map { "\($0.title) at \($0.startTime)" }.joined(separator: ", ")
        let tail = lessons.count > 3 ? ", and \(lessons.count - 3) more" : ""
        return .result(dialog: "On \(dayName) you have \(lessons.count) lectures: \(listed)\(tail).")
    }
}

// MARK: - Find Room Intent

struct FindLectureRoomIntent: AppIntent {
    static var title: LocalizedStringResource = "Find Lecture Room"
    static var description = IntentDescription("Find what room a specific lecture is in today")
    static var openAppWhenRun = false

    @Parameter(title: "Subject", requestValueDialog: "Which subject are you looking for?")
    var subject: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let today = aiLoadLessons(for: Date())
        guard !today.isEmpty else {
            return .result(dialog: "No lectures found for today.")
        }

        let query = subject.lowercased()
        let match = today.first { $0.title.lowercased().contains(query) }
            ?? today.first {
                $0.title.lowercased().split(separator: " ").contains { query.contains($0) }
            }

        guard let lesson = match else {
            return .result(dialog: "No lecture matching \"\(subject)\" found today.")
        }

        if lesson.room.isEmpty {
            return .result(dialog: "\(lesson.title) at \(lesson.startTime) has no room assigned.")
        }
        let building = lesson.building.isEmpty ? "" : ", \(lesson.building)"
        return .result(dialog: "\(lesson.title) is in room \(lesson.room)\(building), starting at \(lesson.startTime).")
    }
}

// MARK: - App Shortcuts Provider

struct UniVRAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NextLectureIntent(),
            phrases: [
                "What's my next lecture in \(.applicationName)",
                "Next class in \(.applicationName)",
                "When is my next lesson in \(.applicationName)",
                "Am I in class right now in \(.applicationName)",
                "What lecture do I have now in \(.applicationName)",
            ],
            shortTitle: "Next Lecture",
            systemImageName: "book.fill"
        )
        AppShortcut(
            intent: TomorrowScheduleIntent(),
            phrases: [
                "What classes do I have tomorrow in \(.applicationName)",
                "Tomorrow's schedule in \(.applicationName)",
                "What are my lectures tomorrow in \(.applicationName)",
            ],
            shortTitle: "Tomorrow's Schedule",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: FindLectureRoomIntent(),
            phrases: [
                "Where is my lecture in \(.applicationName)",
                "Find lecture room in \(.applicationName)",
                "What room is my class in \(.applicationName)",
            ],
            shortTitle: "Find Lecture Room",
            systemImageName: "mappin.and.ellipse"
        )
    }
}

// MARK: - Semantic Course Search

struct SemanticCourseSearch {
    private static let embedding = NLEmbedding.wordEmbedding(for: .italian)

    /// Returns courses ranked by semantic similarity to the query.
    /// Requires the query to produce at least one result above a minimum confidence threshold.
    static func rank(query: String, courses: [StudyCourse]) -> [StudyCourse] {
        guard !query.isEmpty else { return courses }
        let qTokens = tokenize(query)
        guard !qTokens.isEmpty else { return courses }

        if let emb = embedding {
            return courses
                .map { ($0, embeddingScore(emb, qTokens: qTokens, course: $0)) }
                .filter { $0.1 > 0.18 }
                .sorted { $0.1 > $1.1 }
                .map(\.0)
        } else {
            return courses
                .map { ($0, overlapScore(qTokens: qTokens, course: $0)) }
                .filter { $0.1 > 0 }
                .sorted { $0.1 > $1.1 }
                .map(\.0)
        }
    }

    private static func embeddingScore(_ emb: NLEmbedding, qTokens: [String], course: StudyCourse) -> Double {
        let cTokens = tokenize(course.name) + tokenize(course.facultyName)
        guard !cTokens.isEmpty else { return 0 }
        var best = 0.0
        for q in qTokens {
            for c in cTokens {
                let sim = 1.0 - emb.distance(between: q, and: c, distanceType: .cosine)
                if sim > best { best = sim }
            }
        }
        return best
    }

    private static func overlapScore(qTokens: [String], course: StudyCourse) -> Double {
        let courseText = (course.name + " " + course.facultyName).lowercased()
        let hits = qTokens.filter { courseText.contains($0) }
        return Double(hits.count) / Double(qTokens.count)
    }

    private static func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.filter { $0.isLetter || $0.isNumber } }
            .filter { $0.count > 2 }
    }
}

// MARK: - AI Weekly Summary Card (requires iOS 26 / Apple Intelligence)

@available(iOS 26.0, *)
struct AISummaryCard: View {
    let weekLessons: [(date: Date, lessons: [Lesson])]

    @State private var summary: String?
    @State private var isGenerating = false
    @State private var generatedForKey = ""

    private var weekKey: String {
        let total = weekLessons.reduce(0) { $0 + $1.lessons.count }
        let anchor = weekLessons.first?.date.timeIntervalSince1970 ?? 0
        return "\(Int(anchor))-\(total)"
    }

    var body: some View {
        Group {
            if !weekLessons.isEmpty {
                cardContent
                    .onAppear { trigger() }
                    .onChange(of: weekKey) { _, _ in trigger() }
            }
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.uiAccent)
                Text("AI SUMMARY")
                    .font(.system(size: 10, weight: .black))
                    .tracking(1.5)
                    .foregroundStyle(Color.uiAccent)
                Spacer()
                if isGenerating {
                    ProgressView()
                        .scaleEffect(0.55)
                        .tint(Color.uiAccent)
                } else if summary != nil {
                    Button {
                        summary = nil
                        generatedForKey = ""
                        trigger()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.uiTextMuted)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let text = summary {
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.uiTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if isGenerating {
                VStack(alignment: .leading, spacing: 6) {
                    skeleton(width: .infinity)
                    skeleton(width: 0.72)
                }
                .transition(.opacity)
            } else {
                Text("Apple Intelligence not available on this device.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.uiTextMuted)
            }
        }
        .padding(14)
        .background(Color.uiSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.uiAccent.opacity(0.14), lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.3), value: summary)
        .animation(.easeOut(duration: 0.3), value: isGenerating)
    }

    @ViewBuilder
    private func skeleton(width: CGFloat) -> some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.uiTextMuted.opacity(0.18))
                .frame(width: width == .infinity ? geo.size.width : geo.size.width * width, height: 10)
        }
        .frame(height: 10)
    }

    private func trigger() {
        let key = weekKey
        guard key != generatedForKey, !isGenerating else { return }
        generatedForKey = key
        summary = nil
        isGenerating = true
        Task {
            summary = await WeeklySummaryService.generate(for: weekLessons)
            isGenerating = false
        }
    }
}

// MARK: - Weekly Summary Service (iOS 26+)

@available(iOS 26.0, *)
enum WeeklySummaryService {
    static func generate(for week: [(date: Date, lessons: [Lesson])]) async -> String? {
        guard SystemLanguageModel.default.isAvailable else { return nil }
        let session = LanguageModelSession()
        do {
            let response = try await session.respond(to: prompt(for: week))
            return response.content
        } catch {
            return nil
        }
    }

    private static func prompt(for week: [(date: Date, lessons: [Lesson])]) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US")
        fmt.dateFormat = "EEEE"

        let total = week.reduce(0) { $0 + $1.lessons.count }
        var lines = ["University timetable — \(total) lectures this week:"]

        for (date, lessons) in week where !lessons.isEmpty {
            let items = lessons.map { "\($0.startTime)–\($0.endTime) \($0.title)" }.joined(separator: "; ")
            lines.append("\(fmt.string(from: date)): \(items)")
        }

        lines.append(
            "\nWrite a 1–2 sentence plain-English summary for a university student. " +
            "Call out the busiest day, any back-to-back lectures, or if it's a light week. " +
            "Be concise and friendly. No bullet points or lists."
        )
        return lines.joined(separator: "\n")
    }
}
