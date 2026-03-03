import SwiftUI

private let subjectColorPalette: [Color] = [
    Color(hex: "C65D3D"),
    Color(hex: "3F6D5D"),
    Color(hex: "4A6FA5"),
    Color(hex: "D4874E"),
    Color(hex: "7D5BA6"),
    Color(hex: "3D8B8B"),
    Color(hex: "C05C7E"),
    Color(hex: "5A7A3A"),
]

func subjectColor(for title: String) -> Color {
    let index = abs(title.hashValue) % subjectColorPalette.count
    return subjectColorPalette[index]
}

struct WeeklyScheduleView: View {
    @ObservedObject var model: AppModel
    let onEditProfile: () -> Void

    private enum WeekViewMode { case list, grid }
    @State private var viewMode: WeekViewMode = .list
    @State private var showingSubjectFilter = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    Color.clear.frame(height: 0).id("schedule-top")
                    profileHeaderCard
                    weekNavigationCard
                    lessonStateSection
                        .animation(.spring(response: 0.38, dampingFraction: 0.84), value: model.isLoadingLessons)
                        .animation(.spring(response: 0.38, dampingFraction: 0.84), value: model.lessonsError)
                    if viewMode == .list {
                        lessonDayCards
                            .animation(.spring(response: 0.38, dampingFraction: 0.84), value: model.weekStartDate)
                    } else {
                        lessonGridCard
                            .animation(.spring(response: 0.38, dampingFraction: 0.84), value: model.weekStartDate)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
            }
            .scrollDismissesKeyboard(.immediately)
            .onChange(of: model.weekStartDate) { _, _ in
                withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
                    proxy.scrollTo("schedule-top", anchor: .top)
                }
            }
        }
        .sensoryFeedback(.impact(weight: .heavy, intensity: 0.7), trigger: model.weekStartDate)
        .sensoryFeedback(.impact(weight: .medium), trigger: viewMode)
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.8), trigger: showingSubjectFilter) { _, new in new }
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard abs(dx) > abs(dy) * 1.5, abs(dx) > 60 else { return }
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                        if dx < 0 { model.goToNextWeek() } else { model.goToPreviousWeek() }
                    }
                }
        )
        .navigationTitle("Timetable")
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
                    .accessibilityLabel("List view")
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
                    .accessibilityLabel("Grid view")
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
                    showingSubjectFilter = true
                } label: {
                    Image(systemName: model.hiddenSubjects.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .tint(model.hiddenSubjects.isEmpty ? Color.uiTextSecondary : Color.uiAccent)
                .accessibilityLabel("Filter subjects")
                .disabled(model.knownSubjects.isEmpty)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    onEditProfile()
                } label: {
                    Label("Profile", systemImage: "person.crop.circle.badge.gearshape")
                        .font(.subheadline.weight(.semibold))
                }
                .tint(Color.uiAccent)
            }
        }
        .refreshable {
            await model.refreshLessons()
        }
        .sheet(isPresented: $showingSubjectFilter) {
            SubjectFilterSheet(model: model)
        }
        .task(id: "\(model.selectedCourse?.id ?? "")|\(model.weekStartDate.timeIntervalSince1970)|\(model.selectedAcademicYear)|\(model.selectedCourseYear)") {
            guard !model.requiresInitialSetup else { return }
            await model.refreshLessons()
        }
    }

    private func nextUpcomingLesson(at now: Date) -> (lesson: Lesson, isNow: Bool)? {
        guard Calendar.current.isDateInToday(now) else { return nil }
        let cal = Calendar.current
        let currentMins = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        let todayLessons = model.lessonsGroupedByDay
            .first(where: { Calendar.current.isDateInToday($0.date) })?
            .lessons ?? []
        for lesson in todayLessons {
            let startParts = lesson.startTime.split(separator: ":").compactMap { Int($0) }
            let endParts   = lesson.endTime.split(separator: ":").compactMap { Int($0) }
            guard startParts.count == 2, endParts.count == 2 else { continue }
            let startMins = startParts[0] * 60 + startParts[1]
            let endMins   = endParts[0] * 60 + endParts[1]
            if currentMins >= startMins && currentMins < endMins { return (lesson, true) }
            if startMins > currentMins { return (lesson, false) }
        }
        return nil
    }

    private func countdownLabel(lesson: Lesson, isNow: Bool, at now: Date) -> String {
        if isNow { return "Now: \(lesson.title) until \(lesson.endTime)" }
        let cal = Calendar.current
        let currentMins = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        let parts = lesson.startTime.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return "Next: \(lesson.title)" }
        let diff = parts[0] * 60 + parts[1] - currentMins
        if diff < 60 { return "Next: \(lesson.title) in \(diff)m" }
        let h = diff / 60; let m = diff % 60
        return m == 0 ? "Next: \(lesson.title) in \(h)h" : "Next: \(lesson.title) in \(h)h \(m)m"
    }

    private var profileHeaderCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onEditProfile) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(uiAccentGradient)
                            .frame(width: 34, height: 34)
                        if let image = model.profileImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 34, height: 34)
                                .clipShape(Circle())
                        } else {
                            let initial = model.username.trimmingCharacters(in: .whitespaces).prefix(1).uppercased()
                            if initial.isEmpty {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white)
                            } else {
                                Text(initial)
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.username.isEmpty ? "Profile" : model.username)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.uiTextSecondary)
                        Text("Edit profile")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.uiTextMuted)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.uiTextMuted)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit profile")

            Divider()

            Text(model.selectedCourse?.name ?? "No programme selected")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Color.uiTextPrimary)
                .fixedSize(horizontal: false, vertical: true)

            TimelineView(.everyMinute) { context in
                if let next = nextUpcomingLesson(at: context.date) {
                    let color = next.isNow ? Color.uiAccent : Color.uiTextSecondary
                    Label(countdownLabel(lesson: next.lesson, isNow: next.isNow, at: context.date),
                          systemImage: next.isNow ? "dot.radiowaves.left.and.right" : "clock")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(color.opacity(0.10)))
                }
            }

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
                        .accessibilityLabel("Year \(year)")
                        .accessibilityAddTraits(model.selectedCourseYear == year ? .isSelected : [])
                    }
                }
                .padding(3)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.uiSurfaceInput)
                )
                .sensoryFeedback(.impact(weight: .medium, intensity: 0.8), trigger: model.selectedCourseYear)
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
            .accessibilityLabel("Previous week")

            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                    model.jumpToToday()
                }
            } label: {
                Text("Today")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.uiSurfaceStrong))
                    .foregroundStyle(Color.uiAccent)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Jump to current week")

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
            .accessibilityLabel("Next week")
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
                Text("Loading schedule…")
                    .font(.subheadline)
                    .foregroundStyle(Color.uiTextSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .liquidCard(cornerRadius: 18, tint: Color.uiSurface)
            .transition(.opacity)
        } else if let lessonsError = model.lessonsError {
            let isOffline = lessonsError.localizedCaseInsensitiveContains("offline")
            VStack(alignment: .leading, spacing: 6) {
                Label(
                    isOffline ? "Offline data" : "Load error",
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
            .transition(.opacity)
        } else if model.lessons.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("No lectures this week")
                    .font(.headline)
                    .foregroundStyle(Color.uiTextPrimary)
                Text("Try a different week or update your profile.")
                    .font(.subheadline)
                    .foregroundStyle(Color.uiTextSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidCard(cornerRadius: 18, tint: Color.uiSurface)
            .transition(.opacity)
        } else if model.lessonsGroupedByDay.isEmpty && !model.hiddenSubjects.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("No subjects visible")
                    .font(.headline)
                    .foregroundStyle(Color.uiTextPrimary)
                Text("All subjects for this week are hidden.")
                    .font(.subheadline)
                    .foregroundStyle(Color.uiTextSecondary)
                Button {
                    model.hiddenSubjects = []
                } label: {
                    Label("Show all subjects", systemImage: "line.3.horizontal.decrease.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.uiAccent)
                        .padding(.top, 4)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidCard(cornerRadius: 18, tint: Color.uiSurface)
            .transition(.opacity)
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
                WeeklyGridView(
                    weekDays: allWeekDays,
                    lessonsGroupedByDay: model.lessonsGroupedByDay,
                    workShiftForDay: { model.workShift(for: $0) }
                )
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
                    .strokeBorder(Color.uiCardStroke, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    @ViewBuilder
    private var lessonDayCards: some View {
        if !calendarDayDates.isEmpty {
            LazyVStack(spacing: 12) {
                ForEach(calendarDayDates, id: \.self) { date in
                    let isToday = Calendar.current.isDateInToday(date)
                    let dayLessons = lessonsForDay(date)
                    let dayShift = model.workShift(for: date)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(isToday ? "Today" : DateHelpers.dayMonthFormatter.string(from: date).capitalized)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(isToday ? .white : Color.uiAccent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule().fill(isToday ? Color.uiAccent : Color.uiSurfaceInput)
                            )

                        if let shift = dayShift {
                            WorkShiftCard(shift: shift)
                        }

                        if !dayLessons.isEmpty {
                            VStack(spacing: 8) {
                                ForEach(dayLessons) { lesson in
                                    LessonCard(lesson: lesson)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .liquidCard(cornerRadius: 18, tint: Color.uiSurface)
                }
            }
        }
    }

    private var calendarDayDates: [Date] {
        var days = Set(model.lessonsGroupedByDay.map { DateHelpers.startOfDay(for: $0.date) })
        if model.isWorker {
            for shift in model.workShifts where shift.isEnabled {
                if let day = DateHelpers.italianCalendar.date(byAdding: .day, value: shift.weekday, to: model.weekStartDate) {
                    days.insert(DateHelpers.startOfDay(for: day))
                }
            }
        }
        return days.sorted()
    }

    private func lessonsForDay(_ date: Date) -> [Lesson] {
        let start = DateHelpers.startOfDay(for: date)
        return model.lessonsGroupedByDay.first(where: {
            DateHelpers.startOfDay(for: $0.date) == start
        })?.lessons ?? []
    }
}

private struct LessonCard: View {
    let lesson: Lesson

    private var accentColor: Color { subjectColor(for: lesson.title) }

    var body: some View {
        HStack(spacing: 0) {
            LinearGradient(
                colors: [accentColor, accentColor.opacity(0.3)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: 4)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text("\(lesson.startTime) – \(lesson.endTime)")
                            .font(.caption.weight(.bold))
                            .kerning(0.2)
                    }
                    .foregroundStyle(accentColor)

                    if let dur = durationLabel {
                        Text(dur)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.uiTextMuted)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.uiSurfaceInput))
                    }
                }

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

    private var durationLabel: String? {
        let start = lesson.startTime.minutesSinceMidnight
        let end   = lesson.endTime.minutesSinceMidnight
        let diff  = end - start
        guard diff > 0 else { return nil }
        if diff < 60 { return "\(diff)m" }
        let h = diff / 60; let m = diff % 60
        return m == 0 ? "\(h)h" : "\(h)h\(m)m"
    }

    private var locationLabel: String {
        let building = lesson.building
        if building.isEmpty || building == lesson.room || building == "Edificio non specificato" {
            return lesson.room
        }
        return "\(lesson.room) — \(building)"
    }
}

private struct WorkShiftCard: View {
    let shift: WorkShift

    var body: some View {
        HStack(spacing: 0) {
            LinearGradient(
                colors: [Color.uiAccentSecondary, Color.uiAccentSecondary.opacity(0.3)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: 4)

            HStack(spacing: 10) {
                Image(systemName: "briefcase.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.uiAccentSecondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Work shift")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.uiAccentSecondary)
                    Text("\(shift.startTimeString) – \(shift.endTimeString)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.uiTextPrimary)
                }
                Spacer()
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.uiAccentSecondary.opacity(0.08))
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Grid View

private struct WeeklyGridView: View {
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

private struct DayGridColumn: View {
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

private struct GridLessonPill: View {
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

// MARK: - Subject Filter

private struct SubjectFilterSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Select subjects to show in the timetable")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.uiTextSecondary)
                        .padding(.horizontal, 4)

                    VStack(spacing: 0) {
                        ForEach(Array(model.knownSubjects.enumerated()), id: \.element) { index, title in
                            let visible = !model.hiddenSubjects.contains(title)
                            Button {
                                model.toggleSubjectVisibility(title)
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: visible ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(visible ? Color.uiAccent : Color.uiTextMuted)

                                    Text(title)
                                        .font(.subheadline)
                                        .foregroundStyle(visible ? Color.uiTextPrimary : Color.uiTextMuted)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .multilineTextAlignment(.leading)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .sensoryFeedback(.impact(weight: .medium, intensity: 0.8), trigger: visible)
                            .accessibilityLabel(title)
                            .accessibilityAddTraits(visible ? .isSelected : [])

                            if index < model.knownSubjects.count - 1 {
                                Divider()
                                    .padding(.leading, 54)
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.uiSurface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.uiCardStroke, lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background { AppBackground() }
            .navigationTitle("Subjects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Show all") {
                        model.hiddenSubjects = []
                    }
                    .font(.subheadline.weight(.semibold))
                    .tint(Color.uiTextSecondary)
                    .disabled(model.hiddenSubjects.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.subheadline.weight(.semibold))
                        .tint(Color.uiAccent)
                }
            }
        }
    }
}
