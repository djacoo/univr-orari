import SwiftUI
import PhotosUI

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
                    showLoader(name: "Calendario", duration: 2)
                }
                showingProfile = newValue
            }
        )
    }

    private var tabSelectionBinding: Binding<Int> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                guard newValue != selectedTab else { return }
                selectedTab = newValue
                showLoader(name: newValue == 0 ? "Calendario" : "Aule", duration: 2)
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
        .animation(.spring(response: 0.48, dampingFraction: 0.86), value: model.requiresInitialSetup)
        .onAppear {
            syncSetupStateFromModel()
            showLoader(name: "UniVR Orari", duration: 5)
        }
        .onChange(of: model.requiresInitialSetup) { _, requiresSetup in
            if requiresSetup {
                syncSetupStateFromModel()
            }
        }
        .sheet(isPresented: profileSheetBinding) {
            ProfileView(model: model)
        }
        .overlay {
            if loaderVisible {
                LoaderView(name: loaderName, duration: loaderDuration)
            }
        }
    }

    private var mainTabs: some View {
        TabView(selection: tabSelectionBinding) {
            NavigationStack {
                WeeklyScheduleView(
                    model: model,
                    onEditProfile: { showLoader(name: "Profilo", duration: 2) { showingProfile = true } }
                )
            }
            .tabItem { Label("Calendario", systemImage: "calendar") }
            .tag(0)

            NavigationStack {
                RoomsView(model: model)
            }
            .tabItem { Label("Aule", systemImage: "door.left.hand.open") }
            .tag(1)
        }
        .tint(Color.uiAccent)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
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
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
        }
    }

    private var setupHero: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("UniVR Orari")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.uiAccent)

            Text("Il tuo orario.")
                .font(.system(size: 36, weight: .black, design: .rounded))
                .foregroundStyle(Color.uiTextPrimary)

            Text("Scegli il tuo corso per accedere al calendario lezioni.")
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
                    .accessibilityLabel("Anno \(year)")
                    .accessibilityAddTraits(model.selectedCourseYear == year ? .isSelected : [])
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.uiSurfaceInput)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                                .fill(setupSelectedCourse?.id == course.id ? Color.uiAccent.opacity(0.16) : Color.uiSurfaceInput)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(course.name)
                    .accessibilityHint(course.facultyName)
                    .accessibilityAddTraits(setupSelectedCourse?.id == course.id ? .isSelected : [])
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

struct ProfileBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        ZStack {
            LinearGradient(
                colors: isDark
                    ? [Color(hex: "1C1610"), Color(hex: "1A1F1D")]
                    : [Color(hex: "FDF8F2"), Color(hex: "EDCFB8")],
                startPoint: .top,
                endPoint: .bottom
            )

            Circle()
                .fill(RadialGradient(
                    colors: [Color.uiAccent.opacity(isDark ? 0.14 : 0.22), Color.uiAccent.opacity(0)],
                    center: .center, startRadius: 0, endRadius: 330
                ))
                .frame(width: 520, height: 520)
                .offset(x: 90, y: -170)

            Circle()
                .fill(RadialGradient(
                    colors: [Color(hex: "3F6D5D").opacity(isDark ? 0.10 : 0.18), Color(hex: "3F6D5D").opacity(0)],
                    center: .center, startRadius: 0, endRadius: 280
                ))
                .frame(width: 450, height: 450)
                .offset(x: -110, y: 210)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .drawingGroup()
        .ignoresSafeArea()
    }
}

struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        ZStack {
            LinearGradient(
                colors: [Color.uiBackgroundTop, Color.uiBackgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(RadialGradient(colors: [Color.uiBlobCyan.opacity(isDark ? 0.22 : 0.78), Color.uiBlobCyan.opacity(0)], center: .center, startRadius: 1, endRadius: 310))
                .frame(width: 390, height: 390)
                .offset(x: -100, y: -280)

            Circle()
                .fill(RadialGradient(colors: [Color.uiBlobBlue.opacity(isDark ? 0.18 : 0.55), Color.uiBlobBlue.opacity(0)], center: .center, startRadius: 1, endRadius: 350))
                .frame(width: 430, height: 430)
                .offset(x: 155, y: 240)

            Circle()
                .fill(RadialGradient(colors: [Color.uiBlobViolet.opacity(isDark ? 0.14 : 0.50), Color.uiBlobViolet.opacity(0)], center: .center, startRadius: 1, endRadius: 270))
                .frame(width: 350, height: 350)
                .offset(x: 175, y: -215)
        }
        .drawingGroup()
        .ignoresSafeArea()
    }
}

struct LoaderView: View {
    let name: String
    let duration: Double

    @State private var progress: Double = 0
    @State private var step: Int = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Loading")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.55))
                            .shadow(color: .white.opacity(0.5), radius: 8)
                        Text(name + "...")
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .shadow(color: .white.opacity(0.6), radius: 14)
                            .shadow(color: .white.opacity(0.25), radius: 28)
                            .lineLimit(2)
                    }

                    VStack(alignment: .trailing, spacing: 10) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.12))
                                    .frame(height: 5)
                                Capsule()
                                    .fill(Color.white)
                                    .frame(width: max(5, geo.size.width * progress), height: 5)
                                    .shadow(color: .white.opacity(0.9), radius: 6)
                                    .shadow(color: .white.opacity(0.4), radius: 14)
                            }
                        }
                        .frame(height: 5)

                        Text("\(step)%")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.65))
                            .monospacedDigit()
                            .shadow(color: .white.opacity(0.4), radius: 6)
                    }
                }
                .padding(.horizontal, 36)
                .padding(.bottom, 100)
            }
        }
        .task {
            withAnimation(.easeInOut(duration: duration)) {
                progress = 1.0
            }
            let stepDuration = duration / 100.0
            for i in 1...100 {
                try? await Task.sleep(for: .seconds(stepDuration))
                step = i
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
                    .strokeBorder(Color.uiCardStroke, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
            .shadow(color: .black.opacity(0.03), radius: 2, x: 0, y: 1)
    }
}

extension View {
    func liquidCard(cornerRadius: CGFloat = 22, tint: Color = Color.uiSurface) -> some View {
        modifier(LiquidCardModifier(cornerRadius: cornerRadius, tint: tint))
    }
}

extension Color {
    static let uiBackgroundTop    = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: "1C1610") : UIColor(hex: "F5EFE4") })
    static let uiBackgroundBottom = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: "111A17") : UIColor(hex: "D0E9CB") })

    static let uiAccent          = Color(hex: "C65D3D")
    static let uiAccentSecondary = Color(hex: "3F6D5D")

    static let uiBlobCyan   = Color(hex: "7ECFB5")
    static let uiBlobBlue   = Color(hex: "F0A650")
    static let uiBlobViolet = Color(hex: "D48FB2")

    static let uiSurface       = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: "2B2419").withAlphaComponent(0.82) : .white.withAlphaComponent(0.76) })
    static let uiSurfaceStrong = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: "332B1E").withAlphaComponent(0.94) : .white.withAlphaComponent(0.88) })
    static let uiSurfaceInput  = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: "3B3225").withAlphaComponent(0.98) : .white.withAlphaComponent(0.96) })
    static let uiTabBarBackground = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: "332B1E").withAlphaComponent(0.94) : .white.withAlphaComponent(0.88) })

    static let uiStroke       = Color(UIColor { $0.userInterfaceStyle == .dark ? .white.withAlphaComponent(0.06) : .black.withAlphaComponent(0.08) })
    static let uiStrokeStrong = Color(UIColor { $0.userInterfaceStyle == .dark ? .white.withAlphaComponent(0.12) : .black.withAlphaComponent(0.16) })
    static let uiCardStroke   = Color(UIColor { $0.userInterfaceStyle == .dark ? .white.withAlphaComponent(0.10) : .white.withAlphaComponent(0.55) })

    static let uiTextPrimary   = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: "F0EBE3") : UIColor(hex: "222733") })
    static let uiTextSecondary = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: "C2B4A6") : UIColor(hex: "394253") })
    static let uiTextMuted     = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: "8C7E72") : UIColor(hex: "5A6578") })

    static let uiButtonDisabled = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: "4A4538") : UIColor(hex: "C8CCD5") })
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

extension UIColor {
    convenience init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
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
                VStack(spacing: 16) {
                    avatarCard
                    courseCard
                    workerCard
                    returnButton
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
            }
            .background { ProfileBackground() }
            .navigationTitle("Profilo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fatto") {
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

    private var avatarCard: some View {
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
            .accessibilityLabel("Foto profilo")
            .accessibilityHint("Tocca per cambiare la foto")

            TextField("Il tuo nome", text: $editingUsername)
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
        .liquidCard(cornerRadius: 24, tint: Color.uiSurfaceStrong)
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

    private var courseCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Corso")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.uiTextSecondary)
                    Text(model.selectedCourse?.name ?? "Nessun corso selezionato")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.uiTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button {
                    showingCoursePicker = true
                } label: {
                    Text("Cambia")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.uiAccent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.uiAccent.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cambia corso")
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

    private var workerCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Toggle(isOn: $model.isWorker) {
                Label("Lavoro anche", systemImage: "briefcase.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.uiTextPrimary)
            }
            .tint(Color.uiAccent)

            if model.isWorker {
                Divider()
                    .padding(.top, 14)

                Text("Turni settimanali")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.uiTextSecondary)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

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
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidCard(cornerRadius: 20, tint: Color.uiSurfaceStrong)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.isWorker)
    }

    private var returnButton: some View {
        Button {
            saveAndDismiss()
        } label: {
            HStack {
                Spacer()
                Label("Torna al calendario", systemImage: "calendar")
                    .font(.headline.weight(.semibold))
                Spacer()
            }
            .padding(.vertical, 15)
            .foregroundStyle(Color.uiAccent)
            .background(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(Color.uiAccent.opacity(0.11))
            )
        }
        .buttonStyle(.plain)
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
                        Text("Inizio")
                            .font(.caption)
                            .foregroundStyle(Color.uiTextSecondary)
                        DatePicker("", selection: startTimeBinding, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .tint(Color.uiAccent)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Fine")
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
                .searchable(text: $searchText, prompt: "Cerca corso")
            }
        }
        .navigationTitle("Cambia corso")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model.allCourses.isEmpty {
                await model.loadCourses()
            }
        }
    }
}
