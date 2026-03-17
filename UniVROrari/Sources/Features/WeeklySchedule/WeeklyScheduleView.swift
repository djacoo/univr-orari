import SwiftUI
import FoundationModels

// MARK: - WeeklyScheduleView

struct WeeklyScheduleView: View {
    @ObservedObject var model: AppModel
    let onEditProfile: () -> Void

    private enum WeekViewMode { case list, grid }
    @State private var viewMode: WeekViewMode = .list
    @State private var showingSubjectFilter = false
    @State private var selectedLesson: Lesson?

    var body: some View {
        scheduleScrollView
            .sensoryFeedback(.impact(weight: .heavy, intensity: 0.7), trigger: model.weekStartDate)
            .sensoryFeedback(.impact(weight: .medium), trigger: viewMode)
            .sensoryFeedback(.impact(weight: .medium, intensity: 0.8), trigger: showingSubjectFilter) { _, new in new }
            .gesture(
                DragGesture(minimumDistance: 50)
                    .onEnded { val in
                        let dx = val.translation.width
                        let dy = val.translation.height
                        guard abs(dx) > abs(dy) * 1.5, abs(dx) > 60 else { return }
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                            if dx < 0 { model.goToNextWeek() }
                            else if model.canGoPreviousWeek { model.goToPreviousWeek() }
                        }
                    }
            )
            .sheet(item: $selectedLesson) { lesson in LessonDetailSheet(lesson: lesson) }
            .navigationTitle("Timetable")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    yearPickerToolbar
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSubjectFilter = true
                    } label: {
                        Image(systemName: model.hiddenSubjects.isEmpty
                              ? "line.3.horizontal.decrease.circle"
                              : "line.3.horizontal.decrease.circle.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                    .tint(model.hiddenSubjects.isEmpty ? Color.uiTextSecondary : Color.uiAccent)
                    .accessibilityLabel("Filter subjects")
                    .disabled(model.knownSubjects.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onEditProfile) {
                        Label("Profile", systemImage: "person.crop.circle.badge.gearshape")
                            .font(.subheadline.weight(.semibold))
                    }
                    .tint(Color.uiAccent)
                }
            }
            .refreshable { await model.refreshLessons() }
            .sheet(isPresented: $showingSubjectFilter) {
                SubjectFilterSheet(model: model)
            }
            .task(id: "\(model.selectedCourse?.id ?? "")|\(model.weekStartDate.timeIntervalSince1970)|\(model.selectedAcademicYear)|\(model.selectedCourseYear)") {
                guard !model.requiresInitialSetup else { return }
                await model.refreshLessons()
            }
    }

    // MARK: Main scroll

    private var scheduleScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    Color.clear.frame(height: 0).id("schedule-top")

                    weekNavRow
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 14)

                    if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable,
                       !model.lessonsGroupedByDay.isEmpty {
                        AISummaryCard(weekLessons: model.lessonsGroupedByDay)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 14)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    dayChipsRow
                        .padding(.horizontal, 20)

                    Rectangle()
                        .fill(Color.uiStroke)
                        .frame(height: 0.5)
                        .padding(.top, 14)
                        .padding(.horizontal, 20)

                    lessonStateSection
                        .padding(.top, 8)
                        .animation(.easeOut(duration: 0.2), value: model.isLoadingLessons)
                        .animation(.easeOut(duration: 0.2), value: model.lessonsError)

                    if viewMode == .list {
                        if !calendarDayDates.isEmpty {
                            ForEach(Array(calendarDayDates.enumerated()), id: \.element) { index, date in
                                if Calendar.current.isDateInToday(date) {
                                    TimelineView(.everyMinute) { ctx in
                                        DayCardView(
                                            index: index, date: date, now: ctx.date,
                                            dayLessons: lessonsForDay(date),
                                            dayShift: model.workShift(for: date),
                                            onLessonTap: { selectedLesson = $0 }
                                        )
                                    }
                                } else {
                                    DayCardView(
                                        index: index, date: date, now: .distantPast,
                                        dayLessons: lessonsForDay(date),
                                        dayShift: model.workShift(for: date),
                                        onLessonTap: { selectedLesson = $0 }
                                    )
                                }
                            }
                        }
                    } else {
                        lessonGridCard
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                    }
                }
                .padding(.bottom, 16)
            }
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 80) }
            .scrollDismissesKeyboard(.immediately)
            .onAppear {
                guard let today = calendarDayDates.first(where: { Calendar.current.isDateInToday($0) }) else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    proxy.scrollTo(today, anchor: .top)
                }
            }
            .onChange(of: model.weekStartDate) { _, _ in
                proxy.scrollTo("schedule-top", anchor: .top)
            }
            .sensoryFeedback(.success, trigger: model.lessons.count) { old, new in old == 0 && new > 0 }
            .sensoryFeedback(.error, trigger: model.lessonsError) { _, new in new != nil }
        }
    }

    // MARK: Year picker (toolbar)

    private var yearPickerToolbar: some View {
        HStack(spacing: 2) {
            ForEach(1...max(1, model.selectedCourseMaxYear), id: \.self) { year in
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        model.selectedCourseYear = year
                    }
                } label: {
                    Text("\(year)°")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            model.selectedCourseYear == year
                                ? RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.uiAccent)
                                : RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.clear)
                        )
                        .foregroundStyle(model.selectedCourseYear == year ? .white : Color.uiTextMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Year \(year)")
                .accessibilityAddTraits(model.selectedCourseYear == year ? .isSelected : [])
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.uiSurfaceInput))
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.8), trigger: model.selectedCourseYear)
    }

    // MARK: Week nav row

    private var weekNavRow: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) { model.goToPreviousWeek() }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(model.canGoPreviousWeek ? Color.uiTextPrimary : Color.uiTextMuted.opacity(0.3))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(PressButtonStyle(scale: 0.85))
            .disabled(!model.canGoPreviousWeek)
            .accessibilityLabel("Previous week")

            Spacer()

            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) { model.jumpToToday() }
            } label: {
                Text(weekRangeLabel)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.uiTextPrimary)
                    .contentTransition(.numericText())
            }
            .buttonStyle(PressButtonStyle(scale: 0.97))
            .accessibilityLabel("Jump to current week")

            Spacer()

            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) { model.goToNextWeek() }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(model.canGoNextWeek ? Color.uiTextPrimary : Color.uiTextMuted.opacity(0.3))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(PressButtonStyle(scale: 0.85))
            .disabled(!model.canGoNextWeek)
            .accessibilityLabel("Next week")
        }
    }

    private static let weekMonthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.setLocalizedDateFormatFromTemplate("MMM")
        return f
    }()

    private var weekRangeLabel: String {
        let cal = Calendar.current
        let end = cal.date(byAdding: .day, value: 4, to: model.weekStartDate) ?? model.weekStartDate
        let startDay = cal.component(.day, from: model.weekStartDate)
        let endDay = cal.component(.day, from: end)
        let sm = Self.weekMonthFormatter.string(from: model.weekStartDate)
        let em = Self.weekMonthFormatter.string(from: end)
        return sm == em ? "\(startDay)–\(endDay) \(sm)" : "\(startDay) \(sm) – \(endDay) \(em)"
    }

    // MARK: Day chips

    private var dayChipsRow: some View {
        HStack(spacing: 0) {
            ForEach(allWeekDays, id: \.self) { day in
                dayChip(day)
            }
        }
    }

    private func dayChip(_ day: Date) -> some View {
        let cal = Calendar.current
        let isToday = cal.isDateInToday(day)
        let dayNum = cal.component(.day, from: day)
        let abbrev = String(chipWeekdayFormatter.string(from: day).prefix(1))
        let hasContent = calendarDayDates.contains(where: { cal.isDate($0, inSameDayAs: day) })

        return VStack(spacing: 4) {
            Text(abbrev)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isToday ? Color.uiAccent : Color.uiTextMuted)

            ZStack {
                if isToday {
                    Circle().fill(Color.uiAccent).frame(width: 28, height: 28)
                }
                Text("\(dayNum)")
                    .font(.system(size: 14, weight: isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? .white : Color.uiTextPrimary)
            }
            .frame(width: 28, height: 28)

            Circle()
                .fill(hasContent ? (isToday ? Color.white.opacity(0.5) : Color.uiAccent) : Color.clear)
                .frame(width: 3, height: 3)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: View mode toggle

    private var viewModeToggle: some View {
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
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.uiSurfaceInput))
    }

    // MARK: Lesson state / content

    @ViewBuilder
    private var lessonStateSection: some View {
        if model.isLoadingLessons {
            ForEach(0..<3, id: \.self) { dayIdx in
                DaySkeletonView(index: dayIdx)
            }
        } else if let err = model.lessonsError {
            let isOffline = err.localizedCaseInsensitiveContains("offline")
            HStack(spacing: 12) {
                Image(systemName: isOffline ? "wifi.slash" : "exclamationmark.triangle")
                    .font(.system(size: 14))
                    .foregroundStyle(isOffline ? Color.uiTextMuted : .red)
                VStack(alignment: .leading, spacing: 3) {
                    Text(isOffline ? "Offline data" : "Load error")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isOffline ? Color.uiTextSecondary : Color.uiTextPrimary)
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(Color.uiTextMuted)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                isOffline ? Color.uiSurface : Color.red.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .transition(.opacity)
        } else if model.lessons.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.uiTextMuted)
                    .padding(.bottom, 4)
                Text("No lectures this week")
                    .font(.headline)
                    .foregroundStyle(Color.uiTextPrimary)
                Text("Try a different week or update your profile.")
                    .font(.subheadline)
                    .foregroundStyle(Color.uiTextSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
            .transition(.opacity)
        } else if model.lessonsGroupedByDay.isEmpty && !model.hiddenSubjects.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "eye.slash")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.uiTextMuted)
                    .padding(.bottom, 4)
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
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var lessonGridCard: some View {
        if !model.lessonsGroupedByDay.isEmpty {
            WeeklyGridView(
                weekDays: allWeekDays,
                lessonsGroupedByDay: model.lessonsGroupedByDay,
                workShiftForDay: { model.workShift(for: $0) }
            )
            .padding(.vertical, 14)
            .background(Color.uiSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.07), radius: 6, x: 0, y: 3)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    // MARK: Helpers

    private var allWeekDays: [Date] {
        (0..<5).compactMap { i in
            DateHelpers.italianCalendar.date(byAdding: .day, value: i, to: model.weekStartDate)
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

    private var monthLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return f.string(from: model.weekStartDate)
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
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(subjectColor(for: title))
                                        .frame(width: 10, height: 10)
                                        .opacity(visible ? 1.0 : 0.3)

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
                            .buttonStyle(PressButtonStyle(scale: 0.97))
                            .sensoryFeedback(.impact(weight: .medium, intensity: 0.8), trigger: visible)
                            .accessibilityLabel(title)
                            .accessibilityAddTraits(visible ? .isSelected : [])

                            if index < model.knownSubjects.count - 1 {
                                Divider()
                                    .padding(.leading, 54)
                            }
                        }
                    }
                    .background(Color.uiSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.09), radius: 16, x: 0, y: 5)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background { AppBackground() }
            .navigationTitle("Subjects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Show all") { model.hiddenSubjects = [] }
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

// MARK: - Today View

struct TodayView: View {
    @ObservedObject var model: AppModel
    let onEditProfile: () -> Void

    @State private var showingWeeklyCalendar = false
    @State private var selectedLesson: Lesson?
    @State private var showingAIAssistant = false

    private var isWeekend: Bool {
        let w = Calendar.current.component(.weekday, from: Date())
        return w == 1 || w == 7
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.setLocalizedDateFormatFromTemplate("EEEE")
        return f
    }()

    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return f
    }()

    private var yearPickerToolbar: some View {
        HStack(spacing: 2) {
            ForEach(1...max(1, model.selectedCourseMaxYear), id: \.self) { year in
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        model.selectedCourseYear = year
                    }
                } label: {
                    Text("\(year)°")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            model.selectedCourseYear == year
                                ? RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.uiAccent)
                                : RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.clear)
                        )
                        .foregroundStyle(model.selectedCourseYear == year ? .white : Color.uiTextMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Year \(year)")
                .accessibilityAddTraits(model.selectedCourseYear == year ? .isSelected : [])
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.uiSurfaceInput))
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.8), trigger: model.selectedCourseYear)
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 0).id("today-top")

                    dateAndCourseHeader(at: context.date)
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 16)

                    if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable,
                       !todayLessons.isEmpty, !model.isLoadingLessons {
                        AIDailyBriefCard(lessons: todayLessons, now: context.date)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 16)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    if !model.isLoadingLessons {
                        heroSection(at: context.date)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 24)
                            .transition(.opacity)
                            .animation(.spring(response: 0.38, dampingFraction: 0.84), value: model.lessons.count)
                    }

                    scheduleList(at: context.date)

                    weekButton
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                }
                .padding(.bottom, 24)
            }
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 80) }
        }
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                yearPickerToolbar
            }
            ToolbarItem(placement: .topBarTrailing) {
                if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable {
                    Button { showingAIAssistant = true } label: {
                        Image(systemName: "sparkles")
                            .font(.subheadline.weight(.semibold))
                    }
                    .tint(Color.uiAccent)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onEditProfile) {
                    Label("Profile", systemImage: "person.crop.circle.badge.gearshape")
                        .font(.subheadline.weight(.semibold))
                }
                .tint(Color.uiAccent)
            }
        }
        .refreshable { await model.refreshLessons() }
        .task(id: "\(model.selectedCourse?.id ?? "")|\(model.selectedAcademicYear)|\(model.selectedCourseYear)") {
            guard !model.requiresInitialSetup else { return }
            model.jumpToToday()
            await model.refreshLessons()
        }
        .navigationDestination(isPresented: $showingWeeklyCalendar) {
            WeeklyScheduleView(model: model, onEditProfile: onEditProfile)
        }
        .sheet(item: $selectedLesson) { lesson in LessonDetailSheet(lesson: lesson) }
        .sheet(isPresented: $showingAIAssistant) {
            if #available(iOS 26.0, *) {
                AIScheduleAssistantSheet(model: model)
            }
        }
    }

    // MARK: Date + course header

    private func dateAndCourseHeader(at now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Self.dayFormatter.string(from: now).uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(2)
                .foregroundStyle(Color.uiTextMuted)
            HStack(alignment: .lastTextBaseline, spacing: 12) {
                Text("\(Calendar.current.component(.day, from: now))")
                    .font(.system(size: 64, weight: .black))
                    .foregroundStyle(Color.uiTextPrimary)
                    .contentTransition(.numericText())
                Text(Self.monthYearFormatter.string(from: now))
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.uiTextSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Hero section

    @ViewBuilder
    private func heroSection(at now: Date) -> some View {
        let lessons = todayLessons
        let cal = Calendar.current
        let nowMins = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)

        if lessons.isEmpty && todayShift == nil {
            if isWeekend {
                HStack(spacing: 12) {
                    Image(systemName: "sun.horizon.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.uiTextMuted)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("It's the weekend")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.uiTextSecondary)
                        Text("No lectures scheduled. Enjoy the break.")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.uiTextMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color.uiSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.uiTextMuted)
                    Text("No lectures today")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.uiTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color.uiSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        } else if let active = lessons.first(where: {
            $0.startTime.minutesSinceMidnight <= nowMins && nowMins < $0.endTime.minutesSinceMidnight
        }) {
            activeLectureCard(lesson: active, nowMins: nowMins)
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .onTapGesture { selectedLesson = active }
        } else if let next = lessons.first(where: { $0.startTime.minutesSinceMidnight > nowMins }) {
            let diff = next.startTime.minutesSinceMidnight - nowMins
            nextLectureCard(lesson: next, diffMins: diff, now: now)
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .onTapGesture { selectedLesson = next }
        } else if !lessons.isEmpty {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.uiAccentSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("All done for today")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.uiTextPrimary)
                    Text("\(lessons.count) lecture\(lessons.count > 1 ? "s" : "") completed")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.uiTextMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.uiSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func activeLectureCard(lesson: Lesson, nowMins: Int) -> some View {
        let total = lesson.endTime.minutesSinceMidnight - lesson.startTime.minutesSinceMidnight
        let elapsed = nowMins - lesson.startTime.minutesSinceMidnight
        let fraction = total > 0 ? Double(max(0, min(elapsed, total))) / Double(total) : 0

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Circle()
                    .fill(.white)
                    .frame(width: 7, height: 7)
                Text("LIVE NOW")
                    .font(.system(size: 10, weight: .black))
                    .tracking(2)
                    .foregroundStyle(.white)
                Spacer()
                Text("until \(lesson.endTime)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
            }

            Text(lesson.title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            if !lesson.room.isEmpty || !lesson.professor.isEmpty {
                HStack(spacing: 10) {
                    if !lesson.room.isEmpty {
                        Label(lesson.room, systemImage: "mappin")
                    }
                    if !lesson.professor.isEmpty && !lesson.room.isEmpty {
                        Text("·").foregroundStyle(.white.opacity(0.4))
                    }
                    if !lesson.professor.isEmpty {
                        Label(lesson.professor, systemImage: "person")
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.2)).frame(height: 3)
                    Capsule().fill(.white.opacity(0.85)).frame(width: geo.size.width * fraction, height: 3)
                }
            }
            .frame(height: 3)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(uiAccentGradient)
        )
    }

    private func nextLectureCard(lesson: Lesson, diffMins: Int, now: Date) -> some View {
        let timeStr: String = {
            if diffMins < 60 { return "\(diffMins)m" }
            let h = diffMins / 60; let m = diffMins % 60
            return m == 0 ? "\(h)h" : "\(h)h \(m)m"
        }()

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.uiTextMuted)
                if diffMins < 60 {
                    TimelineView(.periodic(from: now, by: 1)) { ctx in
                        let cal = Calendar.current
                        let totalSecs = lesson.startTime.minutesSinceMidnight * 60
                            - (cal.component(.hour, from: ctx.date) * 3600
                            + cal.component(.minute, from: ctx.date) * 60
                            + cal.component(.second, from: ctx.date))
                        let s = max(totalSecs, 0)
                        Text("IN \(s / 60):\(String(format: "%02d", s % 60))")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(1.5)
                            .foregroundStyle(Color.uiTextMuted)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                } else {
                    Text("NEXT IN \(timeStr.uppercased())")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(Color.uiTextMuted)
                }
                Spacer()
                Text(lesson.startTime)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.uiTextSecondary)
            }

            Text(lesson.title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.uiTextPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if !lesson.room.isEmpty || !lesson.professor.isEmpty {
                HStack(spacing: 10) {
                    if !lesson.room.isEmpty {
                        Label(lesson.room, systemImage: "mappin")
                    }
                    if !lesson.professor.isEmpty && !lesson.room.isEmpty {
                        Text("·").foregroundStyle(Color.uiTextMuted.opacity(0.4))
                    }
                    if !lesson.professor.isEmpty {
                        Label(lesson.professor, systemImage: "person")
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(Color.uiTextMuted)
                .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.uiSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.uiStroke, lineWidth: 1))
    }

    // MARK: Schedule list

    @ViewBuilder
    private func scheduleList(at now: Date) -> some View {
        let lessons = todayLessons
        let shift = todayShift

        if model.isLoadingLessons {
            HStack(spacing: 12) {
                ProgressView().tint(Color.uiAccent)
                Text("Loading schedule…")
                    .font(.subheadline)
                    .foregroundStyle(Color.uiTextSecondary)
            }
            .padding(.horizontal, 20)
        } else if let err = model.lessonsError {
            let isOffline = err.localizedCaseInsensitiveContains("offline")
            HStack(spacing: 12) {
                Image(systemName: isOffline ? "wifi.slash" : "exclamationmark.triangle")
                    .font(.system(size: 14))
                    .foregroundStyle(isOffline ? Color.uiTextMuted : .red)
                Text(err)
                    .font(.caption)
                    .foregroundStyle(Color.uiTextMuted)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                isOffline ? Color.uiSurface : Color.red.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .padding(.horizontal, 20)
        } else if !lessons.isEmpty || shift != nil {
            let cal = Calendar.current
            let nowMins = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)

            if let shift = shift {
                todayShiftRow(shift: shift).padding(.horizontal, 20)
                if !lessons.isEmpty {
                    Rectangle().fill(Color.uiStroke).frame(height: 0.5).padding(.horizontal, 20)
                }
            }
            ForEach(Array(lessons.enumerated()), id: \.element.id) { idx, lesson in
                if idx > 0 {
                    Rectangle().fill(Color.uiStroke).frame(height: 0.5).padding(.horizontal, 20)
                }
                let isActive = lesson.startTime.minutesSinceMidnight <= nowMins
                    && nowMins < lesson.endTime.minutesSinceMidnight
                todayLessonRow(lesson: lesson, isActive: isActive).padding(.horizontal, 20)
            }
        }
    }

    private func todayLessonRow(lesson: Lesson, isActive: Bool) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(isActive ? Color.uiAccent : subjectColor(for: lesson.title))
                .frame(width: 3)
                .opacity(isActive ? 1 : 0.75)

            VStack(alignment: .trailing, spacing: 2) {
                Text(lesson.startTime)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(isActive ? Color.uiAccent : Color.uiTextSecondary)
                Text(lesson.endTime)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.uiTextMuted)
            }
            .frame(width: 52)
            .padding(.leading, 14)
            .padding(.vertical, 14)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    Text(lesson.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.uiTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if isActive {
                        Text("LIVE")
                            .font(.system(size: 8, weight: .black))
                            .tracking(1)
                            .foregroundStyle(Color.uiAccent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.uiAccent.opacity(0.12)))
                    }
                }

                if !lesson.room.isEmpty {
                    Label(lesson.room, systemImage: "mappin")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.uiTextMuted)
                        .lineLimit(1)
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 16)
            .padding(.vertical, 14)
        }
        .background(isActive ? Color.uiAccent.opacity(0.04) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { selectedLesson = lesson }
    }

    private func todayShiftRow(shift: WorkShift) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.uiAccentSecondary.opacity(0.8))
                .frame(width: 3)

            VStack(alignment: .trailing, spacing: 2) {
                Text(shift.startTimeString)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.uiAccentSecondary.opacity(0.85))
                Text(shift.endTimeString)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.uiTextMuted)
            }
            .frame(width: 52)
            .padding(.leading, 14)
            .padding(.vertical, 14)

            HStack(spacing: 8) {
                Image(systemName: "briefcase.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.uiAccentSecondary)
                Text("Work shift")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.uiTextPrimary)
            }
            .padding(.leading, 14)
            .padding(.vertical, 14)
        }
    }

    // MARK: Week button

    private var weekButton: some View {
        Button { showingWeeklyCalendar = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "calendar")
                    .font(.system(size: 15, weight: .semibold))
                Text("This week")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Color.uiAccent)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.uiAccent.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.uiAccent.opacity(0.14), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PressButtonStyle(scale: 0.97))
        .accessibilityLabel("Open full weekly calendar")
    }

    // MARK: Helpers

    private var todayLessons: [Lesson] {
        model.lessonsGroupedByDay
            .first(where: { Calendar.current.isDateInToday($0.date) })?
            .lessons ?? []
    }

    private var todayShift: WorkShift? {
        model.workShift(for: Date())
    }
}

// MARK: - Shimmer

private struct ShimmerModifier: ViewModifier {
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

private struct DaySkeletonView: View {
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

private struct LessonDetailSheet: View {
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
