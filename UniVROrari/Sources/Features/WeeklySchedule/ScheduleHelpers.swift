import SwiftUI

// MARK: - Shimmer

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [Color.clear, Color.uiTextMuted.opacity(0.08), Color.clear],
                        startPoint: .init(x: phase, y: 0),
                        endPoint: .init(x: phase + 0.6, y: 0)
                    )
                    .frame(width: geo.size.width, height: geo.size.height)
                }
                .allowsHitTesting(false)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                    phase = 1.4
                }
            }
    }
}

// MARK: - Day Skeleton

struct DaySkeletonView: View {
    let index: Int

    private let rowCounts = [2, 3, 1, 2, 1]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.uiStroke)
                        .frame(width: 22, height: 7)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.uiSurface)
                        .frame(width: 18, height: 20)
                }
                .frame(width: 36, alignment: .leading)
                Rectangle().fill(Color.uiStroke).frame(height: 1)
            }
            .padding(.horizontal, 20)
            .padding(.top, index == 0 ? 16 : 28)
            .padding(.bottom, 10)

            ForEach(0..<rowCounts[index % rowCounts.count], id: \.self) { row in
                if row > 0 {
                    Rectangle().fill(Color.uiStroke).frame(height: 0.5).padding(.horizontal, 20)
                }
                HStack(spacing: 0) {
                    Rectangle().fill(Color.uiStroke.opacity(0.6)).frame(width: 3)
                    VStack(alignment: .trailing, spacing: 4) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.uiSurface).frame(width: 34, height: 10)
                        RoundedRectangle(cornerRadius: 3).fill(Color.uiSurface).frame(width: 28, height: 8)
                    }
                    .frame(width: 52).padding(.leading, 14).padding(.vertical, 14)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.uiSurface).frame(maxWidth: .infinity).frame(height: 12)
                        RoundedRectangle(cornerRadius: 3).fill(Color.uiSurface).frame(width: 80, height: 9)
                    }
                    .padding(.leading, 14).padding(.trailing, 20).padding(.vertical, 14)
                }
                .modifier(ShimmerModifier())
                .padding(.horizontal, 20)
            }
        }
    }
}

// MARK: - Lesson Detail Sheet

struct LessonDetailSheet: View {
    let lesson: Lesson
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Rectangle()
                        .fill(subjectColor(for: lesson.title))
                        .frame(height: 4)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                        .padding(.horizontal, 24)
                        .padding(.top, 24)
                        .padding(.bottom, 20)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(lesson.title)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Color.uiTextPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)

                    VStack(spacing: 0) {
                        detailRow(icon: "clock", label: "Time", value: "\(lesson.startTime) – \(lesson.endTime)")
                        Divider().padding(.leading, 56)
                        if !lesson.room.isEmpty {
                            detailRow(icon: "mappin", label: "Room", value: lesson.room)
                            Divider().padding(.leading, 56)
                        }
                        if !lesson.professor.isEmpty {
                            detailRow(icon: "person", label: "Professor", value: lesson.professor)
                            Divider().padding(.leading, 56)
                        }
                        if !lesson.building.isEmpty {
                            detailRow(icon: "building.2", label: "Building", value: lesson.building)
                        }
                    }
                    .background(Color.uiSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 40)
            }
            .navigationTitle("Lesson Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.body.weight(.semibold))
                        .tint(Color.uiAccent)
                }
            }
        }
    }

    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(Color.uiAccent)
                .frame(width: 20)
                .padding(.leading, 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.uiTextMuted)
                Text(value)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.uiTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.vertical, 14)
        .padding(.trailing, 20)
    }
}
