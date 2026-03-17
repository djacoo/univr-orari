import Foundation

struct ScheduleDiff {
    let added: [Lesson]
    let removed: [Lesson]
    let changed: [(old: Lesson, new: Lesson)]

    var isEmpty: Bool { added.isEmpty && removed.isEmpty && changed.isEmpty }

    var summary: String {
        var parts: [String] = []
        if !added.isEmpty { parts.append("\(added.count) added") }
        if !removed.isEmpty { parts.append("\(removed.count) removed") }
        if !changed.isEmpty { parts.append("\(changed.count) changed") }
        return parts.joined(separator: ", ")
    }

    static func compute(old: [Lesson], new: [Lesson]) -> ScheduleDiff {
        let fmt = DateHelpers.apiDateFormatter
        let oldByKey = Dictionary(grouping: old, by: { "\($0.id):\(fmt.string(from: $0.date))" })
        let newByKey = Dictionary(grouping: new, by: { "\($0.id):\(fmt.string(from: $0.date))" })

        let oldKeys = Set(oldByKey.keys)
        let newKeys = Set(newByKey.keys)

        let added = newKeys.subtracting(oldKeys).flatMap { newByKey[$0] ?? [] }
        let removed = oldKeys.subtracting(newKeys).flatMap { oldByKey[$0] ?? [] }

        var changed: [(Lesson, Lesson)] = []
        for key in oldKeys.intersection(newKeys) {
            guard let o = oldByKey[key]?.first, let n = newByKey[key]?.first else { continue }
            if o.room != n.room || o.startTime != n.startTime || o.endTime != n.endTime || o.professor != n.professor {
                changed.append((o, n))
            }
        }

        return ScheduleDiff(added: added, removed: removed, changed: changed)
    }
}
