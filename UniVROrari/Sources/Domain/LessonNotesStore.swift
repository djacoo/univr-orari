import Foundation

@MainActor
final class LessonNotesStore: ObservableObject {
    private static let key = "univr.lessonNotes"
    @Published private var notes: [String: String] = [:]

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            notes = decoded
        }
    }

    func note(for lessonID: String, date: Date) -> String? {
        notes[makeKey(lessonID: lessonID, date: date)]
    }

    func setNote(_ text: String?, for lessonID: String, date: Date) {
        let key = makeKey(lessonID: lessonID, date: date)
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            notes[key] = text
        } else {
            notes.removeValue(forKey: key)
        }
        save()
    }

    func hasNote(for lessonID: String, date: Date) -> Bool {
        note(for: lessonID, date: date) != nil
    }

    private func makeKey(lessonID: String, date: Date) -> String {
        "\(lessonID):\(DateHelpers.apiDateFormatter.string(from: date))"
    }

    private func save() {
        if let data = try? JSONEncoder().encode(notes) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
