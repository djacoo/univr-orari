import Foundation

enum AttendanceStatus: String, Codable {
    case attended
    case skipped
    case unmarked
}

@MainActor
final class AttendanceStore: ObservableObject {
    private static let key = "univr.attendance"
    @Published private var records: [String: String] = [:]

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            records = decoded
        }
    }

    func status(for lessonID: String, date: Date) -> AttendanceStatus {
        let key = makeKey(lessonID: lessonID, date: date)
        guard let raw = records[key] else { return .unmarked }
        return AttendanceStatus(rawValue: raw) ?? .unmarked
    }

    func setStatus(_ status: AttendanceStatus, for lessonID: String, date: Date) {
        let key = makeKey(lessonID: lessonID, date: date)
        if status == .unmarked {
            records.removeValue(forKey: key)
        } else {
            records[key] = status.rawValue
        }
        save()
    }

    func toggle(for lessonID: String, date: Date) -> AttendanceStatus {
        let current = status(for: lessonID, date: date)
        let next: AttendanceStatus = switch current {
        case .unmarked: .attended
        case .attended: .skipped
        case .skipped: .unmarked
        }
        setStatus(next, for: lessonID, date: date)
        return next
    }

    func attendanceRate(for subjectTitle: String, lessons: [Lesson]) -> Double? {
        let relevant = lessons.filter { $0.title == subjectTitle }
        guard !relevant.isEmpty else { return nil }
        let attended = relevant.filter { status(for: $0.id, date: $0.date) == .attended }.count
        let total = relevant.filter { status(for: $0.id, date: $0.date) != .unmarked }.count
        guard total > 0 else { return nil }
        return Double(attended) / Double(total)
    }

    private func makeKey(lessonID: String, date: Date) -> String {
        "\(lessonID):\(DateHelpers.apiDateFormatter.string(from: date))"
    }

    private func save() {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
