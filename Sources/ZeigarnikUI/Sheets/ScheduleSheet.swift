import SwiftUI
import ZeigarnikKit

struct ScheduleSheet: View {
    let model: AppModel
    let calendarTitle: String?
    let calendarWarning: String?
    let onSave: (ScheduleDraft) -> Void
    @Environment(\.dismiss) private var dismiss
    @State var draft: ScheduleDraft
    @State private var error: String?
    @State private var confirmDelete = false
    private let projectLocked: Bool

    init(model: AppModel, draft: ScheduleDraft, calendarTitle: String?, calendarWarning: String?, onSave: @escaping (ScheduleDraft) -> Void) {
        self.model = model
        self.calendarTitle = calendarTitle
        self.calendarWarning = calendarWarning
        self.onSave = onSave
        _draft = State(initialValue: draft)
        projectLocked = draft.id != nil || (draft.projectId != nil && !draft.title.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(heading).font(.system(size: 14, weight: .semibold))
            if !projectLocked {
                Picker("Project", selection: $draft.projectId) {
                    Text("Select a project").tag(String?.none)
                    ForEach(projects, id: \.id) { Text($0.displayName).tag(Optional($0.id)) }
                }
            }
            TextField("Title", text: $draft.title)
            DatePicker("Date and time", selection: $draft.start)
                .environment(\.locale, model.calendar.locale ?? .autoupdatingCurrent)
                .environment(\.calendar, model.calendar)
                .environment(\.timeZone, model.calendar.timeZone)
            Picker("Duration", selection: $draft.duration) {
                ForEach(durations, id: \.self) { Text(Self.label($0)).tag($0) }
            }
            Toggle("Also add to macOS Calendar" + (calendarTitle.map { " (calendar: \($0))" } ?? ""), isOn: $draft.addToCalendar)
            if draft.addToCalendar, let calendarWarning {
                Text(calendarWarning).font(Theme.small).foregroundStyle(Theme.warn)
            }
            if let error { Text(error).font(Theme.small).foregroundStyle(Theme.warn) }
            HStack {
                if let id = draft.id {
                    if confirmDelete {
                        Text("Are you sure?").font(Theme.small)
                        Button("Cancel") { confirmDelete = false }
                        Button("Delete", role: .destructive) {
                            model.deleteSchedule(id: id)
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.danger)
                    } else {
                        Button("Delete", role: .destructive) { confirmDelete = true }.foregroundStyle(Theme.danger)
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save", action: save).keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
            .padding(.top, 6)
        }
        .padding(16)
        .frame(width: 400)
    }

    private var heading: String {
        if draft.id != nil { return "Edit Schedule · \(draft.projectId.map(model.displayName) ?? "")" }
        if projectLocked, let id = draft.projectId { return "Schedule · \(model.displayName(id))" }
        return "Schedule · Select a Project"
    }

    private var projects: [ProjectRow] {
        model.rows.filter { $0.state == .active }.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    private var durations: [TimeInterval] {
        let base: [TimeInterval] = [1800, 3600, 5400, 7200, 10800]
        return base.contains(draft.duration) ? base : (base + [draft.duration]).sorted()
    }

    static func label(_ seconds: TimeInterval) -> String {
        Format.duration(seconds)
    }

    private func save() {
        do {
            try model.saveSchedule(draft)
            onSave(draft)
            dismiss()
        } catch ModelError.projectRequired {
            error = "Select a project for the schedule."
        } catch {
            self.error = "Could not save: \(error)"
        }
    }
}

/// A note card with edit and delete under the text. Both work inline (no system dialog); the context menu offers the same.
/// ⌘↩ and Esc are read from the focused editor, not as button shortcuts, so they do not clash with "Add Note".
struct EditableNoteCard: View {
    let date: String
    let text: String
    let onSave: (String) throws -> Void
    let onDelete: () -> Void
    @State private var editing = false
    @State private var confirming = false
    @State private var draft = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if editing {
                InlineNoteEditor(text: $draft, saveTitle: "Save", error: error, onSave: save, onCancel: cancel)
            } else {
                NoteCard(date: date, text: text, scheduled: false) {
                    if confirming {
                        HStack(spacing: 8) {
                            Text("Delete?").font(Theme.small)
                            Button("Cancel") { confirming = false }
                            Button("Delete", role: .destructive, action: onDelete)
                                .buttonStyle(.borderedProminent)
                                .tint(Theme.danger)
                        }
                        .controlSize(.small)
                    } else {
                        HStack(spacing: 10) {
                            Button(action: edit) { Image(systemName: "pencil") }.help("Edit note")
                            Button { confirming = true } label: { Image(systemName: "trash") }.help("Delete note")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Theme.muted)
                        .font(Theme.small)
                    }
                }
            }
        }
        .contextMenu {
            Button("Edit", action: edit)
            Button("Delete", role: .destructive) { confirming = true }
        }
    }

    private func edit() {
        draft = text
        error = nil
        confirming = false
        editing = true
    }

    private func cancel() {
        editing = false
        error = nil
    }

    private func save() {
        do {
            try onSave(draft)
            editing = false
            error = nil
        } catch {
            self.error = "Could not save: \(error)"
        }
    }
}

/// The note editor used in place of a card: ⌘↩ saves and Esc cancels, read from the focused editor.
struct InlineNoteEditor: View {
    @Binding var text: String
    let saveTitle: String
    let error: String?
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NoteInput(text: $text, placeholder: "Note", submit: onSave)
            .onKeyPress(keys: [.return]) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                onSave()
                return .handled
            }
            .onKeyPress(.escape) { onCancel(); return .handled }
        HStack {
            Text("⌘↩ saves, Esc cancels").font(Theme.small).foregroundStyle(Theme.muted)
            Spacer()
            Button("Cancel", action: onCancel)
            Button(saveTitle, action: onSave).buttonStyle(.borderedProminent)
        }
        .controlSize(.small)
        if let error { Text(error).font(Theme.small).foregroundStyle(Theme.warn) }
    }
}

/// A suggested note from the project's state. Accept opens it in the editor, so the owner can change the text before it
/// becomes a note; dismiss hides it until the state changes (ADR-006).
struct DraftNoteCard: View {
    let text: String
    let onAccept: (String) throws -> Void
    let onDismiss: () -> Void
    @State private var editing = false
    @State private var draft = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if editing {
                InlineNoteEditor(text: $draft, saveTitle: "Add Note", error: error, onSave: accept, onCancel: { editing = false; error = nil })
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Draft").font(Theme.chip).foregroundStyle(Theme.muted)
                        Spacer(minLength: 8)
                        HStack(spacing: 10) {
                            Button(action: edit) { Image(systemName: "checkmark") }.help("Accept as a note")
                            Button(action: onDismiss) { Image(systemName: "xmark") }.help("Dismiss until this changes")
                        }
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Theme.muted)
                    .font(Theme.small)
                    Text(text).font(Theme.body).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.corner).strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
        }
        .contextMenu {
            Button("Accept as Note…", action: edit)
            Button("Dismiss", action: onDismiss)
        }
    }

    private func edit() {
        draft = text
        error = nil
        editing = true
    }

    private func accept() {
        do {
            try onAccept(draft)
            editing = false
            error = nil
        } catch {
            self.error = "Could not save: \(error)"
        }
    }
}
