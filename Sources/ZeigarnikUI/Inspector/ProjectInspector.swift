import AppKit
import SwiftUI
import ZeigarnikKit

struct ProjectInspector: View {
    let environment: AppEnvironment
    let model: AppModel
    let row: ProjectRow
    var onSchedule: (ScheduleDraft) -> Void = { _ in }
    @State private var pathCopied = false
    @State private var detail = ProjectDetail()
    @State private var noteText = ""
    @State private var noteError: String?
    @State private var showCompletedSpecs = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if let error = row.error {
                    SectionHeader("Scan Error")
                    Text(Format.scanError(error))
                        .font(Theme.small)
                        .foregroundStyle(Theme.warn)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .padding(.bottom, 12)
                }
                if row.state == .missing {
                    Banner("This project is not in your folders right now, or its folder cannot be found. Notes and schedules are preserved.", tone: .warn)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
                        .padding(.bottom, 10)
                }
                if let summary = row.summary {
                    Text(summary).font(Theme.body).padding(.bottom, 12).fixedSize(horizontal: false, vertical: true)
                }
                KeyValueGrid(facts)
                SectionHeader("Last 14 Days")
                Sparkline(values: series)
                specSection
                notesSection
            }
            .padding(Theme.inspectorPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: "\(row.id)-\(model.revision)") { detail = await model.projectDetail(row.id) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                if row.pinned { Text("★").foregroundStyle(Theme.star) }
                Text(row.displayName).font(Theme.title).lineLimit(2)
                if UIFormat.isOpen(row.id, model.coordinator?.openNow) { LiveDot() }
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Button {
                    environment.copyPath(row.path)
                    pathCopied = true
                    Task { try? await Task.sleep(for: .seconds(1.5)); pathCopied = false }
                } label: {
                    Image(systemName: pathCopied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy Path")
                .accessibilityLabel("Copy Path")
                Text(row.path).textSelection(.enabled)
            }
            .font(Theme.small)
            .foregroundStyle(Theme.muted)
            HStack {
                ProjectOpenButtons(environment: environment, path: row.path, compact: true)
            }
            .controlSize(.small)
            .labelStyle(.titleAndIcon)
            .padding(.top, 6)
            if let error = environment.openError { Text(error).font(Theme.small).foregroundStyle(Theme.warn) }
            Spacer().frame(height: 10)
        }
    }

    private var facts: [(String, String)] {
        let cal = model.calendar
        let now = model.currentDate
        var rows: [(String, String)] = [
            ("Last Activity", Format.relativeDay(row.lastActivityAt, now: now, calendar: cal) + (row.lastActivityAgent.map { " (\(UIFormat.agentName($0)))" } ?? "")),
            ("Last Commit", Format.relativeDay(row.lastCommitAt, now: now, calendar: cal)),
            ("Branch", row.status?.branch ?? (row.status == nil ? "?" : "detached")),
            ("Dirty", row.status.map { "\($0.changed + $0.untracked) \($0.changed + $0.untracked == 1 ? "file" : "files") (\($0.changed) modified, \($0.untracked) untracked)" } ?? "?"),
            ("Push", Format.push(row.status)),
            ("Last Fetch", row.lastFetchAt.map { UIFormat.dayMonthTime($0, cal) } ?? "never"),
            ("README", Format.readme(row.readme)),
            ("Architecture", Format.architecture(row.architecture, calendar: cal)),
            ("Visibility", Format.visibility(row.visibility)),
            ("Source", row.isTableProject ? "Project table" : "Found in a scan folder"),
        ].filter { key, _ in
            (key != "README" || model.settings.checkReadme) && (key != "Architecture" || model.settings.checkArchitecture)
                && (key != "Visibility" || model.settings.checkVisibility)
        }
        if let current = row.spec?.current {
            rows.append(("Spec", Format.specLine(current)))
        } else {
            rows.append(("Spec", Format.specShort(row.spec)))
        }
        rows.append(("Active Tasks", row.activeTasksOpen.map { "\($0) open" } ?? "-"))
        rows.append(("≈ Total Time", "\(Format.duration(row.totalSeconds)) · last 4 weeks avg. \(Format.duration(weeklyAverage))/week"))
        return rows
    }

    private var series: [Double] {
        model.activity.projectSeries(row.id, days: UIFormat.lastDays(14, endingAt: model.currentDate, model.calendar))
    }

    private var weeklyAverage: TimeInterval {
        let days = UIFormat.lastDays(28, endingAt: model.currentDate, model.calendar)
        return model.activity.projectSeconds(row.id, fromDay: days.first ?? "", toDay: days.last ?? "") / 4
    }

    @ViewBuilder private var specSection: some View {
        if !detail.specs.isEmpty {
            SectionHeader("Spec")
            Toggle("Show Completed", isOn: $showCompletedSpecs)
                .toggleStyle(.checkbox)
                .font(Theme.small)
                .padding(.bottom, 8)
            if detail.visibleSpecs(showCompleted: showCompletedSpecs).isEmpty {
                Text("No open specs.").font(Theme.small).foregroundStyle(Theme.muted)
            }
            ForEach(detail.visibleSpecs(showCompleted: showCompletedSpecs), id: \.specPath) { spec in
                VStack(alignment: .leading, spacing: 4) {
                    Text(spec.title).fontWeight(.semibold)
                    Text(Format.specLine(spec)).font(Theme.small).foregroundStyle(Theme.muted)
                    ForEach(spec.evidence?.tasks ?? [], id: \.number) { task in
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(task.resolvedPaths, id: \.self) { Text($0).font(Theme.small).textSelection(.enabled) }
                                ForEach(task.matchedCommits, id: \.self) { Text($0).font(Theme.small).foregroundStyle(Theme.muted) }
                                if task.resolvedPaths.isEmpty && task.matchedCommits.isEmpty {
                                    Text("No paths or commits").font(Theme.small).foregroundStyle(Theme.muted)
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                evidenceMark(task.evidence)
                                Text("\(task.number). \(task.title)").font(Theme.small).lineLimit(2)
                            }
                        }
                    }
                    HStack {
                        Button("Mark Done") { model.setSpecOverride(projectId: row.id, specPath: spec.specPath, .done, note: nil) }
                        Button("Mark Not Done") { model.setSpecOverride(projectId: row.id, specPath: spec.specPath, .notDone, note: nil) }
                        Button("Reset") { model.setSpecOverride(projectId: row.id, specPath: spec.specPath, nil, note: nil) }
                    }
                    .controlSize(.small)
                }
                .padding(.bottom, 8)
            }
        }
    }

    @ViewBuilder private func evidenceMark(_ evidence: TaskEvidence) -> some View {
        switch evidence {
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.ok)
        case .pending: Image(systemName: "circle").foregroundStyle(Theme.muted)
        case .external: Tag("external", tone: .warn)
        case .noEvidence: Tag("no evidence")
        }
    }

    @ViewBuilder private var notesSection: some View {
        SectionHeader("Notes and Schedules")
        VStack(spacing: 6) {
            ForEach(detail.drafts, id: \.kind) { draft in
                DraftNoteCard(kind: draft.kind, text: draft.text, onAccept: { try model.acceptDraft(draft, text: $0) }, onDismiss: { model.dismissDraft(draft) })
                    .id("\(draft.kind.rawValue)-\(draft.text)")
            }
            ForEach(detail.items) { item in
                ScheduledItemCard(date: UIFormat.dayMonthTime(item.start, model.calendar), item: item,
                                  onEdit: { onSchedule(ScheduleDraft(id: item.id, projectId: item.projectId, title: item.title, start: item.start, duration: item.duration, addToCalendar: item.wantsCalendar)) },
                                  onDelete: { model.deleteSchedule(id: item.id) })
            }
            ForEach(detail.notes) { note in
                EditableNoteCard(date: UIFormat.dayMonth(note.day, model.calendar), text: note.text,
                                 onSave: { try model.updateNote(id: note.id, text: $0) }, onDelete: { model.deleteNote(id: note.id) })
            }
            if detail.items.isEmpty && detail.notes.isEmpty && detail.drafts.isEmpty {
                Text("No notes yet.").foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        NoteInput(text: $noteText, placeholder: "Write a note, save with ⌘↩", submit: addNote)
            .padding(.top, 8)
        if let noteError { Text(noteError).font(Theme.small).foregroundStyle(Theme.warn) }
        HStack {
            Button("Add Note", action: addNote).buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: .command)
            Button(row.pinned ? "Unpin" : "★ Pin") { model.togglePin(row.id) }
            Button("◷ Schedule…") {
                onSchedule(ScheduleDraft(id: nil, projectId: row.id, title: "\(row.displayName): ", start: nextHour, duration: 3600, addToCalendar: true))
            }
        }
        .controlSize(.small)
        .padding(.top, 8)
    }

    private var nextHour: Date {
        let cal = model.calendar
        let now = model.currentDate
        return cal.nextDate(after: now, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? now
    }

    private func addNote() {
        do {
            try model.addNote(text: noteText, projectId: row.id, context: .projectDetail)
            noteText = ""
            noteError = nil
        } catch ModelError.emptyText {
            noteError = nil
        } catch {
            noteError = "Could not save the note: \(error)"
        }
    }
}

struct NoteInput: View {
    @Binding var text: String
    let placeholder: String
    let submit: () -> Void

    var body: some View {
        TextEditor(text: $text)
            .font(Theme.body)
            .scrollContentBackground(.hidden)
            .padding(4)
            .frame(minHeight: 58)
            .background(Theme.window, in: RoundedRectangle(cornerRadius: Theme.corner))
            .overlay(RoundedRectangle(cornerRadius: Theme.corner).strokeBorder(Theme.line))
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder).foregroundStyle(Theme.muted).padding(.horizontal, 9).padding(.vertical, 4).allowsHitTesting(false)
                }
            }
    }
}
