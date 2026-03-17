import Foundation
import ActivityKit

struct LectureActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable, Hashable {
            case live
            case upcoming
            case idle
            case allDone
        }
        let phase: Phase
        let lessonTitle: String
        let room: String
        let startTime: String
        let endTime: String
        let startDate: Date
        let endDate: Date
        let isDarkMode: Bool
    }
    let courseName: String
}
