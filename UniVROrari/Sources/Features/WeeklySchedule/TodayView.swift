import SwiftUI
import FoundationModels

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
