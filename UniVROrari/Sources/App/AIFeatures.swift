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

// MARK: - AI Daily Brief Card (iOS 26+)

@available(iOS 26.0, *)
struct AIDailyBriefCard: View {
    let lessons: [Lesson]
    let now: Date

    @State private var brief: String?
    @State private var isGenerating = false
    @State private var generatedForKey = ""

    private var briefKey: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        let ids = lessons.map { $0.id }.sorted().joined(separator: ",")
        return "\(fmt.string(from: now)):\(ids)"
    }

    var body: some View {
        cardContent
            .onAppear { trigger() }
            .onChange(of: briefKey) { _, _ in trigger() }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.uiAccent)
                Text("DAILY BRIEF")
                    .font(.system(size: 10, weight: .black))
                    .tracking(1.5)
                    .foregroundStyle(Color.uiAccent)
                Spacer()
                if isGenerating {
                    ProgressView()
                        .scaleEffect(0.55)
                        .tint(Color.uiAccent)
                } else if brief != nil {
                    Button {
                        brief = nil
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

            if let text = brief {
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.uiTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if isGenerating {
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.uiTextMuted.opacity(0.18))
                        .frame(width: geo.size.width * 0.8, height: 10)
                }
                .frame(height: 10)
                .transition(.opacity)
            }
        }
        .padding(14)
        .background(Color.uiSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.uiAccent.opacity(0.14), lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.3), value: brief)
        .animation(.easeOut(duration: 0.3), value: isGenerating)
    }

    private func trigger() {
        let key = briefKey
        guard key != generatedForKey, !isGenerating else { return }
        generatedForKey = key
        brief = nil
        isGenerating = true
        Task {
            brief = await DailyBriefService.generate(lessons: lessons, now: now)
            isGenerating = false
        }
    }
}

// MARK: - Daily Brief Service (iOS 26+)

@available(iOS 26.0, *)
enum DailyBriefService {
    static func generate(lessons: [Lesson], now: Date) async -> String? {
        guard SystemLanguageModel.default.isAvailable else { return nil }
        let session = LanguageModelSession()
        do {
            let response = try await session.respond(to: prompt(lessons: lessons, now: now))
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } catch {
            return nil
        }
    }

    private static func prompt(lessons: [Lesson], now: Date) -> String {
        let cal = Calendar.current
        let nowMins = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)

        let timeFmt = DateFormatter()
        timeFmt.locale = Locale(identifier: "en_US")
        timeFmt.dateFormat = "HH:mm"

        let dayFmt = DateFormatter()
        dayFmt.locale = Locale(identifier: "en_US")
        dayFmt.dateFormat = "EEEE"

        let done = lessons.filter { $0.endTime.minutesSinceMidnight <= nowMins }
        let active = lessons.first {
            $0.startTime.minutesSinceMidnight <= nowMins && nowMins < $0.endTime.minutesSinceMidnight
        }

        var lines = [
            "Current time: \(timeFmt.string(from: now)) (\(dayFmt.string(from: now))).",
            "EXACT schedule for today (do not change or invent any names, times, or rooms):"
        ]
        for l in lessons {
            var entry = "- [\(l.startTime)–\(l.endTime)] \(l.title)"
            if !l.room.isEmpty { entry += ", room \(l.room)" }
            if !l.professor.isEmpty { entry += ", \(l.professor)" }
            let status: String
            if done.contains(where: { $0.id == l.id }) {
                status = "DONE"
            } else if active?.id == l.id {
                status = "IN PROGRESS"
            } else {
                status = "UPCOMING"
            }
            entry += " (\(status))"
            lines.append(entry)
        }
        lines.append(
            "\nTask: Write exactly 1 short, friendly sentence summarising the day from the student's current perspective." +
            " Use ONLY the data listed above — do not invent, rename, or add any lectures, times, rooms, or people." +
            " No bullet points, no quotes."
        )
        return lines.joined(separator: "\n")
    }
}

// MARK: - AI Schedule Assistant Sheet (iOS 26+)

@available(iOS 26.0, *)
struct AIScheduleAssistantSheet: View {
    let todayLessons: [Lesson]
    let weekLessons: [(date: Date, lessons: [Lesson])]

    struct Message: Identifiable {
        let id = UUID()
        let role: Role
        let text: String
        enum Role { case user, assistant }
    }

    @State private var session = LanguageModelSession()
    @State private var messages: [Message] = []
    @State private var inputText = ""
    @State private var isResponding = false
    @FocusState private var inputFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                messageList
                inputBar
            }
            .navigationTitle("Schedule Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.subheadline.weight(.semibold))
                        .tint(Color.uiAccent)
                }
            }
        }
        .onAppear { inputFocused = true }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if messages.isEmpty {
                        emptyState.padding(.top, 40)
                    }
                    ForEach(messages) { msg in
                        messageBubble(msg).id(msg.id)
                    }
                    if isResponding {
                        typingIndicator.id("typing")
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(16)
            }
            .onChange(of: messages.count) { _, _ in
                withAnimation { proxy.scrollTo("bottom") }
            }
            .onChange(of: isResponding) { _, new in
                if new { withAnimation { proxy.scrollTo("bottom") } }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 32))
                .foregroundStyle(Color.uiAccent)
            Text("Ask about your schedule")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.uiTextPrimary)
            Text("Try: \"Any back-to-back lectures?\" or \"What's my busiest day this week?\"")
                .font(.system(size: 13))
                .foregroundStyle(Color.uiTextMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func messageBubble(_ msg: Message) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            if msg.role == .user { Spacer(minLength: 48) }
            Group {
                if msg.role == .assistant,
                   let attributed = try? AttributedString(
                    markdown: msg.text,
                    options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                   ) {
                    Text(attributed)
                } else {
                    Text(msg.text)
                }
            }
            .font(.system(size: 14))
            .foregroundStyle(msg.role == .user ? Color.white : Color.uiTextPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                msg.role == .user
                    ? AnyShapeStyle(uiAccentGradient)
                    : AnyShapeStyle(Color.uiSurface)
            )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .frame(maxWidth: .infinity, alignment: msg.role == .user ? .trailing : .leading)
            if msg.role == .assistant { Spacer(minLength: 48) }
        }
    }

    private var typingIndicator: some View {
        HStack {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(Color.uiTextMuted.opacity(0.6)).frame(width: 7, height: 7)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.uiSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Spacer()
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask about your schedule…", text: $inputText, axis: .vertical)
                .font(.system(size: 15))
                .foregroundStyle(Color.uiTextPrimary)
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.uiSurfaceInput, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .focused($inputFocused)
                .onSubmit { sendMessage() }

            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(
                        inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isResponding
                            ? Color.uiTextMuted : Color.uiAccent
                    )
            }
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isResponding)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.uiSurface)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.uiStroke).frame(height: 0.5)
        }
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 0) }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isResponding else { return }
        inputText = ""
        messages.append(Message(role: .user, text: text))
        isResponding = true

        let isFirst = messages.count == 1
        let payload = isFirst ? buildContextualPrompt(userMessage: text) : text

        Task {
            do {
                let response = try await session.respond(to: payload)
                let reply = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                messages.append(Message(role: .assistant, text: reply.isEmpty ? "I'm not sure. Try rephrasing." : reply))
            } catch {
                messages.append(Message(role: .assistant, text: "Sorry, couldn't process that. Please try again."))
            }
            isResponding = false
        }
    }

    private func buildContextualPrompt(userMessage: String) -> String {
        let dateFmt = DateFormatter()
        dateFmt.locale = Locale(identifier: "en_US")
        dateFmt.dateFormat = "EEEE d MMMM"

        let nowFmt = DateFormatter()
        nowFmt.locale = Locale(identifier: "en_US")
        nowFmt.dateFormat = "EEEE d MMMM 'at' HH:mm"

        let today = Calendar.current.startOfDay(for: Date())

        var lines = [
            "SYSTEM: You are a university timetable assistant.",
            "Today is \(nowFmt.string(from: Date())).",
            "RULE: Only reference lecture titles, times, rooms, and professors that appear verbatim in the schedule below.",
            "RULE: You may reason about dates (e.g. 'tomorrow', 'Monday') using the current date and the schedule.",
            "RULE: Do not invent or rename any lecture, time, room, or professor.",
            "",
            "=== THIS WEEK'S SCHEDULE ==="
        ]
        for (date, lessons) in weekLessons where !lessons.isEmpty {
            let isToday = Calendar.current.isDate(date, inSameDayAs: today)
            let isTomorrow = Calendar.current.isDate(date, inSameDayAs: Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today)
            var dayLabel = dateFmt.string(from: date)
            if isToday { dayLabel += " (TODAY)" }
            else if isTomorrow { dayLabel += " (TOMORROW)" }
            lines.append("\(dayLabel):")
            for l in lessons {
                var entry = "  \(l.startTime)–\(l.endTime)  \(l.title)"
                if !l.room.isEmpty { entry += "  |  Room: \(l.room)" }
                if !l.professor.isEmpty { entry += "  |  \(l.professor)" }
                lines.append(entry)
            }
        }
        lines.append("")
        lines.append("=== STUDENT QUESTION ===")
        lines.append(userMessage)
        return lines.joined(separator: "\n")
    }
}

// MARK: - AI Notification Service (iOS 26+)

@available(iOS 26.0, *)
enum AINotificationService {
    static func generateBody(lesson: Lesson, precedingLesson: Lesson?) async -> String {
        guard SystemLanguageModel.default.isAvailable else { return fallback(lesson: lesson) }
        let session = LanguageModelSession()
        do {
            let response = try await session.respond(to: prompt(lesson: lesson, precedingLesson: precedingLesson))
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? fallback(lesson: lesson) : text
        } catch {
            return fallback(lesson: lesson)
        }
    }

    private static func prompt(lesson: Lesson, precedingLesson: Lesson?) -> String {
        let durationMins = lesson.endTime.minutesSinceMidnight - lesson.startTime.minutesSinceMidnight
        var lines = [
            "Write a 1-sentence notification body for a student about to attend a lecture.",
            "Use ONLY the facts listed below. Do not invent anything not provided.",
            "",
            "Lecture: \(lesson.title)",
            "Time: \(lesson.startTime)–\(lesson.endTime) (\(durationMins) minutes)"
        ]
        if !lesson.room.isEmpty { lines.append("Room: \(lesson.room)") }
        if !lesson.professor.isEmpty { lines.append("Professor: \(lesson.professor)") }
        if let prev = precedingLesson {
            let gap = lesson.startTime.minutesSinceMidnight - prev.endTime.minutesSinceMidnight
            if gap <= 5 {
                lines.append("Note: immediately follows \(prev.title)")
            } else if gap <= 20 {
                lines.append("Note: \(gap)-minute gap after \(prev.title)")
            }
        }
        lines.append("\nOutput: one sentence only, no quotes, no bullet points.")
        return lines.joined(separator: "\n")
    }

    private static func fallback(lesson: Lesson) -> String {
        [lesson.startTime, lesson.room, lesson.professor]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}
