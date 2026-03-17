import SwiftUI

struct SubjectFilterSheet: View {
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
