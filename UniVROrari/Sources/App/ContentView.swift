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
                    showLoader(name: "Calendario", duration: 3)
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
                showLoader(name: newValue == 0 ? "Calendario" : "Aule", duration: 3)
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
                    onEditProfile: { showLoader(name: "Profilo", duration: 3) { showingProfile = true } }
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
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "FDF8F2"), Color(hex: "EDCFB8")],
                startPoint: .top,
                endPoint: .bottom
            )

            Circle()
                .fill(RadialGradient(
                    colors: [Color.uiAccent.opacity(0.22), Color.uiAccent.opacity(0)],
                    center: .center, startRadius: 0, endRadius: 330
                ))
                .frame(width: 520, height: 520)
                .offset(x: 90, y: -170)

            Circle()
                .fill(RadialGradient(
                    colors: [Color(hex: "3F6D5D").opacity(0.18), Color(hex: "3F6D5D").opacity(0)],
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
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.uiBackgroundTop, Color.uiBackgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(RadialGradient(colors: [Color.uiBlobCyan, Color.uiBlobCyan.opacity(0)], center: .center, startRadius: 1, endRadius: 310))
                .frame(width: 390, height: 390)
                .offset(x: -100, y: -280)

            Circle()
                .fill(RadialGradient(colors: [Color.uiBlobBlue, Color.uiBlobBlue.opacity(0)], center: .center, startRadius: 1, endRadius: 350))
                .frame(width: 430, height: 430)
                .offset(x: 155, y: 240)

            Circle()
                .fill(RadialGradient(colors: [Color.uiBlobViolet, Color.uiBlobViolet.opacity(0)], center: .center, startRadius: 1, endRadius: 270))
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
                    .strokeBorder(Color.white.opacity(0.55), lineWidth: 0.5)
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
    static let uiBackgroundTop = Color(hex: "F5EFE4")
    static let uiBackgroundBottom = Color(hex: "D0E9CB")

    static let uiAccent = Color(hex: "C65D3D")
    static let uiAccentSecondary = Color(hex: "3F6D5D")

    static let uiBlobCyan = Color(hex: "7ECFB5").opacity(0.78)
    static let uiBlobBlue = Color(hex: "F0A650").opacity(0.55)
    static let uiBlobViolet = Color(hex: "D48FB2").opacity(0.50)

    static let uiSurface = Color.white.opacity(0.76)
    static let uiSurfaceStrong = Color.white.opacity(0.88)
    static let uiSurfaceInput = Color.white.opacity(0.96)
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
