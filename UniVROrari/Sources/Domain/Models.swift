import Foundation

struct Faculty: Identifiable, Hashable, Codable {
    let id: String
    let name: String
}

struct StudyCourse: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let facultyName: String
    let maxYear: Int

    init(id: String, name: String, facultyName: String, maxYear: Int = 3) {
        self.id = id
        self.name = name
        self.facultyName = facultyName
        self.maxYear = maxYear
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedName = try container.decode(String.self, forKey: .name)
        id = try container.decode(String.self, forKey: .id)
        name = decodedName
        facultyName = try container.decode(String.self, forKey: .facultyName)
        maxYear = try container.decodeIfPresent(Int.self, forKey: .maxYear)
            ?? StudyCourse.detectMaxYear(from: decodedName)
    }

    static func detectMaxYear(from name: String) -> Int {
        let lower = name.lowercased()
        if lower.contains("magistrale") { return 2 }
        if lower.contains("ciclo unico") { return 5 }
        return 3
    }
}

struct Building: Identifiable, Hashable, Codable {
    let id: String
    let name: String
}

struct Lesson: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let professor: String
    let room: String
    let building: String
    let date: Date
    let startTime: String
    let endTime: String
}

struct RoomLesson: Identifiable, Hashable, Codable {
    let id: String
    let subject: String
    let professor: String
    let courseName: String
    let fromTime: String
    let toTime: String
}

struct RoomAgenda: Identifiable, Hashable, Codable {
    let id: String
    let roomName: String
    let lessons: [RoomLesson]
}

struct FreeRoomSlot: Identifiable, Hashable, Codable {
    let id: String
    let roomName: String
    let fromTime: String
    let toTime: String
}

struct WorkShift: Codable {
    var weekday: Int     // 0 = Monday … 6 = Sunday
    var isEnabled: Bool
    var startHour: Int
    var startMinute: Int
    var endHour: Int
    var endMinute: Int

    var weekdayName: String { WorkShift.weekdayNames[weekday] }
    var startTimeString: String { String(format: "%02d:%02d", startHour, startMinute) }
    var endTimeString: String { String(format: "%02d:%02d", endHour, endMinute) }

    private static let weekdayNames = [
        "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"
    ]

    static let defaults: [WorkShift] = (0..<7).map { day in
        WorkShift(weekday: day, isEnabled: false, startHour: 9, startMinute: 0, endHour: 17, endMinute: 0)
    }
}
