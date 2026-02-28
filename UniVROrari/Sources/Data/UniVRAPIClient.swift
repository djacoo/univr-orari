import Foundation

final class UniVRAPIClient {
    private let session: URLSession
    private let baseURL = URL(string: "https://logistica.univr.it/PortaleStudentiUnivr/")!
    private var didWarmupSession = false
    private var courseYearOptionsByCourseID: [String: [CourseYearOption]] = [:]
    private var courseAcademicYearByID: [String: Int] = [:]

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchCourses() async throws -> [StudyCourse] {
        var lastError: Error?

        for academicYear in candidateAcademicYears() {
            do {
                let courses = try await fetchCourses(academicYear: academicYear)
                if !courses.isEmpty {
                    return courses
                }
            } catch {
                lastError = error
            }
        }

        if let lastError {
            throw lastError
        }

        throw UniVRClientError.noData
    }

    func fetchBuildings() async throws -> [Building] {
        let data = try await get(
            path: "combo.php",
            query: [
                "sw": "rooms_",
                "_lang": "it"
            ]
        )

        guard let text = decodeText(from: data) else {
            throw UniVRClientError.invalidEncoding
        }

        let buildings = parseBuildings(from: text)
        guard !buildings.isEmpty else {
            throw UniVRClientError.noData
        }

        return buildings.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    func fetchWeeklyLessons(courseID: String, courseYear: Int, academicYear: Int, weekStart: Date) async throws -> [Lesson] {
        let effectiveCourseYear = max(courseYear, 1)
        let normalizedWeekStart = DateHelpers.startOfDay(for: weekStart)
        let yearOption = try await resolveCourseYearOption(courseID: courseID, requestedCourseYear: effectiveCourseYear)
        let effectiveAcademicYear = academicYear > 0 ? academicYear : (courseAcademicYearByID[courseID] ?? DateHelpers.currentAcademicYear())

        var query: [String: String] = [
            "view": "easycourse",
            "include": "corso",
            "_lang": "it",
            "all_events": "0",
            "anno": String(effectiveAcademicYear),
            "corso": courseID,
            "date": DateHelpers.apiDateFormatter.string(from: normalizedWeekStart),
            "txtcurr": yearOption?.label ?? "Anno \(effectiveCourseYear)"
        ]
        query["anno2[]"] = yearOption?.parameterValue ?? "999|\(effectiveCourseYear)"

        let data = try await get(path: "grid_call.php", query: query)
        let root = try decodeRootObject(from: data)

        let rawLessons = extractObjects(from: root["celle"])
            + extractObjects(from: root["events"])
            + extractObjects(from: root["lessons"])

        var lessons: [Lesson] = []
        var seenLessonIDs = Set<String>()
        lessons.reserveCapacity(rawLessons.count)

        for rawLesson in rawLessons {
            guard
                let title = nonEmpty(
                    stringValue(rawLesson["nome_insegnamento"]),
                    stringValue(rawLesson["name"]),
                    stringValue(rawLesson["nome"]),
                    stringValue(rawLesson["subject"]),
                    stringValue(rawLesson["insegnamento"])
                ),
                let date = parseDate(
                    nonEmpty(
                        stringValue(rawLesson["data"]),
                        stringValue(rawLesson["date"]),
                        stringValue(rawLesson["giorno"])
                    )
                ),
                let timeRange = parseTimeRange(from: rawLesson)
                    ?? parseTimeRange(rawLesson["orario"])
                    ?? parseTimeRange(rawLesson["time"])
            else {
                continue
            }

            let startTime = normalizeTime(timeRange.start)
            let endTime = normalizeTime(timeRange.end)
            let room = nonEmpty(
                stringValue(rawLesson["aula"]),
                stringValue(rawLesson["room"]),
                stringValue(rawLesson["NomeAula"])
            ) ?? "Aula non disponibile"
            let building = nonEmpty(
                stringValue(rawLesson["NomeSede"]),
                extractBuilding(from: room)
            ) ?? "Edificio non specificato"
            let professor = nonEmpty(
                joinedString(from: rawLesson["docenti"]),
                stringValue(rawLesson["docente"]),
                stringValue(rawLesson["prof"]),
                stringValue(rawLesson["nome_docente"])
            ) ?? "Docente non disponibile"

            let rawID = nonEmpty(
                stringValue(rawLesson["id"]),
                stringValue(rawLesson["identifier_cell"])
            ) ?? UUID().uuidString
            let stableID = "\(rawID)-\(DateHelpers.apiDateFormatter.string(from: date))-\(startTime)-\(endTime)-\(room)"

            guard seenLessonIDs.insert(stableID).inserted else {
                continue
            }

            lessons.append(
                Lesson(
                    id: stableID,
                    title: title,
                    professor: professor,
                    room: room,
                    building: building,
                    date: date,
                    startTime: startTime,
                    endTime: endTime
                )
            )
        }

        return lessons.sorted { lhs, rhs in
            if lhs.date != rhs.date {
                return lhs.date < rhs.date
            }
            return lhs.startTime < rhs.startTime
        }
    }

    func fetchRoomAgenda(date: Date, buildingID: String?) async throws -> (agendas: [RoomAgenda], freeSlots: [FreeRoomSlot]) {
        var query: [String: String] = [
            "all_events": "true",
            "view": "easyroom",
            "include": "occupazione",
            "_lang": "it",
            "date": DateHelpers.apiDateFormatter.string(from: DateHelpers.startOfDay(for: date))
        ]

        if let buildingID, !buildingID.isEmpty {
            query["sede"] = buildingID
        }

        let data = try await get(path: "rooms_call.php", query: query)
        let root = try decodeRootObject(from: data)

        let roomNamesByCode = parseRoomNamesByCode(from: root["all_rooms"])
        let tableRows = extractTableRows(from: root["table"])
        let fasceLabels = parseFasceLabels(from: root["fasce"])

        var rawLessons: [(roomCode: String?, payload: [String: Any])] = extractObjects(from: root["events"]).map {
            (roomCode: nil, payload: $0)
        }
        if rawLessons.isEmpty {
            rawLessons = extractEventsFromTable(tableRows: tableRows)
        }

        var agendasByRoom: [String: [RoomLesson]] = [:]
        var seenRoomLessonIDs = Set<String>()

        for rawLesson in rawLessons {
            guard let parsed = parseRoomLesson(
                rawLesson.payload,
                fallbackRoomCode: rawLesson.roomCode,
                roomNamesByCode: roomNamesByCode
            ) else {
                continue
            }

            guard seenRoomLessonIDs.insert(parsed.lesson.id).inserted else {
                continue
            }

            agendasByRoom[parsed.roomName, default: []].append(parsed.lesson)
        }

        let agendas = agendasByRoom.map { roomName, lessons in
            RoomAgenda(
                id: roomName,
                roomName: roomName,
                lessons: lessons.sorted { lhs, rhs in
                    lhs.fromTime < rhs.fromTime
                }
            )
        }
        .sorted { lhs, rhs in
            lhs.roomName.localizedCaseInsensitiveCompare(rhs.roomName) == .orderedAscending
        }

        var freeSlots = extractFreeSlots(
            tableRows: tableRows,
            fasceLabels: fasceLabels,
            roomNamesByCode: roomNamesByCode
        )
        if freeSlots.isEmpty {
            freeSlots = parseLegacyFreeSlots(from: root["aule_libere"])
        }

        freeSlots.sort { lhs, rhs in
            if lhs.roomName != rhs.roomName {
                return lhs.roomName.localizedCaseInsensitiveCompare(rhs.roomName) == .orderedAscending
            }
            return lhs.fromTime < rhs.fromTime
        }

        return (agendas, freeSlots)
    }

    private func fetchCourses(academicYear: Int) async throws -> [StudyCourse] {
        let data = try await get(
            path: "combo.php",
            query: [
                "sw": "ec_",
                "aa": String(academicYear),
                "page": "corsi",
                "_lang": "it"
            ]
        )

        guard let text = decodeText(from: data) else {
            throw UniVRClientError.invalidEncoding
        }

        let courses = parseCourses(from: text, academicYear: academicYear)
        guard !courses.isEmpty else {
            throw UniVRClientError.noData
        }

        return courses
    }

    private func resolveCourseYearOption(courseID: String, requestedCourseYear: Int) async throws -> CourseYearOption? {
        if courseYearOptionsByCourseID[courseID] == nil {
            for academicYear in candidateAcademicYears() {
                _ = try? await fetchCourses(academicYear: academicYear)
                if courseYearOptionsByCourseID[courseID] != nil {
                    break
                }
            }
        }

        guard let options = courseYearOptionsByCourseID[courseID], !options.isEmpty else {
            return nil
        }

        if let exact = options.first(where: { $0.year == requestedCourseYear }) {
            return exact
        }

        if let suffix = options.first(where: { $0.parameterValue.hasSuffix("|\(requestedCourseYear)") }) {
            return suffix
        }

        return options.sorted { $0.year < $1.year }.first
    }

    private func parseCourses(from text: String, academicYear: Int) -> [StudyCourse] {
        guard let rawCourses = parseJavaScriptVariable(named: "elenco_corsi", from: text) as? [Any] else {
            return []
        }

        var uniqueCourses: [String: StudyCourse] = [:]

        for item in rawCourses {
            guard let rawCourse = item as? [String: Any] else {
                continue
            }

            guard
                let id = nonEmpty(
                    stringValue(rawCourse["valore"]),
                    stringValue(rawCourse["value"]),
                    stringValue(rawCourse["id"])
                ),
                let name = nonEmpty(
                    stringValue(rawCourse["label"]),
                    stringValue(rawCourse["name"])
                ),
                isUsefulOption(value: id, label: name)
            else {
                continue
            }

            let options = parseCourseYearOptions(from: rawCourse["elenco_anni"])
            courseYearOptionsByCourseID[id] = mergeCourseYearOptions(
                existing: courseYearOptionsByCourseID[id] ?? [],
                incoming: options
            )
            courseAcademicYearByID[id] = academicYear

            let maxYear = options.map(\.year).max() ?? StudyCourse.detectMaxYear(from: name)
            uniqueCourses[id] = StudyCourse(id: id, name: name, facultyName: "UniVR", maxYear: maxYear)
        }

        return uniqueCourses.values.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func parseBuildings(from text: String) -> [Building] {
        guard let rawBuildings = parseJavaScriptVariable(named: "elenco_sedi", from: text) as? [Any] else {
            return []
        }

        var buildings: [Building] = []
        var seenIDs = Set<String>()

        for item in rawBuildings {
            guard let rawBuilding = item as? [String: Any] else {
                continue
            }

            guard
                let id = nonEmpty(
                    stringValue(rawBuilding["valore"]),
                    stringValue(rawBuilding["value"]),
                    stringValue(rawBuilding["id"])
                ),
                let name = nonEmpty(
                    stringValue(rawBuilding["label"]),
                    stringValue(rawBuilding["name"])
                ),
                isUsefulOption(value: id, label: name),
                seenIDs.insert(id).inserted
            else {
                continue
            }

            buildings.append(Building(id: id, name: name))
        }

        return buildings
    }

    private func parseCourseYearOptions(from rawValue: Any?) -> [CourseYearOption] {
        guard let rawOptions = rawValue as? [Any] else {
            return []
        }

        var options: [CourseYearOption] = []
        var seenValues = Set<String>()

        for item in rawOptions {
            guard let rawOption = item as? [String: Any] else {
                continue
            }

            guard
                let parameterValue = nonEmpty(
                    stringValue(rawOption["valore"]),
                    stringValue(rawOption["value"]),
                    stringValue(rawOption["id"])
                ),
                let label = nonEmpty(
                    stringValue(rawOption["label"]),
                    stringValue(rawOption["name"])
                ),
                isUsefulOption(value: parameterValue, label: label),
                seenValues.insert(parameterValue).inserted
            else {
                continue
            }

            options.append(
                CourseYearOption(
                    year: parseCourseYear(label: label, parameterValue: parameterValue),
                    parameterValue: parameterValue,
                    label: label
                )
            )
        }

        return options.sorted { lhs, rhs in
            lhs.year < rhs.year
        }
    }

    private func mergeCourseYearOptions(existing: [CourseYearOption], incoming: [CourseYearOption]) -> [CourseYearOption] {
        var map: [String: CourseYearOption] = [:]
        for option in existing {
            map[option.parameterValue] = option
        }
        for option in incoming {
            map[option.parameterValue] = option
        }
        return map.values.sorted { lhs, rhs in
            lhs.year < rhs.year
        }
    }

    private func parseCourseYear(label: String, parameterValue: String) -> Int {
        if let pipeIndex = parameterValue.lastIndex(of: "|") {
            let tail = parameterValue[parameterValue.index(after: pipeIndex)...]
            if let value = Int(tail) {
                return max(value, 1)
            }
        }

        if let match = label.range(of: #"\d+"#, options: .regularExpression),
           let value = Int(label[match]) {
            return max(value, 1)
        }

        return 1
    }

    private func parseRoomNamesByCode(from rawValue: Any?) -> [String: String] {
        guard let rawDictionary = rawValue as? [String: Any] else {
            return [:]
        }

        var namesByCode: [String: String] = [:]

        for (key, value) in rawDictionary {
            guard let room = value as? [String: Any] else {
                continue
            }

            let roomName = nonEmpty(
                stringValue(room["room_name"]),
                stringValue(room["nome"]),
                stringValue(room["name"])
            ) ?? key

            namesByCode[key] = roomName

            if let roomCode = nonEmpty(
                stringValue(room["room_code"]),
                stringValue(room["CodiceAula"])
            ) {
                namesByCode[roomCode] = roomName
            }

            if let roomID = stringValue(room["id"]) {
                namesByCode[roomID] = roomName
            }
        }

        return namesByCode
    }

    private func parseFasceLabels(from rawValue: Any?) -> [String] {
        let slots = extractObjects(from: rawValue)
        return slots.compactMap { slot in
            nonEmpty(
                stringValue(slot["label"]),
                stringValue(slot["nome"]),
                stringValue(slot["value"])
            )
        }
    }

    private func extractTableRows(from rawValue: Any?) -> [String: [Any]] {
        guard let rawDictionary = rawValue as? [String: Any] else {
            return [:]
        }

        var rows: [String: [Any]] = [:]
        for (roomCode, rawSlots) in rawDictionary {
            if let slots = rawSlots as? [Any] {
                rows[roomCode] = slots
            }
        }
        return rows
    }

    private func extractEventsFromTable(tableRows: [String: [Any]]) -> [(roomCode: String?, payload: [String: Any])] {
        var collected: [(roomCode: String?, payload: [String: Any])] = []
        var seen = Set<String>()

        for (roomCode, slots) in tableRows {
            for slot in slots {
                guard let payload = slot as? [String: Any], !payload.isEmpty else {
                    continue
                }

                let from = normalizeTime(
                    nonEmpty(
                        stringValue(payload["from"]),
                        stringValue(payload["from_time"]),
                        stringValue(payload["ora_inizio"])
                    ) ?? ""
                )
                let to = normalizeTime(
                    nonEmpty(
                        stringValue(payload["to"]),
                        stringValue(payload["to_time"]),
                        stringValue(payload["ora_fine"])
                    ) ?? ""
                )
                let identifier = nonEmpty(
                    stringValue(payload["id"]),
                    stringValue(payload["identifier_cell"]),
                    stringValue(payload["name"]),
                    stringValue(payload["nome"])
                ) ?? UUID().uuidString

                let stableID = "\(roomCode)-\(identifier)-\(from)-\(to)"
                guard seen.insert(stableID).inserted else {
                    continue
                }

                collected.append((roomCode: roomCode, payload: payload))
            }
        }

        return collected
    }

    private func parseRoomLesson(
        _ payload: [String: Any],
        fallbackRoomCode: String?,
        roomNamesByCode: [String: String]
    ) -> (roomName: String, lesson: RoomLesson)? {
        guard let timeRange = parseTimeRange(from: payload) ?? parseTimeRange(payload["orario"]) else {
            return nil
        }

        let roomCode = nonEmpty(
            stringValue(payload["CodiceAula"]),
            stringValue(payload["codice_aula"]),
            stringValue(payload["room_code"]),
            fallbackRoomCode
        )

        let roomName = nonEmpty(
            stringValue(payload["NomeAula"]),
            stringValue(payload["aula"]),
            stringValue(payload["room_name"]),
            roomCode.flatMap { roomNamesByCode[$0] },
            stringValue(payload["room"]).flatMap { roomNamesByCode[$0] }
        ) ?? "Aula sconosciuta"

        let subject = nonEmpty(
            stringValue(payload["name"]),
            stringValue(payload["nome"]),
            stringValue(payload["nome_insegnamento"]),
            stringValue(payload["subject"]),
            stringValue(payload["insegnamento"])
        ) ?? "Lezione"

        let professor = nonEmpty(
            joinedString(from: payload["docenti"]),
            stringValue(payload["docente"]),
            stringValue(payload["prof"]),
            stringValue(payload["nome_docente"])
        ) ?? "Docente non disponibile"

        let courseName = nonEmpty(
            joinedString(from: payload["insegnamenti"]),
            stringValue(payload["nome_corso"]),
            stringValue(payload["corso"]),
            stringValue(payload["faculty"])
        ) ?? "Corso non specificato"

        let fromTime = normalizeTime(timeRange.start)
        let toTime = normalizeTime(timeRange.end)
        let rawID = nonEmpty(
            stringValue(payload["id"]),
            stringValue(payload["identifier_cell"])
        ) ?? UUID().uuidString
        let stableID = "\(rawID)-\(roomName)-\(fromTime)-\(toTime)-\(subject)"

        return (
            roomName: roomName,
            lesson: RoomLesson(
                id: stableID,
                subject: subject,
                professor: professor,
                courseName: courseName,
                fromTime: fromTime,
                toTime: toTime
            )
        )
    }

    private func extractFreeSlots(
        tableRows: [String: [Any]],
        fasceLabels: [String],
        roomNamesByCode: [String: String]
    ) -> [FreeRoomSlot] {
        guard !tableRows.isEmpty, !fasceLabels.isEmpty else {
            return []
        }

        var freeSlots: [FreeRoomSlot] = []

        for roomCode in tableRows.keys {
            guard let slots = tableRows[roomCode], !slots.isEmpty else {
                continue
            }

            let roomName = roomNamesByCode[roomCode] ?? "Aula \(roomCode)"
            let upperBound = min(slots.count, fasceLabels.count)
            if upperBound == 0 {
                continue
            }

            var freeStartIndex: Int?

            func appendFreeRange(start: Int, end: Int) {
                guard end > start, start < fasceLabels.count else {
                    return
                }

                let fromTime = normalizeTime(fasceLabels[start])
                let toTime: String
                if end < fasceLabels.count {
                    toTime = normalizeTime(fasceLabels[end])
                } else if let last = fasceLabels.last {
                    toTime = addMinutes(10, toTimeString: normalizeTime(last)) ?? normalizeTime(last)
                } else {
                    return
                }

                if fromTime == toTime {
                    return
                }

                freeSlots.append(
                    FreeRoomSlot(
                        id: "\(roomName)-\(fromTime)-\(toTime)",
                        roomName: roomName,
                        fromTime: fromTime,
                        toTime: toTime
                    )
                )
            }

            for index in 0..<upperBound {
                if isFreeSlot(slots[index]) {
                    if freeStartIndex == nil {
                        freeStartIndex = index
                    }
                } else if let start = freeStartIndex {
                    appendFreeRange(start: start, end: index)
                    freeStartIndex = nil
                }
            }

            if let start = freeStartIndex {
                appendFreeRange(start: start, end: upperBound)
            }
        }

        return freeSlots
    }

    private func parseLegacyFreeSlots(from rawValue: Any?) -> [FreeRoomSlot] {
        let rawSlots = extractObjects(from: rawValue)
        return rawSlots.compactMap { slot in
            guard
                let roomName = nonEmpty(
                    stringValue(slot["room_name"]),
                    stringValue(slot["aula"]),
                    stringValue(slot["room"])
                ),
                let fromTime = nonEmpty(
                    stringValue(slot["from_time"]),
                    stringValue(slot["from"]),
                    stringValue(slot["inizio"])
                ),
                let toTime = nonEmpty(
                    stringValue(slot["to_time"]),
                    stringValue(slot["to"]),
                    stringValue(slot["fine"])
                )
            else {
                return nil
            }

            return FreeRoomSlot(
                id: "\(roomName)-\(fromTime)-\(toTime)",
                roomName: roomName,
                fromTime: normalizeTime(fromTime),
                toTime: normalizeTime(toTime)
            )
        }
    }

    private func isFreeSlot(_ rawValue: Any) -> Bool {
        if rawValue is NSNull {
            return true
        }

        if let array = rawValue as? [Any] {
            return array.isEmpty
        }

        if let dictionary = rawValue as? [String: Any] {
            return dictionary.isEmpty
        }

        if let string = rawValue as? String {
            return string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        return false
    }

    private func parseJavaScriptVariable(named variableName: String, from source: String) -> Any? {
        let pattern = #"var\s+\#(NSRegularExpression.escapedPattern(for: variableName))\s*="#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let sourceRange = NSRange(source.startIndex..<source.endIndex, in: source)
        guard
            let match = regex.firstMatch(in: source, options: [], range: sourceRange),
            let assignmentRange = Range(match.range, in: source)
        else {
            return nil
        }

        var start = assignmentRange.upperBound
        while start < source.endIndex, source[start].isWhitespace {
            start = source.index(after: start)
        }

        guard start < source.endIndex else {
            return nil
        }

        let firstCharacter = source[start]
        if firstCharacter == "[" || firstCharacter == "{" {
            let closingCharacter: Character = firstCharacter == "[" ? "]" : "}"
            guard let end = findBalancedJSONEnd(
                in: source,
                startIndex: start,
                openingCharacter: firstCharacter,
                closingCharacter: closingCharacter
            ) else {
                return nil
            }

            let jsonText = String(source[start...end])
            guard let data = jsonText.data(using: .utf8) else {
                return nil
            }

            return try? JSONSerialization.jsonObject(with: data)
        }

        guard let semicolon = source[start...].firstIndex(of: ";") else {
            return nil
        }

        let rawValue = source[start..<semicolon].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = rawValue.data(using: .utf8) else {
            return nil
        }

        return try? JSONSerialization.jsonObject(with: data)
    }

    private func findBalancedJSONEnd(
        in source: String,
        startIndex: String.Index,
        openingCharacter: Character,
        closingCharacter: Character
    ) -> String.Index? {
        var depth = 0
        var index = startIndex
        var inString = false
        var isEscaped = false

        while index < source.endIndex {
            let char = source[index]

            if inString {
                if isEscaped {
                    isEscaped = false
                } else if char == "\\" {
                    isEscaped = true
                } else if char == "\"" {
                    inString = false
                }
            } else {
                if char == "\"" {
                    inString = true
                } else if char == openingCharacter {
                    depth += 1
                } else if char == closingCharacter {
                    depth -= 1
                    if depth == 0 {
                        return index
                    }
                }
            }

            index = source.index(after: index)
        }

        return nil
    }

    private func get(path: String, query: [String: String], skipWarmup: Bool = false) async throws -> Data {
        if !skipWarmup {
            await warmupSessionIfNeeded()
        }

        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw UniVRClientError.invalidURL
        }

        components.queryItems = query
            .map { URLQueryItem(name: $0.key, value: $0.value) }
            .sorted { lhs, rhs in lhs.name < rhs.name }

        guard let url = components.url else {
            throw UniVRClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("it-IT,it;q=0.9,en-US;q=0.7,en;q=0.6", forHTTPHeaderField: "Accept-Language")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw UniVRClientError.httpError
        }

        return data
    }

    private func warmupSessionIfNeeded() async {
        if didWarmupSession {
            return
        }

        _ = try? await get(
            path: "index.php",
            query: [
                "view": "easycourse",
                "_lang": "it",
                "include": "corso"
            ],
            skipWarmup: true
        )

        didWarmupSession = true
    }

    private func decodeRootObject(from data: Data) throws -> [String: Any] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UniVRClientError.invalidResponse
        }
        return root
    }

    private func decodeText(from data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        if let iso = String(data: data, encoding: .isoLatin1) {
            return iso
        }
        if let win = String(data: data, encoding: .windowsCP1252) {
            return win
        }
        return nil
    }

    private func extractObjects(from value: Any?) -> [[String: Any]] {
        if let array = value as? [[String: Any]] {
            return array
        }

        if let arrayAny = value as? [Any] {
            return arrayAny.compactMap { $0 as? [String: Any] }
        }

        if let dictionary = value as? [String: Any] {
            return dictionary.values.compactMap { $0 as? [String: Any] }
        }

        return []
    }

    private func parseTimeRange(_ rawValue: Any?) -> (start: String, end: String)? {
        if let rawString = rawValue as? String {
            let sanitized = rawString.replacingOccurrences(of: " - ", with: "-")
            let separators = ["-", "–", "—"]
            for separator in separators {
                let parts = sanitized.split(separator: Character(separator), maxSplits: 1).map {
                    String($0).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty {
                    return (parts[0], parts[1])
                }
            }
        }

        if let array = rawValue as? [Any], array.count >= 2 {
            let start = stringValue(array[0]) ?? ""
            let end = stringValue(array[1]) ?? ""
            if !start.isEmpty, !end.isEmpty {
                return (start, end)
            }
        }

        if let dictionary = rawValue as? [String: Any] {
            return parseTimeRange(from: dictionary)
        }

        return nil
    }

    private func parseTimeRange(from payload: [String: Any]) -> (start: String, end: String)? {
        let start = nonEmpty(
            stringValue(payload["ora_inizio"]),
            stringValue(payload["from_time"]),
            stringValue(payload["from"]),
            stringValue(payload["inizio"])
        )
        let end = nonEmpty(
            stringValue(payload["ora_fine"]),
            stringValue(payload["to_time"]),
            stringValue(payload["to"]),
            stringValue(payload["fine"])
        )

        if let start, let end {
            return (start, end)
        }

        return nil
    }

    private func parseDate(_ rawValue: String?) -> Date? {
        guard let rawValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines), !rawValue.isEmpty else {
            return nil
        }

        for formatter in Self.lessonDateFormatters {
            if let date = formatter.date(from: rawValue) {
                return DateHelpers.startOfDay(for: date)
            }
        }

        if let unixTimestamp = Double(rawValue) {
            return DateHelpers.startOfDay(for: Date(timeIntervalSince1970: unixTimestamp))
        }

        return nil
    }

    private func normalizeTime(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "--:--"
        }

        let components = trimmed.prefix(8).split(separator: ":", maxSplits: 1)
        if components.count == 2 {
            let hour = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let minute = String(components[1].prefix(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !hour.isEmpty, minute.count == 2,
               hour.allSatisfy(\.isNumber), minute.allSatisfy(\.isNumber) {
                return String(format: "%02d:%@", Int(hour) ?? 0, minute)
            }
        }

        return trimmed
    }

    private func addMinutes(_ minutes: Int, toTimeString time: String) -> String? {
        let components = time.split(separator: ":")
        guard components.count == 2,
              let hour = Int(components[0]),
              let minute = Int(components[1]) else {
            return nil
        }

        let total = (hour * 60) + minute + minutes
        if total < 0 {
            return nil
        }

        let newHour = (total / 60) % 24
        let newMinute = total % 60
        return String(format: "%02d:%02d", newHour, newMinute)
    }

    private func extractBuilding(from room: String) -> String? {
        if let openingBracket = room.lastIndex(of: "["),
           let closingBracket = room[openingBracket...].firstIndex(of: "]"),
           openingBracket < closingBracket {
            let building = room[room.index(after: openingBracket)..<closingBracket]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !building.isEmpty {
                return building
            }
        }

        let normalized = room.replacingOccurrences(of: "  ", with: " ")
        let separators = [" - ", " – ", ", "]

        for separator in separators {
            if let range = normalized.range(of: separator, options: .backwards) {
                let building = normalized[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                if !building.isEmpty {
                    return building
                }
            }
        }

        return nil
    }

    private func candidateAcademicYears() -> [Int] {
        let current = DateHelpers.currentAcademicYear()
        return [current, current - 1, current + 1, current - 2]
    }

    private func isUsefulOption(value: String, label: String) -> Bool {
        let normalizedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedLabel.isEmpty, !normalizedValue.isEmpty else {
            return false
        }

        let lower = normalizedLabel.lowercased()
        if lower.contains("seleziona") || lower.contains("select") || lower == "-" {
            return false
        }

        return true
    }

    private func joinedString(from rawValue: Any?) -> String? {
        if let string = nonEmpty(stringValue(rawValue)) {
            return string
        }

        guard let array = rawValue as? [Any], !array.isEmpty else {
            return nil
        }

        var pieces: [String] = []
        var seen = Set<String>()

        for item in array {
            if let string = nonEmpty(stringValue(item)) {
                if seen.insert(string).inserted {
                    pieces.append(string)
                }
                continue
            }

            if let dictionary = item as? [String: Any],
               let label = nonEmpty(
                    stringValue(dictionary["label"]),
                    stringValue(dictionary["nome"]),
                    stringValue(dictionary["name"]),
                    stringValue(dictionary["value"])
               ),
               seen.insert(label).inserted {
                pieces.append(label)
            }
        }

        guard !pieces.isEmpty else {
            return nil
        }

        return pieces.joined(separator: ", ")
    }

    private func stringValue(_ raw: Any?) -> String? {
        switch raw {
        case let value as String:
            return value
        case let value as NSNumber:
            return value.stringValue
        default:
            return nil
        }
    }

    private func nonEmpty(_ values: String?...) -> String? {
        for value in values {
            if let value {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed.decodingHTMLEntities()
                }
            }
        }
        return nil
    }

    private static let lessonDateFormatters: [DateFormatter] = {
        let formats = ["dd-MM-yyyy", "yyyy-MM-dd", "dd/MM/yyyy", "yyyy/MM/dd", "dd.MM.yyyy"]
        return formats.map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            formatter.timeZone = TimeZone(identifier: "Europe/Rome")
            return formatter
        }
    }()
}

private struct CourseYearOption {
    let year: Int
    let parameterValue: String
    let label: String
}

enum UniVRClientError: LocalizedError {
    case invalidURL
    case invalidResponse
    case invalidEncoding
    case httpError
    case noData

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "URL non valido per la richiesta UniVR."
        case .invalidResponse:
            return "Risposta non valida dal server UniVR."
        case .invalidEncoding:
            return "Impossibile leggere la risposta testuale del server UniVR."
        case .httpError:
            return "Errore HTTP durante la comunicazione con UniVR."
        case .noData:
            return "Nessun dato restituito dal server UniVR."
        }
    }
}

private extension String {
    func decodingHTMLEntities() -> String {
        let entities: [String: String] = [
            "&amp;": "&",
            "&quot;": "\"",
            "&#39;": "'",
            "&apos;": "'",
            "&lt;": "<",
            "&gt;": ">",
            "&nbsp;": " "
        ]

        var result = self
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        return result
    }
}
