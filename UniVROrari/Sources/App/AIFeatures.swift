import AppIntents
import Foundation
import FoundationModels
import NaturalLanguage
import SwiftUI

private func aiLoadLessons(for date: Date) -> [SharedCacheReader.CachedLesson] {
    SharedCacheReader.lessons(for: date)
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
            $0.startTime.minutesSinceMidnight <= currentMins && currentMins < $0.endTime.minutesSinceMidnight
        }) {
            let room = live.room.isEmpty ? "" : " in \(live.room)"
            let rem = live.endTime.minutesSinceMidnight - currentMins
            let remStr = rem >= 60 ? "\(rem / 60)h \(rem % 60)m" : "\(rem) min"
            return .result(dialog: "\(live.title)\(room) is in progress — \(remStr) remaining.")
        }

        if let next = today.first(where: { $0.startTime.minutesSinceMidnight > currentMins }) {
            let room = next.room.isEmpty ? "" : " in \(next.room)"
            let wait = next.startTime.minutesSinceMidnight - currentMins
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
        let dayFmt = DateFormatter()
        dayFmt.locale = Locale(identifier: "en_US")
        dayFmt.dateFormat = "EEE"

        let now = Date()
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)

        func describe(_ l: Lesson) -> String {
            var s = "\(l.title) (\(l.startTime)–\(l.endTime)"
            if !l.room.isEmpty { s += ", \(l.room)" }
            s += ")"
            return s
        }

        var pastDays: [String] = []
        var todayLine: String? = nil
        var futureDays: [String] = []

        for (date, lessons) in week where !lessons.isEmpty {
            let name = dayFmt.string(from: date)
            let items = lessons.map { describe($0) }.joined(separator: ", ")
            let line = "\(name): \(items)"
            if cal.isDate(date, inSameDayAs: today) {
                todayLine = line
            } else if date < today {
                pastDays.append(line)
            } else {
                futureDays.append(line)
            }
        }

        var lines = ["This week's lecture schedule. Use only what is listed — do not invent anything."]
        if !pastDays.isEmpty {
            lines.append("ALREADY PAST:")
            pastDays.forEach { lines.append("  \($0)") }
        }
        if let t = todayLine {
            lines.append("TODAY (\(dayFmt.string(from: now))):")
            lines.append("  \(t)")
        }
        if !futureDays.isEmpty {
            lines.append("STILL AHEAD:")
            futureDays.forEach { lines.append("  \($0)") }
        }

        lines.append("""

The schedule above has been computed by the app and is exact. Do not alter, reinterpret, or contradict it.

Rewrite it as 1–2 natural sentences addressed to the student (use "you"). Include subject names, days, and times. Describe the shape of the week — what's already behind them and what's still to come. Do not add anything not listed above.
""")
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
        let cal = Calendar.current
        let block = cal.component(.hour, from: now)  // refreshes every hour
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        let ids = lessons.map { $0.id }.sorted().joined(separator: ",")
        return "\(fmt.string(from: now))-\(block):\(ids)"
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
        let upcoming = lessons.filter { $0.startTime.minutesSinceMidnight > nowMins }

        func minsUntil(_ startTime: String) -> Int {
            startTime.minutesSinceMidnight - nowMins
        }

        func relativeTime(mins: Int) -> String {
            if mins < 60 { return "in \(mins) min" }
            let h = mins / 60, m = mins % 60
            return m == 0 ? "in \(h)h" : "in \(h)h \(m)m"
        }

        func labelDone(_ l: Lesson) -> String {
            var s = "\(l.title) (\(l.startTime)–\(l.endTime)"
            if !l.room.isEmpty { s += ", \(l.room)" }
            return s + ")"
        }

        func labelAhead(_ l: Lesson) -> String {
            let delta = minsUntil(l.startTime)
            var s = "\(l.title) at \(l.startTime) (\(relativeTime(mins: delta))"
            if !l.room.isEmpty { s += ", \(l.room)" }
            return s + ")"
        }

        let statusLine: String
        if let a = active {
            var s = "IN PROGRESS: \(a.title), \(a.startTime)–\(a.endTime)"
            if !a.room.isEmpty { s += ", \(a.room)" }
            statusLine = s
        } else {
            statusLine = "NOTHING IN PROGRESS at \(timeFmt.string(from: now))"
        }

        return """
These facts are exact and app-computed. Do not alter or contradict them.

TIME: \(timeFmt.string(from: now)), \(dayFmt.string(from: now))
STATUS: \(statusLine)
DONE: \(done.isEmpty ? "none" : done.map { labelDone($0) }.joined(separator: ", "))
AHEAD: \(upcoming.isEmpty ? "none" : upcoming.map { labelAhead($0) }.joined(separator: ", "))

Write 1–2 sentences for the student (use "you"). Use the subject names, times, and rooms from above.
Rule: only use words like "currently", "right now", or "in progress" if STATUS says IN PROGRESS. Otherwise describe what's done and what's coming up.
"""
    }
}

// MARK: - AI Schedule Assistant Sheet (iOS 26+)

@available(iOS 26.0, *)
struct AIScheduleAssistantSheet: View {
    @ObservedObject var model: AppModel

    struct Message: Identifiable {
        let id = UUID()
        let role: Role
        let text: String
        enum Role { case user, assistant }
    }

    @State private var session: LanguageModelSession
    @State private var messages: [Message] = []
    @State private var streamingText = ""
    @State private var inputText = ""
    @State private var isResponding = false
    @FocusState private var inputFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private static let suggestions = [
        "What's left for me today?",
        "Any back-to-backs this week?",
        "What's my busiest day?",
        "When does my day start tomorrow?",
    ]

    init(model: AppModel) {
        self._model = ObservedObject(wrappedValue: model)
        self._session = State(initialValue: LanguageModelSession(instructions: Self.systemInstructions(model: model)))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                messageList
                inputBar
            }
            .navigationTitle("UniVRse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { rebuildSession() } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.subheadline)
                    }
                    .tint(Color.uiTextMuted)
                    .disabled(messages.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.subheadline.weight(.semibold))
                        .tint(Color.uiAccent)
                }
            }
        }
        .onAppear { inputFocused = true }
    }

    private func rebuildSession() {
        session = LanguageModelSession(instructions: Self.systemInstructions(model: model))
        messages = []
        streamingText = ""
    }

    // MARK: - Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if messages.isEmpty && !isResponding {
                        emptyState.padding(.top, 32)
                    }
                    ForEach(messages) { msg in
                        messageBubble(msg)
                            .id(msg.id)
                            .transition(.asymmetric(
                                insertion: .move(edge: msg.role == .user ? .trailing : .leading).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                    if isResponding {
                        if streamingText.isEmpty {
                            assistantRow { TypingDots() } .id("typing")
                        } else {
                            assistantRow {
                                renderedText(streamingText + "▌", role: .assistant)
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.uiTextPrimary)
                            }
                            .id("streaming")
                        }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: messages.count)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { _, _ in
                withAnimation { proxy.scrollTo("bottom") }
            }
            .onChange(of: streamingText) { _, _ in
                proxy.scrollTo("bottom")
            }
            .onChange(of: isResponding) { _, new in
                if new { withAnimation { proxy.scrollTo("bottom") } }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 24) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(uiAccentGradient)
                        .frame(width: 52, height: 52)
                    Image(systemName: "sparkles")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Text("UniVRse")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.uiTextPrimary)
                Text("Your schedule, on demand.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.uiTextMuted)
            }

            VStack(spacing: 7) {
                ForEach(Self.suggestions, id: \.self) { suggestion in
                    Button { send(suggestion) } label: {
                        HStack {
                            Text(suggestion)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.uiTextSecondary)
                            Spacer()
                            Image(systemName: "arrow.up.left")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.uiTextMuted)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(Color.uiSurface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Bubbles

    @ViewBuilder
    private func messageBubble(_ msg: Message) -> some View {
        if msg.role == .user {
            HStack(spacing: 0) {
                Spacer(minLength: 56)
                renderedText(msg.text, role: .user)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(uiAccentGradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        } else {
            assistantRow {
                renderedText(msg.text, role: .assistant)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.uiTextPrimary)
            }
        }
    }

    @ViewBuilder
    private func assistantRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            Circle()
                .fill(uiAccentGradient)
                .frame(width: 26, height: 26)
                .overlay(
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                )
            content()
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.uiSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 56)
        }
    }

    @ViewBuilder
    private func renderedText(_ text: String, role: Message.Role) -> some View {
        if role == .assistant,
           let attributed = try? AttributedString(
               markdown: text,
               options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
           ) {
            Text(attributed)
        } else {
            Text(text)
        }
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask anything…", text: $inputText, axis: .vertical)
                .font(.system(size: 15))
                .foregroundStyle(Color.uiTextPrimary)
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.uiSurfaceInput, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .focused($inputFocused)
                .onSubmit { send(inputText) }

            Button { send(inputText) } label: {
                Image(systemName: isResponding ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(
                        inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isResponding
                            ? Color.uiTextMuted : Color.uiAccent
                    )
                    .animation(.easeInOut(duration: 0.15), value: isResponding)
            }
            .buttonStyle(.plain)
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isResponding)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.uiStroke).frame(height: 0.5)
        }
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 0) }
    }

    // MARK: - Send

    private func send(_ rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isResponding else { return }
        inputText = ""
        messages.append(Message(role: .user, text: text))
        isResponding = true
        streamingText = ""

        Task {
            do {
                var accumulated = ""
                for try await partial in session.streamResponse(to: text) {
                    let chunk = String(partial.content)
                    accumulated = chunk
                    streamingText = chunk
                }
                let reply = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
                messages.append(Message(role: .assistant, text: reply.isEmpty ? "Not sure — try rephrasing." : reply))
            } catch {
                messages.append(Message(role: .assistant, text: "Something went wrong. Try again."))
            }
            streamingText = ""
            isResponding = false
        }
    }

    // MARK: - System instructions

    private static func systemInstructions(model: AppModel) -> String {
        let now = Date()
        let cal = Calendar.current
        let nowMins = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)

        let timeFmt = DateFormatter()
        timeFmt.locale = Locale(identifier: "en_US")
        timeFmt.dateFormat = "HH:mm"

        let dateFmt = DateFormatter()
        dateFmt.locale = Locale(identifier: "en_US")
        dateFmt.dateFormat = "EEEE d MMMM"

        let dayFmt = DateFormatter()
        dayFmt.locale = Locale(identifier: "en_US")
        dayFmt.dateFormat = "EEEE"

        let today = cal.startOfDay(for: now)
        let weekLessons = model.lessonsGroupedByDay

        var lines = [
            "You are UniVRse, a schedule assistant for a university student at the University of Verona.",
            "Speak directly to the student using \"you\"/\"your\". Be conversational and concise — answer in 1–3 sentences unless more detail is explicitly asked for.",
            "Use a cool, natural tone. Never say \"I have\" or speak from your own perspective.",
            "You can handle casual conversation but always ground your answers in the schedule data below when relevant.",
            "",
            "Now: \(timeFmt.string(from: now)), \(dateFmt.string(from: now)).",
            ""
        ]

        let todayLessons = weekLessons.first(where: { cal.isDate($0.date, inSameDayAs: today) })?.lessons ?? []
        if !todayLessons.isEmpty {
            lines.append("TODAY:")
            for l in todayLessons {
                let endMins = l.endTime.minutesSinceMidnight
                let startMins = l.startTime.minutesSinceMidnight
                let tag = endMins <= nowMins ? "done" : startMins <= nowMins ? "now" : "ahead"
                var entry = "  [\(tag)] \(l.startTime)–\(l.endTime) \(l.title)"
                if !l.room.isEmpty { entry += " · \(l.room)" }
                if !l.professor.isEmpty { entry += " · \(l.professor)" }
                lines.append(entry)
            }
            lines.append("")
        }

        let otherDays = weekLessons.filter { !cal.isDate($0.date, inSameDayAs: today) && !$0.lessons.isEmpty }
        if !otherDays.isEmpty {
            lines.append("REST OF WEEK:")
            for (date, lessons) in otherDays {
                let isTomorrow = cal.isDate(date, inSameDayAs: cal.date(byAdding: .day, value: 1, to: today) ?? today)
                let label = isTomorrow ? "Tomorrow (\(dayFmt.string(from: date)))" : dayFmt.string(from: date)
                let items = lessons.map { l -> String in
                    var s = "\(l.startTime)–\(l.endTime) \(l.title)"
                    if !l.room.isEmpty { s += " · \(l.room)" }
                    return s
                }.joined(separator: "; ")
                lines.append("  \(label): \(items)")
            }
            lines.append("")
        }

        lines += [
            "Rules:",
            "- Only reference facts from the schedule above. Never invent titles, times, rooms, or professors.",
            "- Reason about relative dates (tomorrow, Monday, etc.) using the current date.",
            "- Keep answers short by default. Be direct.",
        ]
        return lines.joined(separator: "\n")
    }
}

// MARK: - Typing Dots

@available(iOS 26.0, *)
private struct TypingDots: View {
    @State private var phase = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.uiTextMuted.opacity(0.6))
                    .frame(width: 7, height: 7)
                    .offset(y: phase ? -4 : 0)
                    .animation(
                        .easeInOut(duration: 0.45)
                            .repeatForever()
                            .delay(Double(i) * 0.15),
                        value: phase
                    )
            }
        }
        .onAppear { phase = true }
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
