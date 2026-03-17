import SwiftUI

// MARK: - Subject color helpers

let subjectColorPalette: [Color] = [
    Color(hex: "6366F1"),
    Color(hex: "EC4899"),
    Color(hex: "F59E0B"),
    Color(hex: "10B981"),
    Color(hex: "3B82F6"),
    Color(hex: "EF4444"),
    Color(hex: "8B5CF6"),
    Color(hex: "06B6D4"),
]

func stableHash(_ string: String) -> Int {
    var hash: UInt64 = 5381
    for byte in string.utf8 {
        hash = ((hash &<< 5) &+ hash) &+ UInt64(byte)
    }
    return Int(hash & 0x7FFFFFFFFFFFFFFF)
}

func subjectColor(for title: String) -> Color {
    subjectColorPalette[stableHash(title) % subjectColorPalette.count]
}

// MARK: - Lesson Card

struct LessonCard: View {
    let lesson: Lesson
    var isActive: Bool = false
    var attendanceStatus: AttendanceStatus = .unmarked
    var onTap: (() -> Void)? = nil
    var onAttendanceTap: (() -> Void)? = nil

    private var accentColor: Color { subjectColor(for: lesson.title) }

    private var attendanceDotColor: Color? {
        switch attendanceStatus {
        case .attended: return Color(hex: "10B981")
        case .skipped:  return Color(hex: "EF4444")
        case .unmarked: return nil
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(isActive ? Color.uiAccent : accentColor)
                .frame(width: 3)

            VStack(alignment: .trailing, spacing: 1) {
                Text(lesson.startTime)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isActive ? Color.uiAccent : Color.uiTextSecondary)
                Text(lesson.endTime)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.uiTextMuted)
            }
            .frame(width: 48)
            .padding(.leading, 12)
            .padding(.vertical, 13)

            VStack(alignment: .leading, spacing: 3) {
                Text(lesson.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.uiTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !lesson.room.isEmpty {
                    Text(lesson.room)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.uiTextMuted)
                        .lineLimit(1)
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 14)
            .padding(.vertical, 13)

            if let dotColor = attendanceDotColor {
                Circle()
                    .fill(dotColor)
                    .frame(width: 7, height: 7)
                    .padding(.trailing, 12)
            }
        }
        .background(isActive ? Color.uiAccent.opacity(0.04) : Color.clear)
        .sensoryFeedback(.impact(flexibility: .rigid), trigger: isActive) { _, new in new }
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
        .onLongPressGesture { onAttendanceTap?() }
    }
}

// MARK: - Work Shift Card

struct WorkShiftCard: View {
    let shift: WorkShift

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.uiAccentSecondary.opacity(0.8))
                .frame(width: 3)

            HStack(spacing: 0) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(shift.startTimeString)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.uiAccentSecondary.opacity(0.85))
                    Text(shift.endTimeString)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.uiTextMuted)
                }
                .frame(width: 54)
                .padding(.leading, 14)

                Rectangle()
                    .fill(Color.uiStroke)
                    .frame(width: 0.5)
                    .padding(.vertical, 12)

                HStack(spacing: 8) {
                    Image(systemName: "briefcase.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.uiAccentSecondary)
                    Text("Work shift")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.uiTextPrimary)
                }
                .padding(.leading, 14)
            }
        }
        .padding(.vertical, 12)
    }
}
