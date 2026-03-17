import SwiftUI

// MARK: - Shared helpers

let chipWeekdayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US")
    f.setLocalizedDateFormatFromTemplate("EEE")
    return f
}()

// MARK: - Day Card

struct DayCardView: View {
    let index: Int
    let date: Date
    let now: Date
    let dayLessons: [Lesson]
    let dayShift: WorkShift?
    var onLessonTap: (Lesson) -> Void = { _ in }

    @EnvironmentObject private var attendanceStore: AttendanceStore

    private var isToday: Bool { Calendar.current.isDateInToday(date) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            dayHeaderView
            cardBody
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var dayHeaderView: some View {
        let day = Calendar.current.component(.day, from: date)
        let weekday = String(chipWeekdayFormatter.string(from: date).prefix(3)).uppercased()

        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: -3) {
                Text(weekday)
                    .font(.system(size: 9, weight: .black))
                    .tracking(2)
                    .foregroundStyle(isToday ? Color.uiAccent : Color.uiTextMuted)
                Text("\(day)")
                    .font(.system(size: 26, weight: .black))
                    .foregroundStyle(isToday ? Color.uiAccent : Color.uiTextPrimary)
            }
            .frame(width: 36, alignment: .leading)

            Rectangle()
                .fill(isToday ? Color.uiAccent.opacity(0.5) : Color.uiStroke)
                .frame(height: 1)

            if isToday {
                Text("TODAY")
                    .font(.system(size: 9, weight: .black))
                    .tracking(1.5)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.uiAccent))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, index == 0 ? 16 : 28)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var cardBody: some View {
        if let shift = dayShift {
            WorkShiftCard(shift: shift).padding(.horizontal, 20)
            if !dayLessons.isEmpty {
                Rectangle().fill(Color.uiStroke).frame(height: 0.5).padding(.horizontal, 20)
            }
        }
        if !dayLessons.isEmpty {
            if isToday {
                nowLessonsView
            } else {
                ForEach(Array(dayLessons.indices), id: \.self) { idx in
                    if idx > 0 {
                        Rectangle().fill(Color.uiStroke).frame(height: 0.5).padding(.horizontal, 20)
                    }
                    LessonCard(
                        lesson: dayLessons[idx],
                        isActive: false,
                        attendanceStatus: attendanceStore.status(for: dayLessons[idx].id, date: dayLessons[idx].date),
                        onTap: { onLessonTap(dayLessons[idx]) },
                        onAttendanceTap: { _ = attendanceStore.toggle(for: dayLessons[idx].id, date: dayLessons[idx].date) }
                    )
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    @ViewBuilder
    private var nowLessonsView: some View {
        let cal = Calendar.current
        let h = cal.component(.hour, from: now)
        let m = cal.component(.minute, from: now)
        let currentMins = h * 60 + m
        let insertIdx = dayLessons.firstIndex(where: { $0.startTime.minutesSinceMidnight > currentMins }) ?? dayLessons.count
        let nowLabel = String(format: "%02d:%02d", h, m)

        ForEach(Array(dayLessons.enumerated()), id: \.element.id) { idx, lesson in
            if idx == insertIdx {
                NowIndicatorView(label: nowLabel).padding(.horizontal, 20)
            } else if idx > 0 {
                Rectangle().fill(Color.uiStroke).frame(height: 0.5).padding(.horizontal, 20)
            }
            LessonCard(
                lesson: lesson,
                isActive: isActive(lesson),
                attendanceStatus: attendanceStore.status(for: lesson.id, date: lesson.date),
                onTap: { onLessonTap(lesson) },
                onAttendanceTap: { _ = attendanceStore.toggle(for: lesson.id, date: lesson.date) }
            )
            .padding(.horizontal, 20)
        }
        if insertIdx == dayLessons.count {
            NowIndicatorView(label: nowLabel).padding(.horizontal, 20)
        }
    }

    private func isActive(_ lesson: Lesson) -> Bool {
        guard isToday else { return false }
        let cal = Calendar.current
        let currentMins = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        return lesson.startTime.minutesSinceMidnight <= currentMins
            && currentMins < lesson.endTime.minutesSinceMidnight
    }
}

// MARK: - Now Indicator

struct NowIndicatorView: View {
    let label: String
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.uiAccent)
                .frame(width: 7, height: 7)
                .opacity(pulsing ? 0.5 : 1.0)
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.uiAccent)
            Rectangle()
                .fill(Color.uiAccent)
                .frame(height: 1.5)
                .opacity(pulsing ? 0.35 : 1.0)
        }
        .padding(.vertical, 6)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
    }
}

// MARK: - Timeline Now Row

struct TimelineNowRow: View {
    let labelWidth: CGFloat
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.uiAccent)
                    .frame(width: 7, height: 7)
                    .opacity(pulsing ? 0.5 : 1.0)
                Text("Now")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.uiAccent)
            }
            .frame(width: labelWidth, alignment: .leading)
            Rectangle()
                .fill(Color.uiAccent)
                .frame(height: 1.5)
                .opacity(pulsing ? 0.35 : 1.0)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
    }
}
