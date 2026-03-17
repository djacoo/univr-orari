import SwiftUI

struct LessonNoteSheet: View {
    let lesson: Lesson
    @ObservedObject var store: LessonNotesStore
    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $text)
                    .font(.body)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
            .navigationTitle(lesson.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .tint(Color.uiTextSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        store.setNote(text, for: lesson.id, date: lesson.date)
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                    .tint(Color.uiAccent)
                }
            }
            .onAppear {
                text = store.note(for: lesson.id, date: lesson.date) ?? ""
            }
        }
    }
}
