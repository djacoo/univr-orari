import Foundation
import ActivityKit
import UIKit

@MainActor
final class LiveActivityManager {
    private var lectureActivity: Activity<LectureActivityAttributes>?
    private var liveActivityTimerTask: Task<Void, Never>?

    var notificationLeadMinutes: Int = 15

    func refresh(lessonsGroupedByDay: [(date: Date, lessons: [Lesson])], courseName: String, isDark: Bool? = nil) {
        if lectureActivity == nil {
            lectureActivity = Activity<LectureActivityAttributes>.activities.first
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let cal = Calendar.current
        let now = Date()
        guard cal.isDateInToday(now) else { end(); return }

        let dark = isDark ?? (UIScreen.main.traitCollection.userInterfaceStyle == .dark)
        let currentMins = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        let todayLessons = lessonsGroupedByDay.first(where: { cal.isDateInToday($0.date) })?.lessons ?? []
        let state = computeActivityState(now: now, currentMins: currentMins, todayLessons: todayLessons, isDark: dark)

        if let activity = lectureActivity {
            Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
        } else {
            let attrs = LectureActivityAttributes(courseName: courseName)
            lectureActivity = try? Activity<LectureActivityAttributes>.request(
                attributes: attrs,
                content: ActivityContent(state: state, staleDate: nil)
            )
        }
        scheduleLiveActivityTimer(lessonsGroupedByDay: lessonsGroupedByDay, courseName: courseName, todayLessons: todayLessons, currentMins: currentMins)
    }

    func end() {
        liveActivityTimerTask?.cancel()
        liveActivityTimerTask = nil
        guard let activity = lectureActivity else { return }
        lectureActivity = nil
        Task { await activity.end(ActivityContent(state: activity.content.state, staleDate: nil), dismissalPolicy: .immediate) }
    }

    private func computeActivityState(
        now: Date,
        currentMins: Int,
        todayLessons: [Lesson],
        isDark: Bool
    ) -> LectureActivityAttributes.ContentState {
        var romeCal = Calendar(identifier: .gregorian)
        romeCal.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current

        if let lesson = todayLessons.first(where: {
            $0.startTime.minutesSinceMidnight <= currentMins && currentMins < $0.endTime.minutesSinceMidnight
        }) {
            return makeActivityState(phase: .live, lesson: lesson, romeCal: romeCal, now: now, isDark: isDark)
        }

        if let lesson = todayLessons.first(where: {
            let s = $0.startTime.minutesSinceMidnight
            return s > currentMins && s - currentMins <= notificationLeadMinutes
        }) {
            return makeActivityState(phase: .upcoming, lesson: lesson, romeCal: romeCal, now: now, isDark: isDark)
        }

        if let lesson = todayLessons.first(where: { $0.startTime.minutesSinceMidnight > currentMins }) {
            return makeActivityState(phase: .idle, lesson: lesson, romeCal: romeCal, now: now, isDark: isDark)
        }

        return LectureActivityAttributes.ContentState(
            phase: .allDone,
            lessonTitle: "", room: "", startTime: "", endTime: "",
            startDate: now, endDate: now,
            isDarkMode: isDark
        )
    }

    private func makeActivityState(
        phase: LectureActivityAttributes.ContentState.Phase,
        lesson: Lesson,
        romeCal: Calendar,
        now: Date,
        isDark: Bool
    ) -> LectureActivityAttributes.ContentState {
        let startMins = lesson.startTime.minutesSinceMidnight
        var startComps = romeCal.dateComponents([.year, .month, .day], from: lesson.date)
        startComps.hour = startMins / 60; startComps.minute = startMins % 60
        startComps.timeZone = romeCal.timeZone
        let startDate = romeCal.date(from: startComps) ?? now

        let endMins = lesson.endTime.minutesSinceMidnight
        var endComps = romeCal.dateComponents([.year, .month, .day], from: lesson.date)
        endComps.hour = endMins / 60; endComps.minute = endMins % 60
        endComps.timeZone = romeCal.timeZone
        let endDate = romeCal.date(from: endComps) ?? now.addingTimeInterval(3600)

        return LectureActivityAttributes.ContentState(
            phase: phase,
            lessonTitle: lesson.title,
            room: lesson.room,
            startTime: lesson.startTime,
            endTime: lesson.endTime,
            startDate: startDate,
            endDate: endDate,
            isDarkMode: isDark
        )
    }

    private func scheduleLiveActivityTimer(
        lessonsGroupedByDay: [(date: Date, lessons: [Lesson])],
        courseName: String,
        todayLessons: [Lesson],
        currentMins: Int
    ) {
        liveActivityTimerTask?.cancel()

        var romeCal = Calendar(identifier: .gregorian)
        romeCal.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current
        let now = Date()
        var transitionDates: [Date] = []

        for lesson in todayLessons {
            let startMins = lesson.startTime.minutesSinceMidnight
            let endMins   = lesson.endTime.minutesSinceMidnight
            let leadMins  = startMins - notificationLeadMinutes

            for mins in [leadMins, startMins, endMins] where mins > currentMins {
                var comps = romeCal.dateComponents([.year, .month, .day], from: lesson.date)
                comps.hour = mins / 60; comps.minute = mins % 60; comps.second = 1
                comps.timeZone = romeCal.timeZone
                if let d = romeCal.date(from: comps), d > now { transitionDates.append(d) }
            }
        }

        guard let next = transitionDates.min() else { return }
        let delay = max(next.timeIntervalSinceNow, 1)

        liveActivityTimerTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard let self else { return }
                self.refresh(lessonsGroupedByDay: lessonsGroupedByDay, courseName: courseName)
            } catch {}
        }
    }
}
