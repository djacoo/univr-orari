import Foundation
import UserNotifications
import FoundationModels

@MainActor
final class NotificationScheduler {
    var notificationsEnabled: Bool = false
    var notificationLeadMinutes: Int = 15
    var hiddenSubjects: Set<String> = []

    func requestPermission() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
    }

    func schedule(for lessons: [Lesson]) {
        guard notificationsEnabled else { return }
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        var romeCal = Calendar(identifier: .gregorian)
        romeCal.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current
        let now = Date()
        let visibleLessons = hiddenSubjects.isEmpty ? lessons : lessons.filter { !hiddenSubjects.contains($0.title) }
        for lesson in visibleLessons {
            let startMins = lesson.startTime.minutesSinceMidnight - notificationLeadMinutes
            guard startMins >= 0 else { continue }
            let dayComps = romeCal.dateComponents([.year, .month, .day], from: lesson.date)
            var fireComps = DateComponents()
            fireComps.timeZone = romeCal.timeZone
            fireComps.year    = dayComps.year
            fireComps.month   = dayComps.month
            fireComps.day     = dayComps.day
            fireComps.hour    = startMins / 60
            fireComps.minute  = startMins % 60
            guard let fireDate = romeCal.date(from: fireComps), fireDate > now else { continue }
            let content = UNMutableNotificationContent()
            content.title = lesson.title
            let bodyParts = [lesson.startTime, lesson.room, lesson.professor].filter { !$0.isEmpty }
            content.body = bodyParts.joined(separator: " · ")
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            let trigger = UNCalendarNotificationTrigger(dateMatching: fireComps, repeats: false)
            let request = UNNotificationRequest(
                identifier: "lesson:\(lesson.id):\(notificationLeadMinutes)",
                content: content,
                trigger: trigger
            )
            center.add(request, withCompletionHandler: nil)
        }
    }

    @available(iOS 26.0, *)
    func scheduleWithAI(for lessons: [Lesson]) async {
        guard notificationsEnabled else { return }
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        var romeCal = Calendar(identifier: .gregorian)
        romeCal.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current
        let now = Date()
        let visibleLessons = hiddenSubjects.isEmpty ? lessons : lessons.filter { !hiddenSubjects.contains($0.title) }

        var upcoming: [(lesson: Lesson, prev: Lesson?, fireComps: DateComponents)] = []
        for (i, lesson) in visibleLessons.enumerated() {
            let startMins = lesson.startTime.minutesSinceMidnight - notificationLeadMinutes
            guard startMins >= 0 else { continue }
            let dayComps = romeCal.dateComponents([.year, .month, .day], from: lesson.date)
            var fireComps = DateComponents()
            fireComps.timeZone = romeCal.timeZone
            fireComps.year = dayComps.year
            fireComps.month = dayComps.month
            fireComps.day = dayComps.day
            fireComps.hour = startMins / 60
            fireComps.minute = startMins % 60
            guard let fireDate = romeCal.date(from: fireComps), fireDate > now else { continue }
            let prev = i > 0 ? visibleLessons[i - 1] : nil
            upcoming.append((lesson: lesson, prev: prev, fireComps: fireComps))
        }

        var bodies: [String: String] = [:]
        for item in upcoming {
            let body = await AINotificationService.generateBody(
                lesson: item.lesson,
                precedingLesson: item.prev
            )
            bodies[item.lesson.id] = body
        }

        for item in upcoming {
            let content = UNMutableNotificationContent()
            content.title = item.lesson.title
            content.body = bodies[item.lesson.id] ?? {
                [item.lesson.startTime, item.lesson.room, item.lesson.professor]
                    .filter { !$0.isEmpty }.joined(separator: " · ")
            }()
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            let trigger = UNCalendarNotificationTrigger(dateMatching: item.fireComps, repeats: false)
            let request = UNNotificationRequest(
                identifier: "lesson:\(item.lesson.id):\(notificationLeadMinutes)",
                content: content,
                trigger: trigger
            )
            center.add(request, withCompletionHandler: nil)
        }
    }
}
