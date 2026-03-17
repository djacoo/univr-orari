import Foundation

enum ICSExporter {
    static func generateICS(lessons: [Lesson], courseName: String) -> String {
        var lines = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//UniVROrari//EN",
            "CALSCALE:GREGORIAN",
            "X-WR-CALNAME:\(courseName)"
        ]

        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyyMMdd"
        fmt.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current

        for lesson in lessons {
            let dateStr = fmt.string(from: lesson.date)
            let startTime = lesson.startTime.replacingOccurrences(of: ":", with: "")
            let endTime = lesson.endTime.replacingOccurrences(of: ":", with: "")

            lines.append("BEGIN:VEVENT")
            lines.append("DTSTART;TZID=Europe/Rome:\(dateStr)T\(startTime)00")
            lines.append("DTEND;TZID=Europe/Rome:\(dateStr)T\(endTime)00")
            lines.append("SUMMARY:\(escapeICS(lesson.title))")
            if !lesson.room.isEmpty {
                lines.append("LOCATION:\(escapeICS(lesson.room))")
            }
            if !lesson.professor.isEmpty {
                lines.append("DESCRIPTION:\(escapeICS(lesson.professor))")
            }
            lines.append("UID:\(lesson.id)-\(dateStr)@univr.orari")
            lines.append("END:VEVENT")
        }

        lines.append("END:VCALENDAR")
        return lines.joined(separator: "\r\n")
    }

    static func writeToTempFile(ics: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("schedule.ics")
        do {
            try ics.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private static func escapeICS(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
