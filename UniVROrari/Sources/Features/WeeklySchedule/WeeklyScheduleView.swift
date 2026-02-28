import SwiftUI

struct WeeklyScheduleView: View {
    @ObservedObject var model: AppModel
    let onEditProfile: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                profileHeaderCard
                weekNavigationCard
                lessonStateSection
                lessonDayCards
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .navigationTitle("Calendario")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                Image(systemName: "graduationcap.fill")
                    .foregroundStyle(Color.uiAccent)

                Text(model.selectedAcademicYearLabel)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.uiTextPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.uiAccent.opacity(0.18))
                    )

                Spacer()
            }

            Text(model.selectedCourse?.name ?? "Corso non selezionato")
                .font(.system(size: 25, weight: .bold, design: .rounded))
                .foregroundStyle(Color.uiTextPrimary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Text("Anno di corso")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.uiTextSecondary)

                Spacer()

                HStack(spacing: 0) {
                    ForEach(1...max(1, model.selectedCourseMaxYear), id: \.self) { year in
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                model.selectedCourseYear = year
                            }
                        } label: {
                            Text("\(year)°")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    model.selectedCourseYear == year
                                        ? Color.uiAccent
                                        : Color.clear
                                )
                                .foregroundStyle(
                                    model.selectedCourseYear == year
                                        ? Color.white
                                        : Color.uiTextSecondary
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.uiSurfaceInput)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.uiStrokeStrong, lineWidth: 1)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidCard(cornerRadius: 24, tint: Color.uiSurfaceStrong)
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
                    .background(Circle().fill(model.canGoPreviousWeek ? Color.uiSurfaceInput : Color.uiSurfaceInput.opacity(0.45)))
                    .overlay(Circle().stroke(model.canGoPreviousWeek ? Color.uiStrokeStrong : Color.uiStroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .foregroundStyle(model.canGoPreviousWeek ? Color.uiTextPrimary : Color.uiTextMuted)
            .disabled(!model.canGoPreviousWeek)

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

            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                    model.goToNextWeek()
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .padding(8)
                    .background(Circle().fill(model.canGoNextWeek ? Color.uiSurfaceInput : Color.uiSurfaceInput.opacity(0.45)))
                    .overlay(Circle().stroke(model.canGoNextWeek ? Color.uiStrokeStrong : Color.uiStroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .foregroundStyle(model.canGoNextWeek ? Color.uiTextPrimary : Color.uiTextMuted)
            .disabled(!model.canGoNextWeek)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidCard(cornerRadius: 20, tint: Color.uiSurface)
    }

    @ViewBuilder
    private var lessonStateSection: some View {
        if model.isLoadingLessons {
            HStack(spacing: 10) {
                ProgressView()
                    .tint(Color.uiAccent)
                Text("Caricamento orario...")
                    .font(.subheadline)
                    .foregroundStyle(Color.uiTextSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

    @ViewBuilder
    private var lessonDayCards: some View {
        if !model.lessonsGroupedByDay.isEmpty {
            LazyVStack(spacing: 12) {
                ForEach(model.lessonsGroupedByDay, id: \.date) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(DateHelpers.dayMonthFormatter.string(from: group.date).capitalized)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(Color.uiAccent)

                        ForEach(group.lessons) { lesson in
                            LessonCard(lesson: lesson)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .liquidCard(cornerRadius: 20, tint: Color.uiSurface)
                }
            }
        }
    }
}

private struct LessonCard: View {
    let lesson: Lesson

    private var locationLabel: String {
        let building = lesson.building
        if building.isEmpty || building == lesson.room || building == "Edificio non specificato" {
            return lesson.room
        }
        return "\(lesson.room) — \(building)"
    }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.uiAccent)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 7) {
                Text(lesson.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.uiTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Label("\(lesson.startTime) - \(lesson.endTime)", systemImage: "clock.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.uiAccent)

                Label(locationLabel, systemImage: "mappin")
                    .font(.caption)
                    .foregroundStyle(Color.uiTextSecondary)

                Label(lesson.professor, systemImage: "person.fill")
                    .font(.caption)
                    .foregroundStyle(Color.uiTextSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(13)
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.uiSurfaceInput)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.uiStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
