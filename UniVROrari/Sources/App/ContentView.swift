import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var setupCourseSearch = ""
    @State private var setupSelectedCourse: StudyCourse?
    @State private var setupSelectedAcademicYear = DateHelpers.currentAcademicYear()
    @State private var isApplyingSetup = false

    var body: some View {
        ZStack {
            LiquidBackground()

            Group {
                if model.requiresInitialSetup {
                    setupView
                        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                } else {
                    mainTabs
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
        }
        .animation(.spring(response: 0.48, dampingFraction: 0.86), value: model.requiresInitialSetup)
        .onAppear {
            syncSetupStateFromModel()
        }
        .onChange(of: model.requiresInitialSetup) { _, requiresSetup in
            if requiresSetup {
                syncSetupStateFromModel()
            }
        }
    }

    private var mainTabs: some View {
        TabView {
            NavigationStack {
                WeeklyScheduleView(
                    model: model,
                    onEditProfile: {
                        model.reopenInitialSetup()
                    }
                )
            }
            .tabItem {
                Label("Calendario", systemImage: "calendar")
            }

            NavigationStack {
                RoomsView(model: model)
            }
            .tabItem {
                Label("Aule", systemImage: "door.left.hand.open")
            }
        }
        .tint(Color.uiAccent)
        .toolbarBackground(Color.uiTabBarBackground, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.light, for: .tabBar)
    }

    private var setupView: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                setupHero
                setupAcademicYearCard
                setupCourseYearCard
                setupCourseSearchCard

                if model.isLoadingCourses {
                    loadingSetupCard
                } else if setupFilteredCourses.isEmpty {
                    emptySetupCard
                } else {
                    setupCourseSelectionCard
                }

                setupContinueButton
                    .padding(.top, 2)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
    }

    private var setupHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.headline)
                    .foregroundStyle(Color.uiAccent)
                    .padding(10)
                    .background(
                        Circle()
                            .fill(Color.uiAccent.opacity(0.22))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("UniVR Orari")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.uiTextSecondary)
                    Text("Profilo")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Color.uiTextPrimary)
                }
            }

            Text("Solo il necessario per iniziare")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(Color.uiTextPrimary)

            Text("Corso, anno di corso e anno accademico. Poi entri subito nel calendario.")
                .font(.subheadline)
                .foregroundStyle(Color.uiTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidCard(cornerRadius: 26, tint: Color.uiSurfaceStrong)
    }

    private var setupAcademicYearCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Anno accademico")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.uiTextSecondary)

            Picker("Anno accademico", selection: $setupSelectedAcademicYear) {
                ForEach(model.availableAcademicYears, id: \.self) { academicYear in
                    Text(model.academicYearLabel(for: academicYear)).tag(academicYear)
                }
            }
            .pickerStyle(.menu)
            .font(.headline.weight(.semibold))
            .tint(Color.uiAccent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidCard(cornerRadius: 22, tint: Color.uiSurface)
    }

    private var setupCourseYearCard: some View {
        let maxYear = max(1, setupSelectedCourse?.maxYear ?? 3)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Anno di corso")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.uiTextSecondary)

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
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.uiSurfaceInput)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.uiStrokeStrong, lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidCard(cornerRadius: 22, tint: Color.uiSurface)
        .onChange(of: setupSelectedCourse) { _, newCourse in
            let newMax = newCourse?.maxYear ?? 3
            if model.selectedCourseYear > newMax {
                model.selectedCourseYear = newMax
            }
        }
    }

    private var setupCourseSearchCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Corso di studi")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.uiTextSecondary)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.uiAccent)

                TextField("Cerca corso (es. Artificial Intelligence)", text: $setupCourseSearch)
                    .foregroundStyle(Color.uiTextPrimary)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.uiSurfaceInput)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.uiStrokeStrong, lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidCard(cornerRadius: 22, tint: Color.uiSurface)
    }

    private var setupCourseSelectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Seleziona il tuo corso")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.uiTextSecondary)

            LazyVStack(spacing: 8) {
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
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(setupSelectedCourse?.id == course.id ? Color.uiAccent.opacity(0.22) : Color.uiSurfaceInput)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(setupSelectedCourse?.id == course.id ? Color.uiAccent.opacity(0.78) : Color.uiStroke, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidCard(cornerRadius: 22, tint: Color.uiSurface)
    }

    private var loadingSetupCard: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(Color.uiAccent)
            Text("Carico elenco corsi UniVR...")
                .font(.subheadline)
                .foregroundStyle(Color.uiTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidCard(cornerRadius: 22, tint: Color.uiSurface)
    }

    private var emptySetupCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nessun corso trovato")
                .font(.headline)
                .foregroundStyle(Color.uiTextPrimary)

            if let error = model.coursesError {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(Color.uiTextSecondary)
            } else {
                Text("Prova a cambiare testo di ricerca.")
                    .font(.subheadline)
                    .foregroundStyle(Color.uiTextSecondary)
            }

            Button {
                Task {
                    await model.loadCourses()
                }
            } label: {
                Label("Ricarica corsi", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.uiAccent)
                    .padding(.top, 4)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidCard(cornerRadius: 22, tint: Color.uiSurface)
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
                    Text("Apri calendario")
                        .font(.headline.weight(.semibold))
                }
                Spacer()
            }
            .padding(.vertical, 15)
            .foregroundStyle(.white)
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
            .overlay(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(Color.white.opacity(0.20), lineWidth: 1)
            )
            .shadow(color: Color.uiAccent.opacity(selectedCourse == nil ? 0 : 0.36), radius: 14, x: 0, y: 7)
        }
        .disabled(selectedCourse == nil || isApplyingSetup)
    }

    private var setupFilteredCourses: [StudyCourse] {
        let query = setupCourseSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedQuery = query.searchNormalized
        guard !normalizedQuery.isEmpty else {
            return model.allCourses
        }

        return model.allCourses.filter { course in
            course.name.searchNormalized.contains(normalizedQuery)
                || course.facultyName.searchNormalized.contains(normalizedQuery)
        }
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

struct LiquidBackground: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.uiBackgroundTop, Color.uiBackgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.uiBlobCyan, Color.uiBlobCyan.opacity(0)],
                        center: .center,
                        startRadius: 1,
                        endRadius: 280
                    )
                )
                .frame(width: 360, height: 360)
                .offset(x: animate ? -120 : -50, y: animate ? -260 : -210)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.uiBlobBlue, Color.uiBlobBlue.opacity(0)],
                        center: .center,
                        startRadius: 1,
                        endRadius: 320
                    )
                )
                .frame(width: 390, height: 390)
                .offset(x: animate ? 150 : 90, y: animate ? 220 : 160)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.uiBlobViolet, Color.uiBlobViolet.opacity(0)],
                        center: .center,
                        startRadius: 1,
                        endRadius: 250
                    )
                )
                .frame(width: 320, height: 320)
                .offset(x: animate ? 170 : 120, y: animate ? -210 : -150)
        }
        .drawingGroup()
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 14)) {
                animate = true
            }
        }
    }
}

struct LiquidCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color

    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tint)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.44), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 3)
    }
}

extension View {
    func liquidCard(cornerRadius: CGFloat = 22, tint: Color = Color.uiSurface) -> some View {
        modifier(LiquidCardModifier(cornerRadius: cornerRadius, tint: tint))
    }
}

extension Color {
    static let uiBackgroundTop = Color(hex: "F7F2E8")
    static let uiBackgroundBottom = Color(hex: "E6EFE2")

    static let uiAccent = Color(hex: "C65D3D")
    static let uiAccentSecondary = Color(hex: "3F6D5D")

    static let uiBlobCyan = Color(hex: "A3D9C7").opacity(0.55)
    static let uiBlobBlue = Color(hex: "F1BC8D").opacity(0.35)
    static let uiBlobViolet = Color(hex: "DCA9BA").opacity(0.30)

    static let uiSurface = Color.white.opacity(0.74)
    static let uiSurfaceStrong = Color.white.opacity(0.86)
    static let uiSurfaceInput = Color.white.opacity(0.95)
    static let uiTabBarBackground = Color.white.opacity(0.88)

    static let uiStroke = Color.black.opacity(0.08)
    static let uiStrokeStrong = Color.black.opacity(0.16)

    static let uiTextPrimary = Color(hex: "222733")
    static let uiTextSecondary = Color(hex: "394253")
    static let uiTextMuted = Color(hex: "5A6578")

    static let uiButtonDisabled = Color(hex: "C8CCD5")
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r, g, b: UInt64
        switch cleaned.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (255, 255, 255)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}

let uiAccentGradient = LinearGradient(
    colors: [Color(hex: "C65D3D"), Color(hex: "9E4E6C")],
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
