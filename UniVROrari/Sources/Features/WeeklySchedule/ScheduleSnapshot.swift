import SwiftUI

struct ScheduleSnapshotView: View {
    let weekLabel: String
    let courseName: String
    let days: [(date: Date, lessons: [Lesson])]

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "EEEE d MMM"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(courseName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(weekLabel)
                        .font(.system(size: 20, weight: .bold))
                }
                Spacer()
                Text("UniVR")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
            }

            ForEach(days, id: \.date) { date, lessons in
                VStack(alignment: .leading, spacing: 6) {
                    Text(Self.dayFormatter.string(from: date).uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                    ForEach(lessons) { lesson in
                        HStack(spacing: 8) {
                            Text("\(lesson.startTime)-\(lesson.endTime)")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(lesson.title)
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            if !lesson.room.isEmpty {
                                Text(lesson.room)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(24)
        .background(.background)
        .frame(width: 390)
    }
}

@MainActor
enum ScheduleImageRenderer {
    static func render(
        weekLabel: String,
        courseName: String,
        days: [(date: Date, lessons: [Lesson])]
    ) -> UIImage? {
        let view = ScheduleSnapshotView(
            weekLabel: weekLabel,
            courseName: courseName,
            days: days
        )
        let renderer = ImageRenderer(content: view)
        renderer.scale = UIScreen.main.scale
        return renderer.uiImage
    }
}
