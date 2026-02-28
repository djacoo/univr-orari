import Foundation
import Combine

@MainActor
final class AppModel: ObservableObject {
    private let apiClient: UniVRAPIClient
    private let localStore: LocalDataStore

    private var preferredCourseID: String?
    private var preferredBuildingID: String?
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
            let clamped = min(max(selectedCourseYear, 1), selectedCourse?.maxYear ?? 5)
            if clamped != selectedCourseYear {
                selectedCourseYear = clamped
                return
            }
            persistPreferences()
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
            if let maxYear = selectedCourse?.maxYear, selectedCourseYear > maxYear {
                selectedCourseYear = maxYear
            }
            persistPreferences()
        }
    }

    var selectedCourseMaxYear: Int {
        selectedCourse?.maxYear ?? 3
    }

    @Published var lessons: [Lesson] = [] {
        didSet {
            lessonsGroupedByDay = Self.groupLessons(lessons)
        }
    }
    @Published private(set) var lessonsGroupedByDay: [(date: Date, lessons: [Lesson])] = []

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
    }

    var requiresInitialSetup: Bool {
        !hasCompletedInitialSetup || selectedCourse == nil
    }

    var availableAcademicYears: [Int] {
        let current = DateHelpers.currentAcademicYear()
        return Array((current - 2)...(current + 1)).sorted(by: >)
    }

    var selectedAcademicYearLabel: String {
        academicYearLabel(for: selectedAcademicYear)
    }

    private static func groupLessons(_ lessons: [Lesson]) -> [(date: Date, lessons: [Lesson])] {
        let grouped = Dictionary(grouping: lessons, by: { DateHelpers.startOfDay(for: $0.date) })
        return grouped
            .map { day, dayLessons in
                (day, dayLessons.sorted { lhs, rhs in lhs.startTime < rhs.startTime })
            }
            .sorted { lhs, rhs in lhs.date < rhs.date }
    }

    private static func computeWeekRangeTitle(from weekStart: Date) -> String {
        let weekEnd = DateHelpers.italianCalendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return "\(DateHelpers.weekdayShortFormatter.string(from: weekStart)) - \(DateHelpers.weekdayShortFormatter.string(from: weekEnd))"
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
        await loadCourses()
        await loadBuildings()
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
                    coursesError = "Il server UniVR non ha restituito corsi. Mostro elenco offline."
                    if hasCompletedInitialSetup {
                        await refreshLessons()
                    }
                    return
                }

                allCourses = []
                selectedCourse = nil
                lessons = []
                coursesError = "Nessun corso disponibile dal server UniVR."
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
                    coursesError = "Connessione non disponibile. Uso elenco corsi salvato offline."
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
                    buildingsError = "Il server UniVR non ha restituito edifici. Uso elenco offline."
                    if hasCompletedInitialSetup {
                        await refreshRooms()
                    }
                    return
                }

                buildings = []
                selectedBuilding = nil
                occupiedRooms = []
                freeRoomSlots = []
                buildingsError = "Nessun edificio disponibile dal server UniVR."
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
                    buildingsError = "Connessione non disponibile. Uso elenco edifici salvato offline."
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

        isLoadingLessons = true
        lessonsError = nil

        defer { isLoadingLessons = false }

        let key = lessonsCacheKey(
            courseID: selectedCourse.id,
            courseYear: selectedCourseYear,
            academicYear: selectedAcademicYear,
            weekStart: weekStartDate
        )

        do {
            let fetchedLessons = try await apiClient.fetchWeeklyLessons(
                courseID: selectedCourse.id,
                courseYear: selectedCourseYear,
                academicYear: selectedAcademicYear,
                weekStart: weekStartDate
            )
            lessons = fetchedLessons
            localStore.saveLessonsCache(forKey: key, lessons: fetchedLessons)
        } catch {
            if let cached = localStore.loadLessonsCache(forKey: key) {
                lessons = cached.lessons
                lessonsError = "Connessione non disponibile. Mostro orario offline aggiornato al \(Self.cacheDateFormatter.string(from: cached.savedAt))."
            } else {
                lessonsError = error.localizedDescription
            }
        }
    }

    func refreshRooms() async {
        isLoadingRooms = true
        roomsError = nil

        defer { isLoadingRooms = false }

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
        } catch {
            if let cached = localStore.loadRoomsCache(forKey: key) {
                occupiedRooms = cached.occupiedRooms
                freeRoomSlots = cached.freeRoomSlots
                roomsError = "Connessione non disponibile. Mostro disponibilita aule offline aggiornata al \(Self.cacheDateFormatter.string(from: cached.savedAt))."
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

    func completeInitialSetup(course: StudyCourse, academicYear: Int) async {
        selectedCourse = course
        selectedAcademicYear = academicYear
        hasCompletedInitialSetup = true
        weekStartDate = defaultWeekStart(forAcademicYear: academicYear)
        await refreshLessons()
        await refreshRooms()
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

    private func persistPreferences() {
        localStore.savePreferences(
            StoredPreferences(
                selectedCourseID: selectedCourse?.id,
                selectedCourseYear: selectedCourseYear,
                selectedBuildingID: selectedBuilding?.id,
                selectedAcademicYear: selectedAcademicYear,
                hasCompletedInitialSetup: hasCompletedInitialSetup
            )
        )
    }

    func academicYearLabel(for academicYear: Int) -> String {
        let endYearShort = (academicYear + 1) % 100
        return String(format: "%d/%02d", academicYear, endYearShort)
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

    private static let cacheDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.dateStyle = .short
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

    static let `default` = StoredPreferences(
        selectedCourseID: nil,
        selectedCourseYear: 1,
        selectedBuildingID: nil,
        selectedAcademicYear: nil,
        hasCompletedInitialSetup: nil
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

final class LocalDataStore {
    private enum Key {
        static let preferences = "univr.preferences"
        static let courses = "univr.cache.courses"
        static let buildings = "univr.cache.buildings"
        static let lessons = "univr.cache.lessons"
        static let rooms = "univr.cache.rooms"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
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
