import SwiftUI

struct RoomsView: View {
    @ObservedObject var model: AppModel
    @State private var roomSearchText = ""
    @State private var selectedRoomName: String?
    @State private var freeNowOnly = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    Color.clear.frame(height: 0).id("rooms-top")
                    filterCard
                    roomSearchCard
                    roomsStateSection
                        .animation(.spring(response: 0.38, dampingFraction: 0.84), value: model.isLoadingRooms)
                        .animation(.spring(response: 0.38, dampingFraction: 0.84), value: model.roomsError)
                    roomScheduleSection
                        .animation(.spring(response: 0.38, dampingFraction: 0.84), value: activeRoomName)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
            }
            .scrollDismissesKeyboard(.immediately)
            .onChange(of: model.selectedRoomsDate) { _, _ in
                withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
                    proxy.scrollTo("rooms-top", anchor: .top)
                }
            }
            .onChange(of: model.selectedBuilding?.id) { _, _ in
                withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
                    proxy.scrollTo("rooms-top", anchor: .top)
                }
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: activeRoomName)
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.8), trigger: model.selectedBuilding?.id)
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.8), trigger: model.selectedRoomsDate)
        .navigationTitle("Rooms")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await model.refreshRooms()
        }
        .task(id: "\(model.selectedBuilding?.id ?? "")|\(model.selectedRoomsDate.timeIntervalSince1970)") {
            guard !model.requiresInitialSetup else { return }
            await model.refreshRooms()
            ensureSelectedRoomIsValid()
        }
        .onChange(of: roomSearchText) { _, _ in
            let trimmed = roomSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if let selectedRoomName {
                if trimmed.isEmpty || !selectedRoomName.searchNormalized.contains(trimmed.searchNormalized) {
                    self.selectedRoomName = nil
                }
            }
        }
        .onChange(of: model.selectedRoomsDate) { _, newDate in
            if !Calendar.current.isDateInToday(newDate) {
                freeNowOnly = false
            }
        }
    }

    private var filterCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.isLoadingBuildings {
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(Color.uiAccent)
                        .scaleEffect(1.1)
                    Text("Loading buildings…")
                        .font(.subheadline)
                        .foregroundStyle(Color.uiTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if let buildingsError = model.buildingsError, model.buildings.isEmpty {
                Text(buildingsError)
                    .font(.subheadline)
                    .foregroundStyle(Color.uiTextSecondary)
            } else {
                Picker("Building", selection: selectedBuildingBinding) {
                    ForEach(model.buildings) { building in
                        Text(building.name).tag(Optional(building))
                    }
                }
                .pickerStyle(.menu)
                .tint(Color.uiAccent)

                HStack(spacing: 10) {
                    DatePicker(
                        "Date",
                        selection: $model.selectedRoomsDate,
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.compact)
                    .tint(Color.uiAccent)

                    if !Calendar.current.isDateInToday(model.selectedRoomsDate) {
                        Button {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                                model.selectedRoomsDate = DateHelpers.startOfDay(for: Date())
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
                        .accessibilityHint("Jump to today")
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.82), value: Calendar.current.isDateInToday(model.selectedRoomsDate))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidCard(cornerRadius: 22, tint: Color.uiSurfaceStrong)
    }

    private var roomSearchCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Search room")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.uiTextSecondary)

                Spacer()

                if Calendar.current.isDateInToday(model.selectedRoomsDate) {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                            freeNowOnly.toggle()
                            selectedRoomName = nil
                            roomSearchText = ""
                        }
                    } label: {
                        Label("Free now", systemImage: "door.left.hand.open")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(freeNowOnly ? Color.uiAccentSecondary : Color.uiSurfaceInput))
                            .foregroundStyle(freeNowOnly ? .white : Color.uiTextSecondary)
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.impact(weight: .medium, intensity: 0.8), trigger: freeNowOnly)
                    .accessibilityLabel("Show rooms free right now")
                    .accessibilityAddTraits(freeNowOnly ? .isSelected : [])
                }
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.uiAccent)
                TextField("e.g. T.03", text: $roomSearchText)
                    .foregroundStyle(Color.uiTextPrimary)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.uiSurfaceInput)
            )
            .opacity(freeNowOnly ? 0.4 : 1)
            .disabled(freeNowOnly)

            if !roomSuggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(displayedRoomSuggestions, id: \.self) { roomName in
                            Button {
                                withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                                    selectedRoomName = roomName
                                    roomSearchText = roomName
                                }
                            } label: {
                                Text(roomName)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .fill(selectedRoomName == roomName ? Color.uiAccent.opacity(0.18) : Color.uiSurfaceInput)
                                    )
                                    .foregroundStyle(selectedRoomName == roomName ? Color.uiAccent : Color.uiTextPrimary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(roomName)
                            .accessibilityAddTraits(selectedRoomName == roomName ? .isSelected : [])
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidCard(cornerRadius: 20, tint: Color.uiSurface)
    }

    @ViewBuilder
    private var roomsStateSection: some View {
        if model.isLoadingRooms {
            VStack(spacing: 16) {
                ProgressView()
                    .tint(Color.uiAccent)
                    .scaleEffect(1.5)
                    .frame(height: 28)
                Text("Loading room availability…")
                    .font(.subheadline)
                    .foregroundStyle(Color.uiTextSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .liquidCard(cornerRadius: 18, tint: Color.uiSurface)
            .transition(.opacity)
        } else if let roomsError = model.roomsError {
            let isOffline = roomsError.localizedCaseInsensitiveContains("offline")
            VStack(alignment: .leading, spacing: 6) {
                Label(
                    isOffline ? "Offline data" : "Load error",
                    systemImage: isOffline ? "wifi.slash" : "exclamationmark.triangle"
                )
                .font(.headline)
                .foregroundStyle(isOffline ? Color.uiTextSecondary : Color.uiTextPrimary)
                Text(roomsError)
                    .font(.subheadline)
                    .foregroundStyle(Color.uiTextSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidCard(cornerRadius: 18, tint: isOffline ? Color.uiSurface : Color.red.opacity(0.16))
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var roomScheduleSection: some View {
        if let roomName = activeRoomName {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(roomName)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.uiTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer()

                    Text(DateHelpers.dayMonthFormatter.string(from: model.selectedRoomsDate).capitalized)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.uiAccent)
                }

                if selectedRoomLessons.isEmpty {
                    Text("No bookings today.")
                        .font(.subheadline)
                        .foregroundStyle(Color.uiTextSecondary)
                        .padding(.vertical, 4)
                } else {
                    VStack(spacing: 10) {
                        ForEach(selectedRoomLessons) { lesson in
                            RoomLessonRow(lesson: lesson)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                }

                Divider()
                    .overlay(Color.uiStrokeStrong)

                Text("Free slots")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.uiTextSecondary)

                if selectedRoomFreeSlots.isEmpty {
                    Text("No free slots detected.")
                        .font(.subheadline)
                        .foregroundStyle(Color.uiTextSecondary)
                } else {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(selectedRoomFreeSlots) { slot in
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(Color.uiAccentSecondary)
                                Text("\(slot.fromTime) - \(slot.toTime)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.uiTextPrimary)
                                Spacer()
                            }
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.uiAccentSecondary.opacity(0.10))
                            )
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidCard(cornerRadius: 20, tint: Color.uiSurface)
            .transition(.opacity)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Select a room")
                    .font(.headline)
                    .foregroundStyle(Color.uiTextPrimary)
                Text("Search for a room to view its daily schedule and free periods.")
                    .font(.subheadline)
                    .foregroundStyle(Color.uiTextSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidCard(cornerRadius: 20, tint: Color.uiSurface)
            .transition(.opacity)
        }
    }

    private var selectedBuildingBinding: Binding<Building?> {
        Binding(
            get: { model.selectedBuilding },
            set: { model.selectedBuilding = $0 }
        )
    }

    private var roomSuggestions: [String] {
        let base: [String]
        if freeNowOnly {
            base = model.allRoomNames.filter { isCurrentlyFree($0) }
        } else {
            base = model.allRoomNames
        }
        let query = roomSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedQuery = query.searchNormalized
        guard !normalizedQuery.isEmpty else { return base }
        return base.filter { $0.searchNormalized.contains(normalizedQuery) }
    }

    private func isCurrentlyFree(_ roomName: String) -> Bool {
        guard Calendar.current.isDateInToday(model.selectedRoomsDate) else { return false }
        let now = Date()
        let calendar = Calendar.current
        let currentMins = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        return model.freeRoomSlots.filter { $0.roomName == roomName }.contains { slot in
            let from = slot.fromTime.split(separator: ":").compactMap { Int($0) }
            let to   = slot.toTime.split(separator: ":").compactMap { Int($0) }
            guard from.count == 2, to.count == 2 else { return false }
            return currentMins >= from[0] * 60 + from[1] && currentMins < to[0] * 60 + to[1]
        }
    }

    private var displayedRoomSuggestions: [String] {
        let query = roomSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return Array(roomSuggestions.prefix(20))
        }
        return Array(roomSuggestions.prefix(40))
    }

    private var activeRoomName: String? {
        if let selectedRoomName {
            return selectedRoomName
        }

        let query = roomSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return nil
        }

        return roomSuggestions.first
    }

    private var selectedRoomLessons: [RoomLesson] {
        guard let activeRoomName else { return [] }
        return model.occupiedRooms.first(where: { $0.roomName == activeRoomName })?.lessons ?? []
    }

    private var selectedRoomFreeSlots: [FreeRoomSlot] {
        guard let activeRoomName else { return [] }
        return model.freeRoomSlots.filter { $0.roomName == activeRoomName }
    }

    private func ensureSelectedRoomIsValid() {
        if let selectedRoomName, !model.allRoomNames.contains(selectedRoomName) {
            self.selectedRoomName = nil
        }
    }
}

private struct RoomLessonRow: View {
    let lesson: RoomLesson

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
                    Text("\(lesson.fromTime) – \(lesson.toTime)")
                        .font(.caption.weight(.bold))
                        .kerning(0.2)
                }
                .foregroundStyle(Color.uiAccent)

                Text(lesson.subject)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.uiTextPrimary)

                HStack(spacing: 10) {
                    if !lesson.professor.isEmpty {
                        Label(lesson.professor, systemImage: "person.fill")
                            .lineLimit(1)
                    }
                    if !lesson.courseName.isEmpty {
                        Text(lesson.courseName)
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
}
