import SwiftUI

struct RoomsView: View {
    @ObservedObject var model: AppModel
    @State private var roomSearchText = ""
    @State private var selectedRoomName: String?
    @State private var freeNowOnly = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 0).id("rooms-top")

                    filterRow
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                    Divider()
                        .padding(.top, 16)
                        .padding(.horizontal, 20)

                    searchSection
                        .padding(.top, 16)
                        .padding(.horizontal, 20)

                    if model.isLoadingRooms {
                        loadingView
                            .padding(.top, 40)
                    } else if let err = model.roomsError {
                        errorView(err)
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                    } else if let roomName = activeRoomName {
                        roomDetailSection(roomName: roomName)
                            .padding(.horizontal, 20)
                            .padding(.top, 28)
                    } else if !model.isLoadingRooms {
                        emptyPrompt
                            .padding(.horizontal, 20)
                            .padding(.top, 48)
                    }

                    Color.clear.frame(height: 100)
                }
            }
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 80) }
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
        .refreshable { await model.refreshRooms() }
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

    // MARK: - Filter row

    private var filterRow: some View {
        HStack(spacing: 12) {
            if model.isLoadingBuildings {
                ProgressView().tint(Color.uiAccent).scaleEffect(0.9)
                Text("Loading…")
                    .font(.subheadline)
                    .foregroundStyle(Color.uiTextSecondary)
            } else if let err = model.buildingsError, model.buildings.isEmpty {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(Color.uiTextSecondary)
            } else {
                Menu {
                    ForEach(model.buildings) { building in
                        Button(building.name) { model.selectedBuilding = building }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "building.2")
                            .font(.system(size: 11, weight: .semibold))
                        Text(model.selectedBuilding?.name ?? "Building")
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(Color.uiAccent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.uiAccent.opacity(0.10)))
                }

                DatePicker("", selection: $model.selectedRoomsDate, displayedComponents: [.date])
                    .datePickerStyle(.compact)
                    .tint(Color.uiAccent)
                    .labelsHidden()

                if !Calendar.current.isDateInToday(model.selectedRoomsDate) {
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                            model.selectedRoomsDate = DateHelpers.startOfDay(for: Date())
                        }
                    } label: {
                        Text("Today")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.uiAccent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.uiAccent.opacity(0.10)))
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            Spacer(minLength: 0)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: Calendar.current.isDateInToday(model.selectedRoomsDate))
    }

    // MARK: - Search + chips

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.uiTextMuted)
                    TextField("Search room…", text: $roomSearchText)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.uiTextPrimary)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !roomSearchText.isEmpty {
                        Button {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.75)) {
                                roomSearchText = ""
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(Color.uiTextMuted)
                        }
                        .buttonStyle(.plain)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.uiSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .opacity(freeNowOnly ? 0.4 : 1)
                .disabled(freeNowOnly)
                .animation(.easeInOut(duration: 0.18), value: freeNowOnly)

                if Calendar.current.isDateInToday(model.selectedRoomsDate) {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                            freeNowOnly.toggle()
                            selectedRoomName = nil
                            roomSearchText = ""
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(freeNowOnly ? .white : Color.uiAccentSecondary)
                                .frame(width: 6, height: 6)
                            Text("Free")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(freeNowOnly ? .white : Color.uiAccentSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            Capsule().fill(freeNowOnly ? Color.uiAccentSecondary : Color.uiAccentSecondary.opacity(0.12))
                        )
                    }
                    .buttonStyle(PressButtonStyle(scale: 0.92))
                    .sensoryFeedback(.impact(weight: .medium, intensity: 0.8), trigger: freeNowOnly)
                    .accessibilityLabel("Show rooms free right now")
                    .accessibilityAddTraits(freeNowOnly ? .isSelected : [])
                }
            }

            if !displayedRoomSuggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(displayedRoomSuggestions, id: \.self) { name in
                            roomChip(name)
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
        }
    }

    private func roomChip(_ name: String) -> some View {
        let isSelected = selectedRoomName == name
        let isFree = freeNowOnly && isCurrentlyFree(name)
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                selectedRoomName = name
                roomSearchText = name
            }
        } label: {
            HStack(spacing: 5) {
                if isFree {
                    Circle()
                        .fill(Color.uiAccentSecondary)
                        .frame(width: 5, height: 5)
                }
                Text(name)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.uiAccent : Color.uiTextPrimary)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? Color.uiAccent.opacity(0.10) : Color.uiSurface)
                    .overlay(
                        Capsule().strokeBorder(isSelected ? Color.uiAccent.opacity(0.35) : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Room detail

    private func roomDetailSection(roomName: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(roomName)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Color.uiTextPrimary)
                    Text(DateHelpers.dayMonthFormatter.string(from: model.selectedRoomsDate).capitalized)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.uiTextMuted)
                }
                Spacer()
                nowStatusBadge(for: roomName)
            }
            .padding(.bottom, 20)

            // Occupancy bar
            occupancyBar(for: roomName)
                .padding(.bottom, 8)
            hourAxis
                .padding(.bottom, 24)

            Divider()

            // Bookings
            if selectedRoomLessons.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.uiAccentSecondary)
                    Text("No bookings")
                        .font(.subheadline)
                        .foregroundStyle(Color.uiTextSecondary)
                }
                .padding(.vertical, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(selectedRoomLessons.enumerated()), id: \.element.id) { idx, lesson in
                        if idx > 0 {
                            Divider().padding(.leading, 62)
                        }
                        RoomLessonRow(lesson: lesson)
                    }
                }
                .padding(.top, 4)
            }

            // Free slots
            if !selectedRoomFreeSlots.isEmpty {
                Divider().padding(.top, 8)

                Text("FREE SLOTS")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(Color.uiTextMuted)
                    .padding(.top, 16)
                    .padding(.bottom, 10)

                VStack(spacing: 8) {
                    ForEach(selectedRoomFreeSlots) { slot in
                        HStack {
                            Text("\(slot.fromTime) – \(slot.toTime)")
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.uiAccentSecondary)
                            Spacer()
                            let mins = freeSlotDuration(slot)
                            if mins > 0 {
                                Text(durationString(mins))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color.uiTextMuted)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Color.uiSurface))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.uiAccentSecondary.opacity(0.07))
                        )
                    }
                }
            }
        }
    }

    private func nowStatusBadge(for roomName: String) -> some View {
        let isToday = Calendar.current.isDateInToday(model.selectedRoomsDate)
        guard isToday else { return AnyView(EmptyView()) }
        let free = isCurrentlyFree(roomName)
        return AnyView(
            HStack(spacing: 5) {
                Circle()
                    .fill(free ? Color.uiAccentSecondary : Color.red.opacity(0.7))
                    .frame(width: 6, height: 6)
                Text(free ? "Free now" : "Occupied")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(free ? Color.uiAccentSecondary : Color.red.opacity(0.8))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(free ? Color.uiAccentSecondary.opacity(0.10) : Color.red.opacity(0.08))
            )
        )
    }

    private func occupancyBar(for roomName: String) -> some View {
        let dayStart = 8 * 60
        let dayEnd = 22 * 60
        let span = CGFloat(dayEnd - dayStart)
        let isToday = Calendar.current.isDateInToday(model.selectedRoomsDate)

        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.uiAccentSecondary.opacity(0.14))
                    .frame(height: 10)

                ForEach(selectedRoomLessons) { lesson in
                    let s = CGFloat(max(0, lesson.fromTime.minutesSinceMidnight - dayStart))
                    let e = CGFloat(min(span, CGFloat(lesson.toTime.minutesSinceMidnight - dayStart)))
                    let x = s / span * geo.size.width
                    let w = max(2, (e - s) / span * geo.size.width)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.uiAccent.opacity(0.7))
                        .frame(width: w, height: 10)
                        .offset(x: x)
                }

                if isToday {
                    let cal = Calendar.current
                    let now = Date()
                    let nowMins = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
                    let clamped = max(dayStart, min(dayEnd, nowMins))
                    let x = CGFloat(clamped - dayStart) / span * geo.size.width
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.red)
                            .frame(width: 2, height: 18)
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                            .offset(y: 4)
                    }
                    .offset(x: x - 1, y: -4)
                }
            }
            .frame(height: 10)
        }
        .frame(height: 10)
    }

    private var hourAxis: some View {
        HStack(spacing: 0) {
            ForEach([8, 10, 12, 14, 16, 18, 20, 22], id: \.self) { hour in
                Text(String(format: "%02d", hour))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.uiTextMuted)
                    .frame(maxWidth: .infinity, alignment: hour == 8 ? .leading : (hour == 22 ? .trailing : .center))
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView().tint(Color.uiAccent).scaleEffect(1.2)
            Text("Loading room availability…")
                .font(.subheadline)
                .foregroundStyle(Color.uiTextSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func errorView(_ msg: String) -> some View {
        let isOffline = msg.localizedCaseInsensitiveContains("offline")
        return HStack(spacing: 12) {
            Image(systemName: isOffline ? "wifi.slash" : "exclamationmark.triangle")
                .foregroundStyle(isOffline ? Color.uiTextMuted : .red)
            VStack(alignment: .leading, spacing: 3) {
                Text(isOffline ? "Offline data" : "Load error")
                    .font(.subheadline.weight(.semibold))
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(Color.uiTextMuted)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            isOffline ? Color.uiSurface : Color.red.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    private var emptyPrompt: some View {
        VStack(spacing: 8) {
            Image(systemName: "door.left.hand.open")
                .font(.system(size: 36))
                .foregroundStyle(Color.uiTextMuted)
                .padding(.bottom, 4)
            Text("Find a room")
                .font(.headline)
                .foregroundStyle(Color.uiTextPrimary)
            Text("Search by name or tap a chip to view its schedule and free periods.")
                .font(.subheadline)
                .foregroundStyle(Color.uiTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private var roomSuggestions: [String] {
        let base = freeNowOnly ? model.allRoomNames.filter { isCurrentlyFree($0) } : model.allRoomNames
        let query = roomSearchText.trimmingCharacters(in: .whitespacesAndNewlines).searchNormalized
        guard !query.isEmpty else { return base }
        return base.filter { $0.searchNormalized.contains(query) }
    }

    private func isCurrentlyFree(_ roomName: String) -> Bool {
        guard Calendar.current.isDateInToday(model.selectedRoomsDate) else { return false }
        let now = Date()
        let cal = Calendar.current
        let currentMins = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        return model.freeRoomSlots.filter { $0.roomName == roomName }.contains { slot in
            let from = slot.fromTime.split(separator: ":").compactMap { Int($0) }
            let to   = slot.toTime.split(separator: ":").compactMap { Int($0) }
            guard from.count == 2, to.count == 2 else { return false }
            return currentMins >= from[0] * 60 + from[1] && currentMins < to[0] * 60 + to[1]
        }
    }

    private var displayedRoomSuggestions: [String] { Array(roomSuggestions.prefix(40)) }

    private var activeRoomName: String? {
        if let selectedRoomName { return selectedRoomName }
        let query = roomSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }
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

    private func freeSlotDuration(_ slot: FreeRoomSlot) -> Int {
        let from = slot.fromTime.split(separator: ":").compactMap { Int($0) }
        let to   = slot.toTime.split(separator: ":").compactMap { Int($0) }
        guard from.count == 2, to.count == 2 else { return 0 }
        return (to[0] * 60 + to[1]) - (from[0] * 60 + from[1])
    }

    private func durationString(_ mins: Int) -> String {
        if mins < 60 { return "\(mins)m" }
        let h = mins / 60; let m = mins % 60
        return m == 0 ? "\(h)h" : "\(h)h\(m)m"
    }
}

// MARK: - Room Lesson Row

private struct RoomLessonRow: View {
    let lesson: RoomLesson

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .trailing, spacing: 3) {
                Text(lesson.fromTime)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.uiAccent)
                Text(lesson.toTime)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.uiTextMuted)
            }
            .frame(width: 46)

            Rectangle()
                .fill(Color.uiAccent.opacity(0.4))
                .frame(width: 2)
                .padding(.vertical, 4)
                .padding(.horizontal, 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(lesson.subject)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.uiTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    if !lesson.professor.isEmpty {
                        Label(lesson.professor, systemImage: "person")
                            .lineLimit(1)
                    }
                    if !lesson.courseName.isEmpty {
                        Text(lesson.courseName).lineLimit(1)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(Color.uiTextMuted)
            }
            .padding(.trailing, 12)
        }
        .padding(.vertical, 12)
    }
}
