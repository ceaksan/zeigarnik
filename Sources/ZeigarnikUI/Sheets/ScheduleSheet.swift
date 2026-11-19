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
                        Button("Delete", role: .destructive) {
                            model.deleteSchedule(id: id)
                            dismiss()
                        }
                        Button("Cancel") { confirmDelete = false }
                    } else {
                        Button("Delete", role: .destructive) { confirmDelete = true }
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

/// A note card with a context-menu delete that asks inline; no system dialog.
struct DeletableNoteCard: View {
    let date: String
    let text: String
    let onDelete: () -> Void
    @State private var confirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            NoteCard(date: date, text: text, scheduled: false)
            if confirming {
                HStack {
                    Text("Delete this note?").font(Theme.small)
                    Button("Delete", role: .destructive, action: onDelete)
                    Button("Cancel") { confirming = false }
                }
                .controlSize(.small)
            }
        }
        .contextMenu { Button("Delete", role: .destructive) { confirming = true } }
    }
}
