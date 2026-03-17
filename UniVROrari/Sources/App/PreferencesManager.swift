import Foundation

@MainActor
final class PreferencesManager {
    private let localStore: LocalDataStore
    private var persistTask: Task<Void, Never>?

    init(localStore: LocalDataStore) {
        self.localStore = localStore
    }

    func loadPreferences() -> StoredPreferences {
        localStore.loadPreferences()
    }

    func persist(preferences: StoredPreferences) {
        localStore.savePreferences(preferences)
    }

    func schedulePersist(preferences: @escaping @Sendable () -> StoredPreferences) {
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled, let self else { return }
            self.persist(preferences: preferences())
        }
    }

    func saveSubjectFilter(courseID: String, courseYear: Int, knownSubjects: [String], hiddenSubjects: [String]) {
        let key = "\(courseID):\(courseYear)"
        localStore.saveSubjectFilter(
            SubjectFilterEntry(knownSubjects: knownSubjects, hiddenSubjects: hiddenSubjects, savedAt: Date()),
            forKey: key
        )
    }

    func loadSubjectFilter(courseID: String, courseYear: Int) -> SubjectFilterEntry? {
        let key = "\(courseID):\(courseYear)"
        return localStore.loadSubjectFilter(forKey: key)
    }
}
