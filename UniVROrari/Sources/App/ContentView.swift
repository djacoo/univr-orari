import SwiftUI
import PhotosUI
import UserNotifications

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var setupCourseSearch = ""
    @State private var setupSelectedCourse: StudyCourse?
    @State private var setupSelectedAcademicYear = DateHelpers.currentAcademicYear()
    @State private var isApplyingSetup = false
    @State private var showingProfile = false
    @State private var selectedTab = 0
    @State private var loaderVisible = false
    @State private var loaderName = "UniVR Orari"
    @State private var loaderDuration = 5.0
    @State private var loaderTask: Task<Void, Never>?
    @AppStorage("preferredColorScheme") private var colorSchemePreference: String = "system"
    @Environment(\.colorScheme) private var colorScheme

    private var resolvedColorScheme: ColorScheme? {
        switch colorSchemePreference {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    private func showLoader(name: String, duration: Double, then action: (() -> Void)? = nil) {
        loaderTask?.cancel()
        loaderName = name
        loaderDuration = duration
        loaderVisible = true
        loaderTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(duration))
                action?()
                withAnimation(.easeOut(duration: 0.45)) {
                    loaderVisible = false
                }
            } catch {}
        }
    }

    private var profileSheetBinding: Binding<Bool> {
        Binding(
            get: { showingProfile },
            set: { newValue in
                if !newValue && showingProfile {
                    showLoader(name: "Timetable", duration: 1)
                }
                showingProfile = newValue
            }
        )
    }

    var body: some View {
        Group {
            if model.requiresInitialSetup {
                setupView
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
            } else {
                mainTabs
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .background { AppBackground() }
        .preferredColorScheme(resolvedColorScheme)
        .animation(.spring(response: 0.48, dampingFraction: 0.86), value: model.requiresInitialSetup)
        .onAppear {
            syncSetupStateFromModel()
            showLoader(name: "UniVR Orari", duration: 1.5)
        }
        .onChange(of: model.requiresInitialSetup) { _, requiresSetup in
            if requiresSetup {
                syncSetupStateFromModel()
            }
        }
        .onChange(of: model.pendingShortcutAction) { _, action in
            guard let action else { return }
            switch action {
            case .openTimetable:
                selectedTab = 0
                showLoader(name: "Timetable", duration: 1)
            case .findFreeRoom:
                selectedTab = 1
                showLoader(name: "Rooms", duration: 1)
            }
            model.pendingShortcutAction = nil
        }
        .task(id: colorScheme) {
            model.refreshLiveActivity(isDark: colorScheme == .dark)
        }
        .sheet(isPresented: profileSheetBinding) {
            ProfileView(model: model)
        }
        .overlay {
            if loaderVisible {
                LoaderView(name: loaderName, duration: loaderDuration)
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: showingProfile) { _, new in new }
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.8), trigger: loaderVisible) { _, new in !new }
        .sensoryFeedback(.success, trigger: model.requiresInitialSetup) { old, new in old && !new }
    }

    private var todayLectureCount: Int {
        model.lessonsGroupedByDay
            .first(where: { Calendar.current.isDateInToday($0.date) })?
            .lessons.count ?? 0
    }

    private var mainTabs: some View {
        ZStack(alignment: .bottom) {
            Group {
                if selectedTab == 0 {
                    NavigationStack {
                        TodayView(
                            model: model,
                            onEditProfile: { showLoader(name: "Profile", duration: 1) { showingProfile = true } }
                        )
                    }
                    .transition(.opacity)
                } else {
                    NavigationStack {
                        RoomsView(model: model)
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: selectedTab)

            FloatingTabBar(selectedTab: selectedTab, todayBadgeCount: todayLectureCount) { newTab in
                guard newTab != selectedTab else { return }
                selectedTab = newTab
                showLoader(name: newTab == 0 ? "Timetable" : "Rooms", duration: 1)
            }
        }
        .tint(Color.uiAccent)
        .sensoryFeedback(.selection, trigger: selectedTab)
    }

    private var setupView: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                setupHero
                setupOptionsSection
                setupSearchSection

                if model.isLoadingCourses {
                    loadingSetupCard
                } else if setupFilteredCourses.isEmpty {
                    emptySetupCard
                } else {
                    setupCourseSelectionCard
                }

                setupContinueButton
                    .padding(.top, 4)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private var setupHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("UNIVR · ORARI")
                .font(.system(size: 10, weight: .black))
                .tracking(4)
                .foregroundStyle(Color.uiAccent)

            VStack(alignment: .leading, spacing: -4) {
                Text("Your")
                    .font(.system(size: 48, weight: .black))
                    .foregroundStyle(Color.uiTextPrimary)
                Text("timetable.")
                    .font(.system(size: 48, weight: .black))
                    .foregroundStyle(Color.uiAccent)
            }

            Text("Select your degree programme to get started.")
                .font(.subheadline)
                .foregroundStyle(Color.uiTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    private var setupOptionsSection: some View {
        let maxYear = max(1, setupSelectedCourse?.maxYear ?? 3)
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("ACADEMIC YEAR")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(Color.uiTextMuted)

                Picker("Academic year", selection: $setupSelectedAcademicYear) {
                    ForEach(model.availableAcademicYears, id: \.self) { academicYear in
                        Text(model.academicYearLabel(for: academicYear)).tag(academicYear)
                    }
                }
                .pickerStyle(.menu)
                .font(.headline.weight(.semibold))
                .tint(Color.uiAccent)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("YEAR OF STUDY")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(Color.uiTextMuted)

                HStack(spacing: 0) {
                    ForEach(1...maxYear, id: \.self) { year in
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                model.selectedCourseYear = year
                            }
                        } label: {
                            Text("\(year)°")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(
                                    model.selectedCourseYear == year ? Color.uiAccent : Color.clear
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
                .background(Color.uiSurfaceInput, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .sensoryFeedback(.impact(weight: .medium, intensity: 0.8), trigger: model.selectedCourseYear)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.uiSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.8), trigger: setupSelectedAcademicYear)
        .onChange(of: setupSelectedCourse) { _, newCourse in
            let newMax = newCourse?.maxYear ?? 3
            if model.selectedCourseYear > newMax {
                model.selectedCourseYear = newMax
            }
        }
    }

    private var setupSearchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DEGREE PROGRAMME")
                .font(.system(size: 10, weight: .bold))
                .tracking(2)
                .foregroundStyle(Color.uiTextMuted)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.uiAccent)

                TextField("Search (e.g. Artificial Intelligence)", text: $setupCourseSearch)
                    .foregroundStyle(Color.uiTextPrimary)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if !setupCourseSearch.isEmpty {
                    Button {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.75)) {
                            setupCourseSearch = ""
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.uiTextMuted)
                            .font(.system(size: 16))
                    }
                    .buttonStyle(PressButtonStyle(scale: 0.88))
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(12)
            .background(Color.uiSurfaceInput, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var setupCourseSelectionCard: some View {
        LazyVStack(spacing: 6) {
            ForEach(displayedSetupCourses) { course in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                        setupSelectedCourse = course
                    }
                } label: {
                    HStack(alignment: .top, spacing: 11) {
                        Image(systemName: setupSelectedCourse?.id == course.id ? "checkmark.circle.fill" : "circle")
                            .font(.headline)
                            .foregroundStyle(setupSelectedCourse?.id == course.id ? Color.uiAccent : Color.uiTextSecondary)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(course.name)
                                .font(.subheadline.weight(.semibold))
                                .multilineTextAlignment(.leading)
                                .foregroundStyle(Color.uiTextPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text(course.facultyName)
                                .font(.caption)
                                .foregroundStyle(Color.uiTextMuted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(setupSelectedCourse?.id == course.id ? Color.uiAccent.opacity(0.12) : Color.uiSurface)
                    )
                }
                .buttonStyle(PressButtonStyle())
                .accessibilityLabel(course.name)
                .accessibilityHint(course.facultyName)
                .accessibilityAddTraits(setupSelectedCourse?.id == course.id ? .isSelected : [])
            }
        }
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.8), trigger: setupSelectedCourse?.id)
    }

    private var loadingSetupCard: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(Color.uiAccent)
            Text("Loading course catalogue…")
                .font(.subheadline)
                .foregroundStyle(Color.uiTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.uiSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var emptySetupCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No programmes found")
                .font(.headline)
                .foregroundStyle(Color.uiTextPrimary)

            if let error = model.coursesError {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(Color.uiTextSecondary)
            } else {
                Text("Try a different search query.")
                    .font(.subheadline)
                    .foregroundStyle(Color.uiTextSecondary)
            }

            Button {
                Task { await model.loadCourses() }
            } label: {
                Label("Reload", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.uiAccent)
                    .padding(.top, 4)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.uiSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var setupContinueButton: some View {
        Button {
            guard let selectedCourse else { return }

            isApplyingSetup = true
            Task {
                await model.completeInitialSetup(
                    course: selectedCourse,
                    academicYear: setupSelectedAcademicYear
                )
                isApplyingSetup = false
            }
        } label: {
            HStack {
                Spacer()
                if isApplyingSetup {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Open timetable")
                        .font(.headline.weight(.semibold))
                }
                Spacer()
            }
            .padding(.vertical, 15)
            .foregroundStyle(selectedCourse == nil ? Color.uiTextMuted : .white)
            .background(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(
                        selectedCourse == nil
                        ? LinearGradient(
                            colors: [Color.uiButtonDisabled, Color.uiButtonDisabled],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        : uiAccentGradient
                    )
            )
            .shadow(color: Color.uiAccent.opacity(selectedCourse == nil ? 0 : 0.32), radius: 14, x: 0, y: 7)
        }
        .disabled(selectedCourse == nil || isApplyingSetup)
        .buttonStyle(PressButtonStyle(scale: 0.97))
    }

    private var setupFilteredCourses: [StudyCourse] {
        let query = setupCourseSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedQuery = query.searchNormalized
        guard !normalizedQuery.isEmpty else {
            return model.allCourses
        }

        let substringMatches = model.allCourses.filter { course in
            course.name.searchNormalized.contains(normalizedQuery)
                || course.facultyName.searchNormalized.contains(normalizedQuery)
        }

        // When substring search finds nothing, fall back to semantic ranking so
        // queries like "calculus" or "databases" still surface relevant courses.
        if !substringMatches.isEmpty { return substringMatches }
        return SemanticCourseSearch.rank(query: query, courses: model.allCourses)
    }

    private var displayedSetupCourses: [StudyCourse] {
        let query = setupCourseSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return Array(setupFilteredCourses.prefix(40))
        }
        return setupFilteredCourses
    }

    private var selectedCourse: StudyCourse? {
        if let setupSelectedCourse {
            return setupSelectedCourse
        }
        return model.selectedCourse
    }

    private func syncSetupStateFromModel() {
        setupSelectedAcademicYear = model.selectedAcademicYear
        setupSelectedCourse = model.selectedCourse
        setupCourseSearch = ""
    }
}

struct ProfileBackground: View {
    var body: some View {
        Color.uiBackground.ignoresSafeArea()
    }
}

struct AppBackground: View {
    var body: some View {
        Color.uiBackground.ignoresSafeArea()
    }
}

struct LoaderView: View {
    let name: String
    let duration: Double

    @State private var progress: Double = 0
    @State private var step: Int = 0

    private func fireDroplet(progress: Double) {
        Task { @MainActor in
            let base = 0.16 + 0.84 * max(0, min(progress, 1))
            let style: UIImpactFeedbackGenerator.FeedbackStyle = base < 0.48 ? .light : (base < 0.74 ? .medium : .heavy)
            let gen = UIImpactFeedbackGenerator(style: style)
            let ripple = UIImpactFeedbackGenerator(style: .light)
            gen.prepare()
            ripple.prepare()
            gen.impactOccurred(intensity: min(base, 1.0))
            try? await Task.sleep(for: .milliseconds(65))
            ripple.impactOccurred(intensity: min(base * 0.62, 1.0))
            try? await Task.sleep(for: .milliseconds(58))
            ripple.impactOccurred(intensity: min(base * 0.26, 1.0))
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "1E1B4B"), Color(hex: "312E81"), Color(hex: "4F46E5")],
                startPoint: .bottomLeading,
                endPoint: .topTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color(hex: "818CF8").opacity(0.30))
                .frame(width: 380, height: 380)
                .blur(radius: 90)
                .offset(x: 130, y: -240)

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 32) {
                    Text("UNIVR · ORARI")
                        .font(.system(size: 10, weight: .black))
                        .tracking(6)
                        .foregroundStyle(.white.opacity(0.4))

                    Text(name)
                        .font(.system(size: 48, weight: .black))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.2)
                }

                Spacer()

                VStack(spacing: 14) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(.white.opacity(0.18))
                                .frame(height: 3)
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(.white)
                                .frame(width: geo.size.width * progress, height: 3)
                                .animation(.easeInOut(duration: duration), value: progress)
                        }
                    }
                    .frame(height: 3)
                    .padding(.horizontal, 40)

                    Text("\(step)%")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .padding(.bottom, 60)
            }
            .frame(maxWidth: .infinity)
        }
        .task {
            withAnimation(.easeInOut(duration: duration)) {
                progress = 1.0
            }
            fireDroplet(progress: 0)
            let stepDuration = duration / 100.0
            let dropletInterval = 0.09
            var nextDropletAt = dropletInterval
            for i in 1...100 {
                do {
                    try await Task.sleep(for: .seconds(stepDuration))
                } catch {
                    break
                }
                step = i
                let elapsed = Double(i) * stepDuration
                if elapsed >= nextDropletAt {
                    nextDropletAt += dropletInterval
                    fireDroplet(progress: elapsed / duration)
                }
            }
        }
    }
}

struct LiquidCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color

    func body(content: Content) -> some View {
        content
            .padding(18)
            .background(tint, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.09), radius: 20, x: 0, y: 6)
    }
}

extension View {
    func liquidCard(cornerRadius: CGFloat = 22, tint: Color = Color.uiSurface) -> some View {
        modifier(LiquidCardModifier(cornerRadius: cornerRadius, tint: tint))
    }
}

struct PressButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.94
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension Color {
    static let uiBackground = Color(UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(hex: "09090B") : UIColor(hex: "FFFFFF")
    })

    static let uiAccent          = Color(hex: "6366F1")
    static let uiAccentSecondary = Color(hex: "34D399")

    static let uiSurface = Color(UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(hex: "18181B") : UIColor(hex: "F4F4F5")
    })
    static let uiSurfaceStrong = Color(UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(hex: "27272A") : UIColor(hex: "E4E4E7")
    })
    static let uiSurfaceInput = Color(UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(hex: "3F3F46") : UIColor(hex: "D4D4D8")
    })

    static let uiStroke = Color(UIColor { t in
        t.userInterfaceStyle == .dark ? .white.withAlphaComponent(0.07) : .black.withAlphaComponent(0.07)
    })
    static let uiStrokeStrong = Color(UIColor { t in
        t.userInterfaceStyle == .dark ? .white.withAlphaComponent(0.14) : .black.withAlphaComponent(0.14)
    })
    static let uiCardStroke = Color(UIColor { t in
        t.userInterfaceStyle == .dark ? .white.withAlphaComponent(0.07) : .black.withAlphaComponent(0.07)
    })

    static let uiTextPrimary = Color(UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(hex: "F4F4F5") : UIColor(hex: "09090B")
    })
    static let uiTextSecondary = Color(UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(hex: "A1A1AA") : UIColor(hex: "52525B")
    })
    static let uiTextMuted = Color(UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(hex: "71717A") : UIColor(hex: "A1A1AA")
    })

    static let uiButtonDisabled = Color(UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(hex: "3F3F46") : UIColor(hex: "D4D4D8")
    })
}

private func _parseHexRGB(_ hex: String) -> (r: Double, g: Double, b: Double) {
    let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    assert(cleaned.count == 6, "Invalid hex color: \(hex)")
    var int: UInt64 = 0
    Scanner(string: cleaned).scanHexInt64(&int)
    return (
        Double((int >> 16) & 0xFF) / 255,
        Double((int >> 8)  & 0xFF) / 255,
        Double(int & 0xFF) / 255
    )
}

extension Color {
    init(hex: String) {
        let (r, g, b) = _parseHexRGB(hex)
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

extension UIColor {
    convenience init(hex: String) {
        let (r, g, b) = _parseHexRGB(hex)
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}

let uiAccentGradient = LinearGradient(
    colors: [Color(hex: "818CF8"), Color(hex: "6366F1"), Color(hex: "4F46E5")],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

extension String {
    var searchNormalized: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "it_IT"))
            .unicodeScalars
            .filter(CharacterSet.alphanumerics.contains)
            .map(String.init)
            .joined()
    }
}

// MARK: - Floating Tab Bar

private struct FloatingTabBar: View {
    let selectedTab: Int
    let todayBadgeCount: Int
    let onSelect: (Int) -> Void
    @AppStorage("preferredColorScheme") private var colorSchemePreference: String = "system"

    private let items: [(icon: String, label: String)] = [
        ("calendar", "Today"),
        ("building.2", "Rooms"),
    ]

    private var themeIcon: String {
        switch colorSchemePreference {
        case "light": return "sun.max.fill"
        case "dark": return "moon.fill"
        default: return "circle.lefthalf.filled"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<items.count, id: \.self) { index in
                Button {
                    onSelect(index)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: items[index].icon)
                            .font(.system(size: 16, weight: selectedTab == index ? .semibold : .regular))
                            .overlay(alignment: .topTrailing) {
                                if index == 0 && todayBadgeCount > 0 && selectedTab != 0 {
                                    Text("\(todayBadgeCount)")
                                        .font(.system(size: 8, weight: .black))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Color.uiAccent))
                                        .offset(x: 8, y: -6)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                        if selectedTab == index {
                            Text(items[index].label)
                                .font(.system(size: 12, weight: .semibold))
                                .transition(.opacity.combined(with: .move(edge: .leading)))
                        }
                    }
                    .foregroundStyle(selectedTab == index ? .white : Color.uiTextSecondary)
                    .padding(.vertical, 12)
                    .padding(.horizontal, selectedTab == index ? 22 : 20)
                    .background(
                        Capsule()
                            .fill(selectedTab == index ? Color.uiAccent : Color.clear)
                    )
                    .animation(.spring(response: 0.32, dampingFraction: 0.78), value: selectedTab)
                }
                .buttonStyle(PressButtonStyle(scale: 0.90))
                .accessibilityLabel(items[index].label)
                .accessibilityAddTraits(selectedTab == index ? [.isSelected] : [])
            }

            Rectangle()
                .fill(Color.uiStroke)
                .frame(width: 1, height: 20)
                .padding(.horizontal, 2)

            Button {
                let next: String
                switch colorSchemePreference {
                case "system": next = "light"
                case "light": next = "dark"
                default: next = "system"
                }
                withAnimation(.easeInOut(duration: 0.2)) { colorSchemePreference = next }
            } label: {
                Image(systemName: themeIcon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.uiTextSecondary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(PressButtonStyle(scale: 0.88))
            .accessibilityLabel("Toggle color scheme")
        }
        .padding(6)
        .background(
            Capsule()
                .fill(Color.uiSurface)
                .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
        )
        .overlay(
            Capsule()
                .strokeBorder(Color.uiStroke, lineWidth: 1)
        )
        .padding(.horizontal, 32)
        .padding(.bottom, 24)
    }
}

// MARK: - Profile

struct ProfileView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var editingUsername: String = ""
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var showingCoursePicker = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    avatarSection
                        .padding(24)

                    Divider()

                    VStack(alignment: .leading, spacing: 14) {
                        sectionHeader("PROGRAMME")

                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.selectedCourse?.name ?? "No programme selected")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.uiTextPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer()

                            Button {
                                showingCoursePicker = true
                            } label: {
                                Text("Change")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.uiAccent)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Capsule().fill(Color.uiAccent.opacity(0.12)))
                            }
                            .buttonStyle(PressButtonStyle(scale: 0.92))
                            .accessibilityLabel("Change programme")
                        }

                        Divider()

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
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)

                    Divider()

                    VStack(alignment: .leading, spacing: 14) {
                        Toggle(isOn: $model.isWorker) {
                            sectionHeader("WORK SHIFTS")
                        }
                        .tint(Color.uiAccent)

                        if model.isWorker {
                            Divider()

                            VStack(spacing: 0) {
                                ForEach(model.workShifts.indices, id: \.self) { index in
                                    WorkShiftRow(shift: $model.workShifts[index])
                                    if index < model.workShifts.count - 1 {
                                        Divider()
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.isWorker)

                    Divider()

                    VStack(alignment: .leading, spacing: 14) {
                        sectionHeader("NOTIFICATIONS")

                        Toggle(isOn: $model.liveActivitiesEnabled) {
                            Label("Live Activity", systemImage: "circle.filled.pattern.diagonalline.rectangle")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.uiTextPrimary)
                        }
                        .tint(Color.uiAccent)

                        Text("Shows the active lecture in Dynamic Island and Lock Screen.")
                            .font(.caption)
                            .foregroundStyle(Color.uiTextMuted)
                            .padding(.leading, 28)

                        Divider()

                        Toggle(isOn: $model.notificationsEnabled) {
                            Label("Lecture reminders", systemImage: "bell.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.uiTextPrimary)
                        }
                        .tint(Color.uiAccent)

                        if model.notificationsEnabled {
                            Divider()

                            Text("Notify me")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.uiTextSecondary)
                                .padding(.top, 4)
                                .padding(.bottom, 4)

                            HStack(spacing: 8) {
                                ForEach([15, 30, 60], id: \.self) { minutes in
                                    Button {
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                            model.notificationLeadMinutes = minutes
                                        }
                                    } label: {
                                        Text(minutes == 60 ? "1h" : "\(minutes)m")
                                            .font(.subheadline.weight(.semibold))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 9)
                                            .background(
                                                model.notificationLeadMinutes == minutes
                                                    ? Color.uiAccent
                                                    : Color.uiSurfaceInput
                                            )
                                            .foregroundStyle(
                                                model.notificationLeadMinutes == minutes ? Color.white : Color.uiTextSecondary
                                            )
                                    }
                                    .buttonStyle(PressButtonStyle(scale: 0.94))
                                    .accessibilityLabel("\(minutes) minutes before")
                                    .accessibilityAddTraits(model.notificationLeadMinutes == minutes ? .isSelected : [])
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                            Text("before each lecture")
                                .font(.caption)
                                .foregroundStyle(Color.uiTextMuted)
                                .padding(.top, 2)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.notificationsEnabled)
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.liveActivitiesEnabled)

                    Divider()

                    Button {
                        saveAndDismiss()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Done")
                                .font(.headline.weight(.semibold))
                            Spacer()
                        }
                        .padding(.vertical, 15)
                        .foregroundStyle(.white)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(uiAccentGradient)
                        )
                    }
                    .buttonStyle(PressButtonStyle(scale: 0.97))
                    .padding(20)
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        saveAndDismiss()
                    }
                    .font(.subheadline.weight(.semibold))
                    .tint(Color.uiAccent)
                }
            }
            .navigationDestination(isPresented: $showingCoursePicker) {
                CoursePickerView(model: model)
            }
        }
        .background { ProfileBackground() }
        .onAppear {
            editingUsername = model.username
        }
        .onChange(of: photoPickerItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    model.saveProfileImage(image)
                }
            }
        }
    }

    private var avatarSection: some View {
        VStack(spacing: 16) {
            PhotosPicker(selection: $photoPickerItem, matching: .images) {
                avatarCircle
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "camera.fill")
                            .font(.caption.weight(.bold))
                            .padding(7)
                            .background(Circle().fill(Color.uiAccent))
                            .foregroundStyle(.white)
                            .offset(x: 4, y: 4)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Profile photo")
            .accessibilityHint("Tap to change photo")

            TextField("Your name", text: $editingUsername)
                .multilineTextAlignment(.center)
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.uiTextPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.uiSurfaceInput)
                )
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var avatarCircle: some View {
        if let image = model.profileImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 88, height: 88)
                .clipShape(Circle())
        } else {
            ZStack {
                Circle()
                    .fill(uiAccentGradient)
                    .frame(width: 88, height: 88)
                let initial = editingUsername.trimmingCharacters(in: .whitespaces).prefix(1).uppercased()
                if initial.isEmpty {
                    Image(systemName: "person.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.white)
                } else {
                    Text(initial)
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .bold))
            .tracking(2)
            .foregroundStyle(Color.uiTextMuted)
    }

    private func saveAndDismiss() {
        model.username = editingUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        dismiss()
    }
}

private struct WorkShiftRow: View {
    @Binding var shift: WorkShift

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(shift.weekdayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(shift.isEnabled ? Color.uiTextPrimary : Color.uiTextMuted)
                Spacer()
                Toggle("", isOn: $shift.isEnabled)
                    .labelsHidden()
                    .tint(Color.uiAccent)
            }
            .padding(.vertical, 12)

            if shift.isEnabled {
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Start")
                            .font(.caption)
                            .foregroundStyle(Color.uiTextSecondary)
                        DatePicker("", selection: startTimeBinding, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .tint(Color.uiAccent)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("End")
                            .font(.caption)
                            .foregroundStyle(Color.uiTextSecondary)
                        DatePicker("", selection: endTimeBinding, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .tint(Color.uiAccent)
                    }
                    Spacer()
                }
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: shift.isEnabled)
    }

    private var startTimeBinding: Binding<Date> {
        Binding(
            get: {
                var c = DateComponents()
                c.hour = shift.startHour
                c.minute = shift.startMinute
                return Calendar.current.date(from: c) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                var updated = shift
                updated.startHour = c.hour ?? 0
                updated.startMinute = c.minute ?? 0
                shift = updated
            }
        )
    }

    private var endTimeBinding: Binding<Date> {
        Binding(
            get: {
                var c = DateComponents()
                c.hour = shift.endHour
                c.minute = shift.endMinute
                return Calendar.current.date(from: c) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                var updated = shift
                updated.endHour = c.hour ?? 0
                updated.endMinute = c.minute ?? 0
                shift = updated
            }
        )
    }
}

private struct CoursePickerView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredCourses: [StudyCourse] {
        let query = searchText.searchNormalized
        guard !query.isEmpty else { return Array(model.allCourses.prefix(40)) }
        return model.allCourses.filter { $0.name.searchNormalized.contains(query) }
    }

    var body: some View {
        ZStack {
            AppBackground()

            if model.isLoadingCourses {
                ProgressView()
                    .tint(Color.uiAccent)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredCourses) { course in
                            Button {
                                model.selectedCourse = course
                                dismiss()
                            } label: {
                                HStack(alignment: .top, spacing: 11) {
                                    Image(systemName: model.selectedCourse?.id == course.id ? "checkmark.circle.fill" : "circle")
                                        .font(.headline)
                                        .foregroundStyle(model.selectedCourse?.id == course.id ? Color.uiAccent : Color.uiTextSecondary)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(course.name)
                                            .font(.subheadline.weight(.semibold))
                                            .multilineTextAlignment(.leading)
                                            .foregroundStyle(Color.uiTextPrimary)
                                            .frame(maxWidth: .infinity, alignment: .leading)

                                        Text(course.facultyName)
                                            .font(.caption)
                                            .foregroundStyle(Color.uiTextMuted)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(model.selectedCourse?.id == course.id ? Color.uiAccent.opacity(0.14) : Color.uiSurface)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(course.name)
                            .accessibilityHint(course.facultyName)
                            .accessibilityAddTraits(model.selectedCourse?.id == course.id ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .searchable(text: $searchText, prompt: "Search programme")
            }
        }
        .navigationTitle("Change programme")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model.allCourses.isEmpty {
                await model.loadCourses()
            }
        }
    }
}
