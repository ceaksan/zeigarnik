import SwiftUI
import ZeigarnikKit

struct DayInspector: View {
    let model: AppModel
    let day: String
    var onSchedule: (ScheduleDraft) -> Void = { _ in }
    @State private var detail = DayDetail()
    @State private var noteText = ""
    @State private var noteProject: String?
    @State private var noteError: String?

    var body: some View {
        let slices = model.activity.slices(day: day)
        let total = model.activity.dayTotal(day)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(Format.dayTitle(day, calendar: model.calendar)).font(Theme.title)
                Text(total > 0 ? "\(Format.duration(total)) active work" : "No recorded work")
                    .font(Theme.small).foregroundStyle(Theme.muted).padding(.bottom, 4)
                if !detail.items.isEmpty {
                    SectionHeader("Scheduled")
                    VStack(spacing: 6) {
                        ForEach(detail.items) { item in
                            ScheduledItemCard(date: "\(UIFormat.time(item.start, model.calendar)) · \(model.displayName(item.projectId))", item: item,
                                              onEdit: { onSchedule(ScheduleDraft(id: item.id, projectId: item.projectId, title: item.title, start: item.start,
                                                                                 duration: item.duration, addToCalendar: item.wantsCalendar)) },
                                              onDelete: { model.deleteSchedule(id: item.id) })
                        }
                    }
                }
                SectionHeader("Projects")
                if slices.isEmpty {
                    Text("-").foregroundStyle(Theme.muted)
                } else {
                    VStack(spacing: 6) {
                        ForEach(Array(slices.enumerated()), id: \.offset) { _, slice in
                            NoteCard(date: ownerName(slice.owner) + (slice.seconds > 0 ? " · \(Format.duration(slice.seconds))" : ""), text: sliceLine(slice), scheduled: false)
                        }
                    }
                }
                if !detail.notes.isEmpty {
                    SectionHeader("Notes")
                    VStack(spacing: 6) {
                        ForEach(detail.notes) { note in
                            EditableNoteCard(date: "✎ \(model.displayName(note.projectId))", text: note.text,
                                             onSave: { try model.updateNote(id: note.id, text: $0) }, onDelete: { model.deleteNote(id: note.id) })
                        }
                    }
                }
                SectionHeader("Note for This Day")
                Picker("Project", selection: $noteProject) {
                    Text("Select a project").tag(String?.none)
                    ForEach(projectChoices, id: \.id) { row in Text(row.displayName).tag(Optional(row.id)) }
                }
                .labelsHidden()
                .padding(.bottom, 6)
                NoteInput(text: $noteText, placeholder: "Note for this day and a project, save with ⌘↩", submit: addNote)
                if let noteError { Text(noteError).font(Theme.small).foregroundStyle(Theme.warn).padding(.top, 4) }
                HStack {
                    Button("Add Note", action: addNote).buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: .command)
                    Button("◷ Schedule for This Day…") {
                        onSchedule(ScheduleDraft(id: nil, projectId: noteProject, title: "", start: tenOClock, duration: 3600, addToCalendar: true))
                    }
                }
                .controlSize(.small)
                .padding(.top, 8)
            }
            .padding(Theme.inspectorPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: "\(day)-\(model.revision)") { detail = await model.dayDetail(day) }
        .onChange(of: day, initial: true) { _, newDay in
            noteProject = model.notePrefillProject(day: newDay)
            noteError = nil
        }
    }

    private var projectChoices: [ProjectRow] {
        model.rows.filter { $0.state == .active }.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    private var tenOClock: Date {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return model.currentDate }
        return model.calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 10)) ?? model.currentDate
    }

    private func ownerName(_ owner: ActivityOwner) -> String {
        switch owner {
        case .project(let id): model.displayName(id)
        case .other(let label): label == "?" ? "Other: unknown folder" : "Other: \(label)"
        }
    }

    private func sliceLine(_ slice: DaySlice) -> String {
        var parts: [String] = []
        if let claude = slice.sessions[.claude] { parts.append("claude: \(claude) \(claude == 1 ? "session" : "sessions")") }
        if let codex = slice.sessions[.codex] { parts.append("codex: \(codex) \(codex == 1 ? "session" : "sessions")") }
        if slice.commits > 0 { parts.append("\(slice.commits) \(slice.commits == 1 ? "commit" : "commits")") }
        return parts.isEmpty ? "-" : parts.joined(separator: " · ")
    }

    private func addNote() {
        do {
            try model.addNote(text: noteText, projectId: noteProject, context: .dayDetail)
            noteText = ""
            noteError = nil
        } catch ModelError.projectRequired {
            noteError = "Select a project for the note."
        } catch ModelError.emptyText {
            noteError = nil
        } catch {
            noteError = "Could not save the note: \(error)"
        }
    }
}
