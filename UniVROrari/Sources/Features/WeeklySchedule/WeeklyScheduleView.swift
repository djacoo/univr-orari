import SwiftUI
import FoundationModels
import UIKit

// MARK: - WeeklyScheduleView

struct WeeklyScheduleView: View {
    @ObservedObject var model: AppModel
    let onEditProfile: () -> Void

    private enum WeekViewMode { case list, grid }
    @State private var viewMode: WeekViewMode = .list
    @State private var showingSubjectFilter = false
    @State private var selectedLesson: Lesson?
    @State private var exportURL: IdentifiableURL?
    @State private var shareImage: IdentifiableImage?

    struct IdentifiableURL: Identifiable {
        let id = UUID()
        let url: URL
    }

    struct IdentifiableImage: Identifiable {
        let id = UUID()
        let image: UIImage
    }

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
            .sheet(item: $exportURL) { item in
                ActivityViewControllerWrapper(activityItems: [item.url])
            }
            .sheet(item: $shareImage) { item in
                ActivityViewControllerWrapper(activityItems: [item.image])
            }
            .navigationTitle("Timetable")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    yearPickerToolbar
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        let ics = ICSExporter.generateICS(
                            lessons: model.lessons,
                            courseName: model.selectedCourse?.name ?? "UniVR"
                        )
                        if let url = ICSExporter.writeToTempFile(ics: ics) {
                            exportURL = IdentifiableURL(url: url)
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.subheadline.weight(.semibold))
                    }
                    .tint(Color.uiTextSecondary)
                    .disabled(model.lessons.isEmpty)
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

                    if let diff = model.scheduleDiff {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.uiAccent)
                            Text("Schedule updated: \(diff.summary)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.uiTextSecondary)
                            Spacer()
                            Button {
                                model.scheduleDiff = nil
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color.uiTextMuted)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.uiAccent.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

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
            .contextMenu {
                Button {
                    if let image = ScheduleImageRenderer.render(
                        weekLabel: weekRangeLabel,
                        courseName: model.selectedCourse?.name ?? "UniVR",
                        days: model.lessonsGroupedByDay
                    ) {
                        shareImage = IdentifiableImage(image: image)
                    }
                } label: {
                    Label("Share as image", systemImage: "photo")
                }
            }

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
        let fullWeekday = chipWeekdayFormatter.string(from: day)

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
        .accessibilityLabel("\(fullWeekday) \(dayNum)")
        .accessibilityHint(hasContent ? "Has lectures" : "No lectures")
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
            VStack(spacing: 12) {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.uiTextMuted)
                    .padding(.bottom, 4)
                Text("No lectures this week")
                    .font(.headline)
                    .foregroundStyle(Color.uiTextPrimary)
                Text("There are no scheduled lectures for this period.")
                    .font(.subheadline)
                    .foregroundStyle(Color.uiTextSecondary)
                    .multilineTextAlignment(.center)
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                        model.jumpToToday()
                    }
                } label: {
                    Label("Jump to today", systemImage: "arrow.uturn.backward")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.uiAccent)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
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

// MARK: - ActivityViewControllerWrapper

struct ActivityViewControllerWrapper: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
