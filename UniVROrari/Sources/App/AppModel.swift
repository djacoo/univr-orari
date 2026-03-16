import Foundation
import Combine
import UIKit
import UserNotifications
import ActivityKit
import CoreSpotlight
import UniformTypeIdentifiers

enum ShortcutAction {
    case openTimetable
    case findFreeRoom
}

struct LectureActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable, Hashable {
            case live       // lesson in progress
            case upcoming   // starts within lead-time window
            case idle       // gap between lessons, next lesson later today
            case allDone    // no more lessons today
        }
        let phase: Phase
        let lessonTitle: String
        let room: String
        let startTime: String
        let endTime: String
        let startDate: Date   // lesson start (or next lesson start for idle/upcoming)
        let endDate: Date     // lesson end
        let isDarkMode: Bool
    }
    let courseName: String
}

@MainActor
final class AppModel: ObservableObject {
    private let apiClient: UniVRAPIClient
    private let localStore: LocalDataStore

    private var preferredCourseID: String?
    private var preferredBuildingID: String?
    private var appearanceObserver: NSObjectProtocol?
    private let defaultAcademicYear = DateHelpers.currentAcademicYear()
    private var _weekBounds: (start: Date, end: Date) = (Date(), Date())

    @Published var selectedAcademicYear: Int = DateHelpers.currentAcademicYear() {
        didSet {
            let allowedYears = availableAcademicYears
            if !allowedYears.contains(selectedAcademicYear), let fallback = allowedYears.first {
                selectedAcademicYear = fallback
                return
            }

            _weekBounds = Self.computeWeekBounds(for: selectedAcademicYear)

            if oldValue != selectedAcademicYear {
                weekStartDate = defaultWeekStart(forAcademicYear: selectedAcademicYear)
            }

            persistPreferences()
        }
    }

    @Published var selectedCourseYear: Int = 1 {
        didSet {
            let clamped = min(max(selectedCourseYear, 1), selectedCourse?.maxYear ?? 3)
            if clamped != selectedCourseYear {
                selectedCourseYear = clamped
                return
            }
            guard !_isApplyingCourseChange else { return }
            persistPreferences()
            loadSubjectFilter()
        }
    }

    @Published var weekStartDate: Date = DateHelpers.monday(for: Date()) {
        didSet {
            weekRangeTitle = Self.computeWeekRangeTitle(from: weekStartDate)
            canGoPreviousWeek = DateHelpers.addWeeks(-1, to: weekStartDate) >= _weekBounds.start
            canGoNextWeek = DateHelpers.addWeeks(1, to: weekStartDate) <= _weekBounds.end
        }
    }
    @Published private(set) var weekRangeTitle: String = ""
    @Published private(set) var canGoPreviousWeek: Bool = false
    @Published private(set) var canGoNextWeek: Bool = false

    @Published var hasCompletedInitialSetup = false {
        didSet {
            persistPreferences()
        }
    }

    @Published var allCourses: [StudyCourse] = []
    @Published var selectedCourse: StudyCourse? {
        didSet {
            preferredCourseID = selectedCourse?.id
            _isApplyingCourseChange = true
            if let maxYear = selectedCourse?.maxYear, selectedCourseYear > maxYear {
                selectedCourseYear = maxYear
            }
            _isApplyingCourseChange = false
            lessons = []
            lessonsError = nil
            persistPreferences()
            loadSubjectFilter()
        }
    }

    var selectedCourseMaxYear: Int {
        selectedCourse?.maxYear ?? 3
    }

    @Published var lessons: [Lesson] = [] {
        didSet {
            accumulateKnownSubjects(from: lessons)
            lessonsGroupedByDay = Self.groupLessons(lessons, excluding: hiddenSubjects)
        }
    }
    @Published private(set) var lessonsGroupedByDay: [(date: Date, lessons: [Lesson])] = []

    @Published private(set) var knownSubjects: [String] = []
    @Published var hiddenSubjects: Set<String> = [] {
        didSet {
            guard !_isLoadingSubjectFilter else { return }
            lessonsGroupedByDay = Self.groupLessons(lessons, excluding: hiddenSubjects)
            saveSubjectFilter()
            persistPreferences()
        }
    }
    private var _isLoadingSubjectFilter = false
    private var _isApplyingCourseChange = false

    @Published var buildings: [Building] = []
    @Published var selectedBuilding: Building? {
        didSet {
            preferredBuildingID = selectedBuilding?.id
            persistPreferences()
        }
    }

    @Published var selectedRoomsDate: Date = DateHelpers.startOfDay(for: Date())
    @Published var occupiedRooms: [RoomAgenda] = [] {
        didSet { allRoomNames = Self.computeAllRoomNames(occupiedRooms: occupiedRooms, freeRoomSlots: freeRoomSlots) }
    }
    @Published var freeRoomSlots: [FreeRoomSlot] = [] {
        didSet { allRoomNames = Self.computeAllRoomNames(occupiedRooms: occupiedRooms, freeRoomSlots: freeRoomSlots) }
    }
    @Published private(set) var allRoomNames: [String] = []

    @Published var username: String = "" {
        didSet { persistPreferences() }
    }
    @Published var profileImage: UIImage?

    @Published var isWorker: Bool = false {
        didSet { persistPreferences() }
    }

    @Published var notificationsEnabled: Bool = false {
        didSet {
            persistPreferences()
            if notificationsEnabled {
                Task { await requestNotificationPermission() }
            } else {
                UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            }
        }
    }
    @Published var notificationLeadMinutes: Int = 15 {
        didSet {
            persistPreferences()
            if notificationsEnabled { scheduleNotifications(for: lessons) }
            if liveActivitiesEnabled { refreshLiveActivity() }
        }
    }

    @Published var liveActivitiesEnabled: Bool = false {
        didSet {
            persistPreferences()
            if liveActivitiesEnabled {
                refreshLiveActivity()
            } else {
                endLectureActivity()
            }
        }
    }
    @Published var workShifts: [WorkShift] = WorkShift.defaults {
        didSet { localStore.saveWorkShifts(workShifts) }
    }

    @Published var pendingShortcutAction: ShortcutAction?

    private var lectureActivity: Activity<LectureActivityAttributes>?
    private var liveActivityTimerTask: Task<Void, Never>?

    private static let profileImageURL: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("profile_photo.jpg")
    }()

    func saveProfileImage(_ image: UIImage) {
        profileImage = image
        if let data = image.jpegData(compressionQuality: 0.85) {
            try? data.write(to: Self.profileImageURL)
        }
    }

    @Published var isLoadingCourses = false
    @Published var isLoadingLessons = false
    @Published var isLoadingBuildings = false
    @Published var isLoadingRooms = false

    @Published var coursesError: String?
    @Published var lessonsError: String?
    @Published var buildingsError: String?
    @Published var roomsError: String?

    init(
        apiClient: UniVRAPIClient = UniVRAPIClient(),
        localStore: LocalDataStore = LocalDataStore()
    ) {
        self.apiClient = apiClient
        self.localStore = localStore

        let storedPreferences = localStore.loadPreferences()

        selectedCourseYear = min(max(storedPreferences.selectedCourseYear, 1), 5)
        selectedAcademicYear = storedPreferences.selectedAcademicYear ?? defaultAcademicYear
        hasCompletedInitialSetup = storedPreferences.hasCompletedInitialSetup ?? (storedPreferences.selectedCourseID != nil)
        preferredCourseID = storedPreferences.selectedCourseID
        preferredBuildingID = storedPreferences.selectedBuildingID
        username = storedPreferences.username ?? ""
        if let data = try? Data(contentsOf: Self.profileImageURL),
           let image = UIImage(data: data) {
            profileImage = image
        }

        isWorker = storedPreferences.isWorker ?? false
        workShifts = localStore.loadWorkShifts() ?? WorkShift.defaults
        notificationsEnabled = storedPreferences.notificationsEnabled ?? false
        notificationLeadMinutes = storedPreferences.notificationLeadMinutes ?? 15
        liveActivitiesEnabled = storedPreferences.liveActivitiesEnabled ?? false

        let cachedCourses = localStore.loadCourses()
        if !cachedCourses.isEmpty {
            allCourses = cachedCourses
            applyPreferredCourseSelection()
        }

        let cachedBuildings = localStore.loadBuildings()
        if !cachedBuildings.isEmpty {
            buildings = cachedBuildings
            applyPreferredBuildingSelection()
        }

        _weekBounds = Self.computeWeekBounds(for: selectedAcademicYear)
        weekStartDate = defaultWeekStart(forAcademicYear: selectedAcademicYear)
        // weekRangeTitle, canGoPreviousWeek, canGoNextWeek already set by weekStartDate.didSet above

        appearanceObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let isDark = UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .first?.traitCollection.userInterfaceStyle == .dark
                self.refreshLiveActivity(isDark: isDark)
            }
        }
    }

    var requiresInitialSetup: Bool {
        !hasCompletedInitialSetup || selectedCourse == nil
    }

    var availableAcademicYears: [Int] {
        let current = DateHelpers.currentAcademicYear()
        return Array((current - 4)...(current + 1)).sorted(by: >)
    }

    var selectedAcademicYearLabel: String {
        academicYearLabel(for: selectedAcademicYear)
    }

    private static func groupLessons(_ lessons: [Lesson], excluding hiddenSubjects: Set<String> = []) -> [(date: Date, lessons: [Lesson])] {
        let visible = hiddenSubjects.isEmpty ? lessons : lessons.filter { !hiddenSubjects.contains($0.title) }
        let grouped = Dictionary(grouping: visible, by: { DateHelpers.startOfDay(for: $0.date) })
        return grouped
            .map { day, dayLessons in
                (day, dayLessons.sorted { lhs, rhs in lhs.startTime < rhs.startTime })
            }
            .sorted { lhs, rhs in lhs.date < rhs.date }
    }

    private static func computeWeekRangeTitle(from weekStart: Date) -> String {
        let weekEnd = DateHelpers.italianCalendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        let startStr = DateHelpers.weekdayShortFormatter.string(from: weekStart)
        let endStr   = DateHelpers.weekdayShortFormatter.string(from: weekEnd)
        let startMonth = DateHelpers.monthAbbrevFormatter.string(from: weekStart)
        let endMonth   = DateHelpers.monthAbbrevFormatter.string(from: weekEnd)
        if startMonth == endMonth {
            return "\(startStr) – \(endStr) \(endMonth)"
        }
        return "\(startStr) \(startMonth) – \(endStr) \(endMonth)"
    }

    private static func computeAllRoomNames(occupiedRooms: [RoomAgenda], freeRoomSlots: [FreeRoomSlot]) -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        for r in occupiedRooms where seen.insert(r.roomName).inserted { names.append(r.roomName) }
        for r in freeRoomSlots where seen.insert(r.roomName).inserted { names.append(r.roomName) }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private static func computeWeekBounds(for academicYear: Int) -> (start: Date, end: Date) {
        let startComponents = DateComponents(year: academicYear, month: 8, day: 1)
        let endComponents = DateComponents(year: academicYear + 1, month: 7, day: 31)
        let rawStart = DateHelpers.italianCalendar.date(from: startComponents) ?? DateHelpers.startOfDay(for: Date())
        let rawEnd = DateHelpers.italianCalendar.date(from: endComponents) ?? DateHelpers.startOfDay(for: Date())
        return (start: DateHelpers.monday(for: rawStart), end: DateHelpers.monday(for: rawEnd))
    }

    func bootstrap() async {
        async let courses: Void = loadCourses()
        async let buildings: Void = loadBuildings()
        await courses
        await buildings
        clampWeekStartWithinAcademicYear()
    }

    func loadCourses() async {
        isLoadingCourses = true
        coursesError = nil

        defer { isLoadingCourses = false }

        do {
            let courses = try await apiClient.fetchCourses()
            if courses.isEmpty {
                let cachedCourses = localStore.loadCourses()
                if !cachedCourses.isEmpty {
                    allCourses = cachedCourses
                    applyPreferredCourseSelection()
                    coursesError = "UniVR server returned no results. Showing cached course list."
                    if hasCompletedInitialSetup {
                        await refreshLessons()
                    }
                    return
                }

                allCourses = []
                selectedCourse = nil
                lessons = []
                coursesError = "No courses available from the UniVR server."
                return
            }

            allCourses = courses
            localStore.saveCourses(courses)
            applyPreferredCourseSelection()
            if hasCompletedInitialSetup {
                await refreshLessons()
            }
        } catch {
            if allCourses.isEmpty {
                let cachedCourses = localStore.loadCourses()
                if !cachedCourses.isEmpty {
                    allCourses = cachedCourses
                    applyPreferredCourseSelection()
                    coursesError = "No connection — showing cached course list."
                    if hasCompletedInitialSetup {
                        await refreshLessons()
                    }
                    return
                }
            }

            coursesError = error.localizedDescription
        }
    }

    func loadBuildings() async {
        isLoadingBuildings = true
        buildingsError = nil

        defer { isLoadingBuildings = false }

        do {
            let availableBuildings = try await apiClient.fetchBuildings()
            if availableBuildings.isEmpty {
                let cachedBuildings = localStore.loadBuildings()
                if !cachedBuildings.isEmpty {
                    buildings = cachedBuildings
                    applyPreferredBuildingSelection()
                    buildingsError = "UniVR server returned no results. Showing cached building list."
                    if hasCompletedInitialSetup {
                        await refreshRooms()
                    }
                    return
                }

                buildings = []
                selectedBuilding = nil
                occupiedRooms = []
                freeRoomSlots = []
                buildingsError = "No buildings available from the UniVR server."
                return
            }

            buildings = availableBuildings
            localStore.saveBuildings(availableBuildings)
            applyPreferredBuildingSelection()
            if hasCompletedInitialSetup {
                await refreshRooms()
            }
        } catch {
            if buildings.isEmpty {
                let cachedBuildings = localStore.loadBuildings()
                if !cachedBuildings.isEmpty {
                    buildings = cachedBuildings
                    applyPreferredBuildingSelection()
                    buildingsError = "No connection — showing cached building list."
                    if hasCompletedInitialSetup {
                        await refreshRooms()
                    }
                    return
                }
            }

            buildingsError = error.localizedDescription
        }
    }

    func refreshLessons() async {
        guard let selectedCourse else {
            lessons = []
            return
        }

        lessonsError = nil

        let key = lessonsCacheKey(
            courseID: selectedCourse.id,
            courseYear: selectedCourseYear,
            academicYear: selectedAcademicYear,
            weekStart: weekStartDate
        )

        // Surface cached data immediately so the UI is not blank while the network request runs.
        let cached = localStore.loadLessonsCache(forKey: key)
        if let cached {
            lessons = cached.lessons
            isLoadingLessons = false
        } else {
            lessons = []
            isLoadingLessons = true
        }

        do {
            let fetchedLessons = try await apiClient.fetchWeeklyLessons(
                courseID: selectedCourse.id,
                courseYear: selectedCourseYear,
                academicYear: selectedAcademicYear,
                weekStart: weekStartDate
            )
            lessons = fetchedLessons
            isLoadingLessons = false
            localStore.saveLessonsCache(forKey: key, lessons: fetchedLessons)
            scheduleNotifications(for: fetchedLessons)
            indexLessonsForSpotlight(fetchedLessons)
            refreshLiveActivity()
        } catch {
            if Self.isCancelledError(error) { return }
            isLoadingLessons = false
            if let cached {
                lessonsError = "No connection — showing offline schedule as of \(Self.cacheDateFormatter.string(from: cached.savedAt))."
            } else {
                lessonsError = error.localizedDescription
            }
        }
    }

    func refreshRooms() async {
        isLoadingRooms = true
        roomsError = nil

        let key = roomsCacheKey(date: selectedRoomsDate, buildingID: selectedBuilding?.id)

        do {
            let response = try await apiClient.fetchRoomAgenda(
                date: selectedRoomsDate,
                buildingID: selectedBuilding?.id
            )
            occupiedRooms = response.agendas
            freeRoomSlots = response.freeSlots
            localStore.saveRoomsCache(
                forKey: key,
                occupiedRooms: response.agendas,
                freeRoomSlots: response.freeSlots
            )
            isLoadingRooms = false
        } catch {
            if Self.isCancelledError(error) { return }
            isLoadingRooms = false
            if let cached = localStore.loadRoomsCache(forKey: key) {
                occupiedRooms = cached.occupiedRooms
                freeRoomSlots = cached.freeRoomSlots
                roomsError = "No connection — showing offline room availability as of \(Self.cacheDateFormatter.string(from: cached.savedAt))."
            } else {
                roomsError = error.localizedDescription
            }
        }
    }

    func goToPreviousWeek() {
        let candidate = DateHelpers.addWeeks(-1, to: weekStartDate)
        guard candidate >= _weekBounds.start else { return }
        weekStartDate = candidate
    }

    func goToNextWeek() {
        let candidate = DateHelpers.addWeeks(1, to: weekStartDate)
        guard candidate <= _weekBounds.end else { return }
        weekStartDate = candidate
    }

    func jumpToToday() {
        let today = DateHelpers.monday(for: Date())
        weekStartDate = min(max(today, _weekBounds.start), _weekBounds.end)
    }

    func navigateToWeekContaining(_ date: Date) {
        weekStartDate = DateHelpers.monday(for: date)
    }

    func refreshLiveActivity(isDark: Bool? = nil) {
        guard liveActivitiesEnabled else { return }
        if lectureActivity == nil {
            lectureActivity = Activity<LectureActivityAttributes>.activities.first
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let cal = Calendar.current
        let now = Date()
        guard cal.isDateInToday(now) else { endLectureActivity(); return }

        let dark = isDark ?? (UIScreen.main.traitCollection.userInterfaceStyle == .dark)
        let currentMins = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        let todayLessons = lessonsGroupedByDay.first(where: { cal.isDateInToday($0.date) })?.lessons ?? []
        let state = computeActivityState(now: now, currentMins: currentMins, todayLessons: todayLessons, isDark: dark)

        if let activity = lectureActivity {
            Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
        } else {
            let attrs = LectureActivityAttributes(courseName: selectedCourse?.name ?? "")
            lectureActivity = try? Activity<LectureActivityAttributes>.request(
                attributes: attrs,
                content: ActivityContent(state: state, staleDate: nil)
            )
        }
        scheduleLiveActivityTimer(todayLessons: todayLessons, currentMins: currentMins)
    }

    private func computeActivityState(
        now: Date,
        currentMins: Int,
        todayLessons: [Lesson],
        isDark: Bool
    ) -> LectureActivityAttributes.ContentState {
        var romeCal = Calendar(identifier: .gregorian)
        romeCal.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current

        // 1. Lesson currently live
        if let lesson = todayLessons.first(where: {
            $0.startTime.minutesSinceMidnight <= currentMins && currentMins < $0.endTime.minutesSinceMidnight
        }) {
            return makeActivityState(phase: .live, lesson: lesson, romeCal: romeCal, now: now, isDark: isDark)
        }

        // 2. Upcoming within lead-time window
        if let lesson = todayLessons.first(where: {
            let s = $0.startTime.minutesSinceMidnight
            return s > currentMins && s - currentMins <= notificationLeadMinutes
        }) {
            return makeActivityState(phase: .upcoming, lesson: lesson, romeCal: romeCal, now: now, isDark: isDark)
        }

        // 3. Later lesson exists today — show idle countdown
        if let lesson = todayLessons.first(where: { $0.startTime.minutesSinceMidnight > currentMins }) {
            return makeActivityState(phase: .idle, lesson: lesson, romeCal: romeCal, now: now, isDark: isDark)
        }

        // 4. Nothing left today
        return LectureActivityAttributes.ContentState(
            phase: .allDone,
            lessonTitle: "", room: "", startTime: "", endTime: "",
            startDate: now, endDate: now,
            isDarkMode: isDark
        )
    }

    private func makeActivityState(
        phase: LectureActivityAttributes.ContentState.Phase,
        lesson: Lesson,
        romeCal: Calendar,
        now: Date,
        isDark: Bool
    ) -> LectureActivityAttributes.ContentState {
        let startMins = lesson.startTime.minutesSinceMidnight
        var startComps = romeCal.dateComponents([.year, .month, .day], from: lesson.date)
        startComps.hour = startMins / 60; startComps.minute = startMins % 60
        startComps.timeZone = romeCal.timeZone
        let startDate = romeCal.date(from: startComps) ?? now

        let endMins = lesson.endTime.minutesSinceMidnight
        var endComps = romeCal.dateComponents([.year, .month, .day], from: lesson.date)
        endComps.hour = endMins / 60; endComps.minute = endMins % 60
        endComps.timeZone = romeCal.timeZone
        let endDate = romeCal.date(from: endComps) ?? now.addingTimeInterval(3600)

        return LectureActivityAttributes.ContentState(
            phase: phase,
            lessonTitle: lesson.title,
            room: lesson.room,
            startTime: lesson.startTime,
            endTime: lesson.endTime,
            startDate: startDate,
            endDate: endDate,
            isDarkMode: isDark
        )
    }

    private func scheduleLiveActivityTimer(todayLessons: [Lesson], currentMins: Int) {
        liveActivityTimerTask?.cancel()
        guard liveActivitiesEnabled else { return }

        var romeCal = Calendar(identifier: .gregorian)
        romeCal.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current
        let now = Date()
        var transitionDates: [Date] = []

        for lesson in todayLessons {
            let startMins = lesson.startTime.minutesSinceMidnight
            let endMins   = lesson.endTime.minutesSinceMidnight
            let leadMins  = startMins - notificationLeadMinutes

            for mins in [leadMins, startMins, endMins] where mins > currentMins {
                var comps = romeCal.dateComponents([.year, .month, .day], from: lesson.date)
                comps.hour = mins / 60; comps.minute = mins % 60; comps.second = 1
                comps.timeZone = romeCal.timeZone
                if let d = romeCal.date(from: comps), d > now { transitionDates.append(d) }
            }
        }

        guard let next = transitionDates.min() else { return }
        let delay = max(next.timeIntervalSinceNow, 1)

        liveActivityTimerTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                self?.refreshLiveActivity()
            } catch {}
        }
    }

    func endLectureActivity() {
        liveActivityTimerTask?.cancel()
        liveActivityTimerTask = nil
        guard let activity = lectureActivity else { return }
        lectureActivity = nil
        Task { await activity.end(ActivityContent(state: activity.content.state, staleDate: nil), dismissalPolicy: .immediate) }
    }

    private func indexLessonsForSpotlight(_ lessons: [Lesson]) {
        let fmt = DateHelpers.apiDateFormatter
        let items: [CSSearchableItem] = lessons.map { lesson in
            let attrs = CSSearchableItemAttributeSet(contentType: UTType.plainText)
            attrs.title = lesson.title
            let parts = ["\(lesson.startTime)–\(lesson.endTime)", lesson.room, lesson.professor]
                .filter { !$0.isEmpty }
            attrs.contentDescription = parts.joined(separator: " · ")
            attrs.keywords = [lesson.title, lesson.professor, lesson.room, lesson.building]
                .filter { !$0.isEmpty }
            let id = "univr.lesson:\(lesson.id):\(fmt.string(from: lesson.date))"
            return CSSearchableItem(uniqueIdentifier: id, domainIdentifier: "it.univr.orari.lessons", attributeSet: attrs)
        }
        CSSearchableIndex.default().indexSearchableItems(items) { _ in }
    }

    func completeInitialSetup(course: StudyCourse, academicYear: Int) async {
        selectedCourse = course
        selectedAcademicYear = academicYear
        hasCompletedInitialSetup = true
        weekStartDate = defaultWeekStart(forAcademicYear: academicYear)
        async let lessons: Void = refreshLessons()
        async let rooms: Void = refreshRooms()
        await lessons
        await rooms
    }

    func reopenInitialSetup() {
        hasCompletedInitialSetup = false
    }

    private func applyPreferredCourseSelection() {
        if let preferredCourseID {
            if let match = allCourses.first(where: { $0.id == preferredCourseID }) {
                selectedCourse = match
                return
            }
        }

        if let selectedCourse, allCourses.contains(where: { $0.id == selectedCourse.id }) {
            return
        }

        if hasCompletedInitialSetup {
            selectedCourse = allCourses.first
        } else {
            selectedCourse = nil
        }
    }

    private func applyPreferredBuildingSelection() {
        if let preferredBuildingID,
           let preferredBuilding = buildings.first(where: { $0.id == preferredBuildingID }) {
            selectedBuilding = preferredBuilding
            return
        }

        if let selectedBuilding,
           buildings.contains(where: { $0.id == selectedBuilding.id }) {
            return
        }

        selectedBuilding = buildings.first
    }

    func requestNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
        if notificationsEnabled { scheduleNotifications(for: lessons) }
    }

    func scheduleNotifications(for lessons: [Lesson]) {
        guard notificationsEnabled else { return }
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        var romeCal = Calendar(identifier: .gregorian)
        romeCal.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current
        let now = Date()
        let visibleLessons = hiddenSubjects.isEmpty ? lessons : lessons.filter { !hiddenSubjects.contains($0.title) }
        for lesson in visibleLessons {
            let startMins = lesson.startTime.minutesSinceMidnight - notificationLeadMinutes
            guard startMins >= 0 else { continue }
            let dayComps = romeCal.dateComponents([.year, .month, .day], from: lesson.date)
            var fireComps = DateComponents()
            fireComps.timeZone = romeCal.timeZone
            fireComps.year    = dayComps.year
            fireComps.month   = dayComps.month
            fireComps.day     = dayComps.day
            fireComps.hour    = startMins / 60
            fireComps.minute  = startMins % 60
            guard let fireDate = romeCal.date(from: fireComps), fireDate > now else { continue }
            let content = UNMutableNotificationContent()
            content.title = lesson.title
            let bodyParts = [lesson.startTime, lesson.room, lesson.professor].filter { !$0.isEmpty }
            content.body = bodyParts.joined(separator: " · ")
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            let trigger = UNCalendarNotificationTrigger(dateMatching: fireComps, repeats: false)
            let request = UNNotificationRequest(
                identifier: "lesson:\(lesson.id):\(notificationLeadMinutes)",
                content: content,
                trigger: trigger
            )
            center.add(request, withCompletionHandler: nil)
        }
    }

    private func persistPreferences() {
        localStore.savePreferences(
            StoredPreferences(
                selectedCourseID: selectedCourse?.id,
                selectedCourseYear: selectedCourseYear,
                selectedBuildingID: selectedBuilding?.id,
                selectedAcademicYear: selectedAcademicYear,
                hasCompletedInitialSetup: hasCompletedInitialSetup,
                username: username.isEmpty ? nil : username,
                isWorker: isWorker,
                notificationsEnabled: notificationsEnabled,
                notificationLeadMinutes: notificationLeadMinutes,
                liveActivitiesEnabled: liveActivitiesEnabled,
                hiddenSubjects: hiddenSubjects.isEmpty ? nil : Array(hiddenSubjects)
            )
        )
    }

    func workShift(for date: Date) -> WorkShift? {
        guard isWorker else { return nil }
        let weekday = DateHelpers.italianCalendar.component(.weekday, from: date)
        let index = (weekday + 5) % 7
        return workShifts.first(where: { $0.weekday == index && $0.isEnabled })
    }

    func academicYearLabel(for academicYear: Int) -> String {
        let endYearShort = (academicYear + 1) % 100
        return String(format: "%d/%02d", academicYear, endYearShort)
    }

    func toggleSubjectVisibility(_ title: String) {
        if hiddenSubjects.contains(title) {
            hiddenSubjects.remove(title)
        } else {
            hiddenSubjects.insert(title)
        }
    }

    private func accumulateKnownSubjects(from lessons: [Lesson]) {
        guard !lessons.isEmpty else { return }
        var known = Set(knownSubjects)
        var changed = false
        for lesson in lessons where known.insert(lesson.title).inserted {
            knownSubjects.append(lesson.title)
            changed = true
        }
        if changed {
            saveSubjectFilter()
        }
    }

    private func subjectFilterKey() -> String? {
        guard let courseID = selectedCourse?.id else { return nil }
        return "\(courseID):\(selectedCourseYear)"
    }

    private func saveSubjectFilter() {
        guard let key = subjectFilterKey() else { return }
        localStore.saveSubjectFilter(
            SubjectFilterEntry(knownSubjects: knownSubjects, hiddenSubjects: Array(hiddenSubjects), savedAt: Date()),
            forKey: key
        )
    }

    private func loadSubjectFilter() {
        _isLoadingSubjectFilter = true
        defer { _isLoadingSubjectFilter = false }
        guard let key = subjectFilterKey() else {
            knownSubjects = []
            hiddenSubjects = []
            return
        }
        if let entry = localStore.loadSubjectFilter(forKey: key) {
            knownSubjects = entry.knownSubjects
            hiddenSubjects = Set(entry.hiddenSubjects)
        } else {
            knownSubjects = []
            hiddenSubjects = []
        }
    }

    private func clampWeekStartWithinAcademicYear() {
        if weekStartDate < _weekBounds.start {
            weekStartDate = _weekBounds.start
            return
        }

        if weekStartDate > _weekBounds.end {
            weekStartDate = _weekBounds.end
        }
    }

    private func defaultWeekStart(forAcademicYear academicYear: Int) -> Date {
        let today = DateHelpers.startOfDay(for: Date())
        let start = academicYearStartDate(for: academicYear)
        let end = academicYearEndDate(for: academicYear)

        if today >= start && today <= end {
            return DateHelpers.monday(for: today)
        }

        return DateHelpers.monday(for: start)
    }

    private func academicYearStartDate(for academicYear: Int) -> Date {
        let components = DateComponents(year: academicYear, month: 8, day: 1)
        return DateHelpers.italianCalendar.date(from: components) ?? DateHelpers.startOfDay(for: Date())
    }

    private func academicYearEndDate(for academicYear: Int) -> Date {
        let components = DateComponents(year: academicYear + 1, month: 7, day: 31)
        return DateHelpers.italianCalendar.date(from: components) ?? DateHelpers.startOfDay(for: Date())
    }

    private func lessonsCacheKey(courseID: String, courseYear: Int, academicYear: Int, weekStart: Date) -> String {
        let weekStartValue = DateHelpers.apiDateFormatter.string(from: DateHelpers.startOfDay(for: weekStart))
        return "lessons:\(courseID):\(courseYear):\(academicYear):\(weekStartValue)"
    }

    private func roomsCacheKey(date: Date, buildingID: String?) -> String {
        let dateValue = DateHelpers.apiDateFormatter.string(from: DateHelpers.startOfDay(for: date))
        let buildingToken = buildingID ?? "all"
        return "rooms:\(buildingToken):\(dateValue)"
    }

    private static func isCancelledError(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }

    private static let cacheDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

struct StoredPreferences: Codable {
    var selectedCourseID: String?
    var selectedCourseYear: Int
    var selectedBuildingID: String?
    var selectedAcademicYear: Int?
    var hasCompletedInitialSetup: Bool?
    var username: String?
    var isWorker: Bool?
    var notificationsEnabled: Bool?
    var notificationLeadMinutes: Int?
    var liveActivitiesEnabled: Bool?
    var hiddenSubjects: [String]?

    static let `default` = StoredPreferences(
        selectedCourseID: nil,
        selectedCourseYear: 1,
        selectedBuildingID: nil,
        selectedAcademicYear: nil,
        hasCompletedInitialSetup: nil,
        username: nil,
        isWorker: nil,
        notificationsEnabled: nil,
        notificationLeadMinutes: nil,
        liveActivitiesEnabled: nil,
        hiddenSubjects: nil
    )
}

struct LessonsCacheEntry: Codable {
    let key: String
    let savedAt: Date
    let lessons: [Lesson]
}

struct RoomsCacheEntry: Codable {
    let key: String
    let savedAt: Date
    let occupiedRooms: [RoomAgenda]
    let freeRoomSlots: [FreeRoomSlot]
}

struct SubjectFilterEntry: Codable {
    var knownSubjects: [String]
    var hiddenSubjects: [String]
    var savedAt: Date = Date()
}

final class LocalDataStore {
    private enum Key {
        static let preferences = "univr.preferences"
        static let courses = "univr.cache.courses"
        static let buildings = "univr.cache.buildings"
        static let lessons = "univr.cache.lessons"
        static let rooms = "univr.cache.rooms"
        static let subjectFilter = "univr.subjectFilter"
        static let workShifts = "univr.workShifts"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = UserDefaults(suiteName: "group.it.univr.orari") ?? .standard) {
        self.defaults = defaults
    }

    func loadPreferences() -> StoredPreferences {
        guard
            let data = defaults.data(forKey: Key.preferences),
            let preferences = try? decoder.decode(StoredPreferences.self, from: data)
        else {
            return .default
        }

        return preferences
    }

    func savePreferences(_ preferences: StoredPreferences) {
        guard let data = try? encoder.encode(preferences) else {
            return
        }
        defaults.set(data, forKey: Key.preferences)
    }

    func loadCourses() -> [StudyCourse] {
        loadValue([StudyCourse].self, forKey: Key.courses) ?? []
    }

    func saveCourses(_ courses: [StudyCourse]) {
        saveValue(courses, forKey: Key.courses)
    }

    func loadBuildings() -> [Building] {
        loadValue([Building].self, forKey: Key.buildings) ?? []
    }

    func saveBuildings(_ buildings: [Building]) {
        saveValue(buildings, forKey: Key.buildings)
    }

    func loadLessonsCache(forKey key: String) -> LessonsCacheEntry? {
        let entries = loadValue([LessonsCacheEntry].self, forKey: Key.lessons) ?? []
        return entries.first(where: { $0.key == key })
    }

    func saveLessonsCache(forKey key: String, lessons: [Lesson]) {
        var entries = loadValue([LessonsCacheEntry].self, forKey: Key.lessons) ?? []
        entries.removeAll(where: { $0.key == key })
        entries.append(LessonsCacheEntry(key: key, savedAt: Date(), lessons: lessons))
        entries = Array(entries.sorted(by: { $0.savedAt > $1.savedAt }).prefix(60))
        saveValue(entries, forKey: Key.lessons)
    }

    func loadRoomsCache(forKey key: String) -> RoomsCacheEntry? {
        let entries = loadValue([RoomsCacheEntry].self, forKey: Key.rooms) ?? []
        return entries.first(where: { $0.key == key })
    }

    func loadSubjectFilter(forKey key: String) -> SubjectFilterEntry? {
        let all = loadValue([String: SubjectFilterEntry].self, forKey: Key.subjectFilter) ?? [:]
        return all[key]
    }

    func saveSubjectFilter(_ entry: SubjectFilterEntry, forKey key: String) {
        var all = loadValue([String: SubjectFilterEntry].self, forKey: Key.subjectFilter) ?? [:]
        all[key] = entry
        if all.count > 20 {
            let sorted = all.sorted { $0.value.savedAt > $1.value.savedAt }
            all = Dictionary(uniqueKeysWithValues: sorted.prefix(20).map { ($0.key, $0.value) })
        }
        saveValue(all, forKey: Key.subjectFilter)
    }

    func loadWorkShifts() -> [WorkShift]? {
        loadValue([WorkShift].self, forKey: Key.workShifts)
    }

    func saveWorkShifts(_ shifts: [WorkShift]) {
        saveValue(shifts, forKey: Key.workShifts)
    }

    func saveRoomsCache(forKey key: String, occupiedRooms: [RoomAgenda], freeRoomSlots: [FreeRoomSlot]) {
        var entries = loadValue([RoomsCacheEntry].self, forKey: Key.rooms) ?? []
        entries.removeAll(where: { $0.key == key })
        entries.append(
            RoomsCacheEntry(
                key: key,
                savedAt: Date(),
                occupiedRooms: occupiedRooms,
                freeRoomSlots: freeRoomSlots
            )
        )
        entries = Array(entries.sorted(by: { $0.savedAt > $1.savedAt }).prefix(60))
        saveValue(entries, forKey: Key.rooms)
    }

    private func loadValue<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard
            let data = defaults.data(forKey: key),
            let value = try? decoder.decode(T.self, from: data)
        else {
            return nil
        }

        return value
    }

    private func saveValue<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? encoder.encode(value) else {
            return
        }

        defaults.set(data, forKey: key)
    }
}
