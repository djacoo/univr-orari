import SwiftUI

struct WeeklyScheduleView: View {
    @ObservedObject var model: AppModel
    let onEditProfile: () -> Void

    private enum WeekViewMode { case list, grid }
    @State private var viewMode: WeekViewMode = .list

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                profileHeaderCard
                weekNavigationCard
                lessonStateSection
                if viewMode == .list {
                    lessonDayCards
                } else {
                    lessonGridCard
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .navigationTitle("Calendario")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                HStack(spacing: 2) {
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { viewMode = .list }
                    } label: {
                        Image(systemName: "list.bullet")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(viewMode == .list ? Color.uiAccent : Color.clear)
                            )
                            .foregroundStyle(viewMode == .list ? .white : Color.uiTextSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Vista lista")
                    .accessibilityAddTraits(viewMode == .list ? .isSelected : [])

                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { viewMode = .grid }
                    } label: {
                        Image(systemName: "tablecells")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(viewMode == .grid ? Color.uiAccent : Color.clear)
                            )
                            .foregroundStyle(viewMode == .grid ? .white : Color.uiTextSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Vista griglia")
                    .accessibilityAddTraits(viewMode == .grid ? .isSelected : [])
                }
                .padding(3)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.uiSurfaceInput)
                )
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    onEditProfile()
                } label: {
                    Label("Profilo", systemImage: "person.crop.circle.badge.gearshape")
                        .font(.subheadline.weight(.semibold))
                }
                .tint(Color.uiAccent)
            }
        }
        .refreshable {
            await model.refreshLessons()
        }
        .task(id: "\(model.selectedCourse?.id ?? "")|\(model.weekStartDate.timeIntervalSince1970)|\(model.selectedAcademicYear)|\(model.selectedCourseYear)") {
            guard !model.requiresInitialSetup else { return }
            await model.refreshLessons()
        }
    }

    private var profileHeaderCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.selectedCourse?.name ?? "Corso non selezionato")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Color.uiTextPrimary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Text(model.selectedAcademicYearLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.uiTextSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.uiSurfaceInput))

                Spacer()

                HStack(spacing: 2) {
                    ForEach(1...max(1, model.selectedCourseMaxYear), id: \.self) { year in
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                model.selectedCourseYear = year
                            }
                        } label: {
                            Text("\(year)°")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(
                                    model.selectedCourseYear == year
                                        ? RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.uiAccent)
                                        : RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.clear)
                                )
                                .foregroundStyle(
                                    model.selectedCourseYear == year ? Color.white : Color.uiTextSecondary
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Anno \(year)")
                        .accessibilityAddTraits(model.selectedCourseYear == year ? .isSelected : [])
                    }
                }
                .padding(3)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.uiSurfaceInput)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidCard(cornerRadius: 20, tint: Color.uiSurfaceStrong)
    }

    private var weekNavigationCard: some View {
        HStack(spacing: 10) {
            Text(model.weekRangeTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.uiTextPrimary)

            Spacer()

            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                    model.goToPreviousWeek()
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.subheadline.weight(.semibold))
                    .padding(8)
                    .background(Circle().fill(model.canGoPreviousWeek ? Color.uiSurfaceInput : Color.uiSurfaceInput.opacity(0.4)))
            }
            .buttonStyle(.plain)
            .foregroundStyle(model.canGoPreviousWeek ? Color.uiTextPrimary : Color.uiTextMuted)
            .disabled(!model.canGoPreviousWeek)
            .accessibilityLabel("Settimana precedente")

            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                    model.jumpToToday()
                }
            } label: {
                Text("Oggi")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.uiAccent.opacity(0.18)))
                    .foregroundStyle(Color.uiAccent)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Torna alla settimana corrente")

            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                    model.goToNextWeek()
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .padding(8)
                    .background(Circle().fill(model.canGoNextWeek ? Color.uiSurfaceInput : Color.uiSurfaceInput.opacity(0.4)))
            }
            .buttonStyle(.plain)
            .foregroundStyle(model.canGoNextWeek ? Color.uiTextPrimary : Color.uiTextMuted)
            .disabled(!model.canGoNextWeek)
            .accessibilityLabel("Settimana successiva")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidCard(cornerRadius: 20, tint: Color.uiSurface)
    }

    @ViewBuilder
    private var lessonStateSection: some View {
        if model.isLoadingLessons {
            VStack(spacing: 16) {
                ProgressView()
                    .tint(Color.uiAccent)
                    .scaleEffect(1.5)
                    .frame(height: 28)
                Text("Caricamento orario...")
                    .font(.subheadline)
                    .foregroundStyle(Color.uiTextSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .liquidCard(cornerRadius: 18, tint: Color.uiSurface)
        } else if let lessonsError = model.lessonsError {
            let isOffline = lessonsError.localizedCaseInsensitiveContains("offline")
            VStack(alignment: .leading, spacing: 6) {
                Label(
                    isOffline ? "Dati offline" : "Errore caricamento",
                    systemImage: isOffline ? "wifi.slash" : "exclamationmark.triangle"
                )
                .font(.headline)
                .foregroundStyle(isOffline ? Color.uiTextSecondary : Color.uiTextPrimary)
                Text(lessonsError)
                    .font(.subheadline)
                    .foregroundStyle(Color.uiTextSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidCard(cornerRadius: 18, tint: isOffline ? Color.uiSurface : Color.red.opacity(0.16))
        } else if model.lessons.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Nessuna lezione in questa settimana")
                    .font(.headline)
                    .foregroundStyle(Color.uiTextPrimary)
                Text("Cambia settimana o aggiorna il profilo se necessario.")
                    .font(.subheadline)
                    .foregroundStyle(Color.uiTextSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidCard(cornerRadius: 18, tint: Color.uiSurface)
        }
    }

    private var allWeekDays: [Date] {
        (0..<5).compactMap { i in
            DateHelpers.italianCalendar.date(byAdding: .day, value: i, to: model.weekStartDate)
        }
    }

    @ViewBuilder
    private var lessonGridCard: some View {
        if !model.lessonsGroupedByDay.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                WeeklyGridView(weekDays: allWeekDays, lessonsGroupedByDay: model.lessonsGroupedByDay)
                    .padding(.vertical, 14)
            }
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.uiSurface)
                    .shadow(color: .black.opacity(0.09), radius: 12, x: 0, y: 5)
                    .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.55), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    @ViewBuilder
    private var lessonDayCards: some View {
        if !model.lessonsGroupedByDay.isEmpty {
            LazyVStack(spacing: 12) {
                ForEach(model.lessonsGroupedByDay, id: \.date) { group in
                    let isToday = Calendar.current.isDateInToday(group.date)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(isToday ? "Oggi" : DateHelpers.dayMonthFormatter.string(from: group.date).capitalized)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(isToday ? .white : Color.uiAccent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule().fill(isToday ? Color.uiAccent : Color.uiAccent.opacity(0.12))
                            )

                        VStack(spacing: 8) {
                            ForEach(group.lessons) { lesson in
                                LessonCard(lesson: lesson)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .liquidCard(cornerRadius: 18, tint: Color.uiSurface)
                }
            }
        }
    }
}

private struct LessonCard: View {
    let lesson: Lesson

    var body: some View {
        HStack(spacing: 0) {
            LinearGradient(
                colors: [Color.uiAccent, Color.uiAccent.opacity(0.3)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: 4)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text("\(lesson.startTime) – \(lesson.endTime)")
                        .font(.caption.weight(.bold))
                        .kerning(0.2)
                }
                .foregroundStyle(Color.uiAccent)

                Text(lesson.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.uiTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    if !lesson.professor.isEmpty {
                        Label(lesson.professor, systemImage: "person.fill")
                            .lineLimit(1)
                    }
                    if !locationLabel.isEmpty {
                        Label(locationLabel, systemImage: "mappin")
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(Color.uiTextSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.uiSurfaceInput)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var locationLabel: String {
        let building = lesson.building
        if building.isEmpty || building == lesson.room || building == "Edificio non specificato" {
            return lesson.room
        }
        return "\(lesson.room) — \(building)"
    }
}

// MARK: - Grid View

private struct WeeklyGridView: View {
    let weekDays: [Date]
    let lessonsGroupedByDay: [(date: Date, lessons: [Lesson])]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(weekDays.enumerated()), id: \.offset) { index, day in
                    DayGridColumn(date: day, lessons: lessonsForDay(day))
                    if index < weekDays.count - 1 {
                        Divider()
                            .padding(.vertical, 8)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func lessonsForDay(_ date: Date) -> [Lesson] {
        let start = Calendar.current.startOfDay(for: date)
        return lessonsGroupedByDay.first(where: {
            Calendar.current.startOfDay(for: $0.date) == start
        })?.lessons ?? []
    }
}

private struct DayGridColumn: View {
    let date: Date
    let lessons: [Lesson]

    private var isToday: Bool { Calendar.current.isDateInToday(date) }

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
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

            if lessons.isEmpty {
                Text("–")
                    .font(.caption)
                    .foregroundStyle(Color.uiTextMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            } else {
                VStack(spacing: 6) {
                    ForEach(lessons) { lesson in
                        GridLessonPill(lesson: lesson)
                    }
                }
            }
        }
        .frame(width: 128)
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }
}

private struct GridLessonPill: View {
    let lesson: Lesson

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.uiAccent.opacity(0.75))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(lesson.startTime)–\(lesson.endTime)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.uiAccent)

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
