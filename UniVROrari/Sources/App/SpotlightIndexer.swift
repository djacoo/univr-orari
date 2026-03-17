import Foundation
import CoreSpotlight
import UniformTypeIdentifiers

enum SpotlightIndexer {
    static func indexLessons(_ lessons: [Lesson]) {
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
}
