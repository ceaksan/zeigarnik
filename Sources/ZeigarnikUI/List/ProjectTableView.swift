import SwiftUI
import ZeigarnikKit

struct RowSort: SortComparator, Hashable {
    let key: ProjectSortKey
    var order: SortOrder = .forward

    func compare(_ lhs: ProjectRow, _ rhs: ProjectRow) -> ComparisonResult { .orderedSame }
}

struct ProjectTableView: View {
    let environment: AppEnvironment
    @Bindable var model: AppModel
    @State private var sortOrder = [RowSort(key: .lastActivity, order: .reverse)]
    @State private var columns = TableColumnCustomization<ProjectRow>()
    /// Hidden, reordered and resized columns, kept across launches. Right-click a column header to choose columns.
    @AppStorage("projectTableColumns") private var savedColumns = Data()

    var body: some View {
        let rows = model.visibleRows
        let openNow = model.coordinator?.openNow
        Table(rows, selection: $model.selectedProjectId, sortOrder: $sortOrder, columnCustomization: $columns) {
            TableColumn("", sortUsing: RowSort(key: .name)) { row in
                if row.pinned { Text("★").foregroundStyle(Theme.star) }
            }
            .width(18)
            .customizationID("pin")
            TableColumn("Project", sortUsing: RowSort(key: .name)) { row in
                HStack(spacing: 6) {
                    Text(row.displayName).fontWeight(.semibold).lineLimit(1)
                    if UIFormat.isOpen(row.id, openNow) { LiveDot() }
                    if let error = row.error {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warn).help(error)
                    }
                }
                .help(row.summary ?? row.path)
            }
            .width(min: 130, ideal: 160)
            .customizationID("project")
            .disabledCustomizationBehavior(.visibility)
            TableColumn("Last Activity", sortUsing: RowSort(key: .lastActivity)) { row in
                HStack(spacing: 4) {
                    Text(Format.relativeDay(row.lastActivityAt, now: model.currentDate, calendar: model.calendar))
                    Text(UIFormat.agentName(row.lastActivityAgent)).foregroundStyle(Theme.muted)
                }
            }
            .width(min: 96, ideal: 100)
            .customizationID("lastActivity")
            TableColumn("Last Commit", sortUsing: RowSort(key: .lastCommit)) { row in
                Text(Format.relativeDay(row.lastCommitAt, now: model.currentDate, calendar: model.calendar)).foregroundStyle(Theme.muted)
            }
            .width(min: 86, ideal: 86)
            .customizationID("lastCommit")
            TableColumn("Dirty", sortUsing: RowSort(key: .dirty)) { row in
                dirtyCell(row.status)
            }
            .width(min: 44, ideal: 50)
            .customizationID("dirty")
            TableColumn("Push", sortUsing: RowSort(key: .push)) { row in
                if Format.pushNeedsAttention(row.status) { Tag(Format.push(row.status), tone: .warn) } else { Text(Format.push(row.status)).foregroundStyle(Theme.muted) }
            }
            .width(min: 96, ideal: 96)
            .customizationID("push")
            TableColumn("README", sortUsing: RowSort(key: .readme)) { row in
                Group {
                    if case .behind = row.readme { Tag(Format.readmeShort(row.readme), tone: .warn) } else { Text(Format.readmeShort(row.readme)).foregroundStyle(Theme.muted) }
                }
                .help(Format.readme(row.readme))
            }
            .width(min: 88, ideal: 88)
            .customizationID("readme")
            TableColumn("Visibility", sortUsing: RowSort(key: .visibility)) { row in
                visibilityCell(row.visibility)
            }
            .width(min: 64, ideal: 70)
            .customizationID("visibility")
            TableColumn("≈ Total Time", sortUsing: RowSort(key: .time)) { row in
                Text(row.totalSeconds > 0 ? Format.duration(row.totalSeconds) : "-").monospacedDigit()
            }
            .width(min: 64, ideal: 72)
            .customizationID("time")
            TableColumn("Spec / Plan", sortUsing: RowSort(key: .spec)) { row in
                specCell(row.spec)
            }
            .width(min: 100, ideal: 120)
            .customizationID("spec")
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if ids.count == 1, let id = ids.first, let row = model.row(id) {
                ProjectOpenButtons(environment: environment, path: row.path)
            }
        }
        .onChange(of: sortOrder) { _, newValue in
            guard let first = newValue.first else { return }
            model.sortKey = first.key
            model.sortAscending = first.order == .forward
        }
        .onAppear {
            sortOrder = [RowSort(key: model.sortKey, order: model.sortAscending ? .forward : .reverse)]
            if let saved = try? JSONDecoder().decode(TableColumnCustomization<ProjectRow>.self, from: savedColumns) { columns = saved }
            if !model.settings.checkReadme { columns[visibility: "readme"] = .hidden }
            if !model.settings.checkVisibility { columns[visibility: "visibility"] = .hidden }
        }
        .onChange(of: columns) { _, value in savedColumns = (try? JSONEncoder().encode(value)) ?? Data() }
        .onChange(of: model.settings.checkReadme) { _, on in columns[visibility: "readme"] = on ? .visible : .hidden }
        .onChange(of: model.settings.checkVisibility) { _, on in columns[visibility: "visibility"] = on ? .visible : .hidden }
        .overlay {
            if rows.isEmpty {
                if model.rows.isEmpty, model.coordinator?.isScanning == true {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("First scan in progress: reading repositories, git status and agent history.").foregroundStyle(Theme.muted)
                    }
                } else if model.isLoaded {
                    Text("No projects in this view").foregroundStyle(Theme.muted)
                }
            }
        }
    }

    @ViewBuilder private func dirtyCell(_ status: GitStatus?) -> some View {
        let count = status.map { $0.changed + $0.untracked }
        if let count, count > 0 {
            Tag("\(count)", tone: count > 50 ? .warn : .neutral)
        } else {
            Text(Format.dirty(status)).foregroundStyle(Theme.muted)
        }
    }

    @ViewBuilder private func visibilityCell(_ value: RepoVisibility?) -> some View {
        switch value {
        case .public?: Text(Format.visibility(value)).foregroundStyle(Theme.ok)
        default: Text(Format.visibility(value)).foregroundStyle(Theme.muted)
        }
    }

    @ViewBuilder private func specCell(_ headline: SpecHeadline?) -> some View {
        HStack(spacing: 6) {
            if case .inProgress(let done, let total, _)? = headline?.current?.stage, total > 0 {
                SpecBar(done: done, total: total)
            }
            Text(Format.specShort(headline)).foregroundStyle(headline == nil ? Theme.muted : Theme.text).lineLimit(1)
        }
    }
}
