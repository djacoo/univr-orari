import SwiftUI

// MARK: - Grid View

struct WeeklyGridView: View {
    let weekDays: [Date]
    let lessonsGroupedByDay: [(date: Date, lessons: [Lesson])]
    var workShiftForDay: (Date) -> WorkShift?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(weekDays.enumerated()), id: \.offset) { index, day in
                DayGridColumn(date: day, lessons: lessonsForDay(day), shift: workShiftForDay(day))
                if index < weekDays.count - 1 {
                    Divider()
                        .padding(.vertical, 8)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func lessonsForDay(_ date: Date) -> [Lesson] {
        let start = Calendar.current.startOfDay(for: date)
        return lessonsGroupedByDay.first(where: {
            Calendar.current.startOfDay(for: $0.date) == start
        })?.lessons ?? []
    }
}

struct DayGridColumn: View {
    let date: Date
    let lessons: [Lesson]
    var shift: WorkShift? = nil

    private var isToday: Bool { Calendar.current.isDateInToday(date) }

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.setLocalizedDateFormatFromTemplate("EEE")
        return f
    }()

    var body: some View {
        VStack(spacing: 8) {
            VStack(spacing: 3) {
                Text(Self.weekdayFormatter.string(from: date).uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isToday ? Color.uiAccent : Color.uiTextMuted)
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(isToday ? .white : Color.uiTextPrimary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(isToday ? Color.uiAccent : Color.clear))
            }

            if let shift {
                HStack(spacing: 4) {
                    Image(systemName: "briefcase.fill")
                        .font(.system(size: 7, weight: .semibold))
                    Text("\(shift.startTimeString)–\(shift.endTimeString)")
                        .font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(Color.uiAccentSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.uiAccentSecondary.opacity(0.12))
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if lessons.isEmpty && shift == nil {
                Text("–")
                    .font(.caption)
                    .foregroundStyle(Color.uiTextMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            } else if !lessons.isEmpty {
                VStack(spacing: 6) {
                    ForEach(lessons) { lesson in
                        GridLessonPill(lesson: lesson)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
    }
}

struct GridLessonPill: View {
    let lesson: Lesson
    private var accentColor: Color { subjectColor(for: lesson.title) }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(accentColor.opacity(0.75))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(lesson.startTime)–\(lesson.endTime)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(accentColor)

                Text(lesson.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.uiTextPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if !lesson.room.isEmpty {
                    Text(lesson.room)
                        .font(.system(size: 9))
                        .foregroundStyle(Color.uiTextSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.uiSurfaceInput)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
