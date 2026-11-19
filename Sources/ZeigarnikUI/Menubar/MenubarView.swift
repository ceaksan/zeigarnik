import SwiftUI
import ZeigarnikKit

struct MenubarView: View {
    let environment: AppEnvironment
    let openMain: () -> Void

    var body: some View {
        let model = environment.model
        let summary = environment.menubarSummary
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("Today and Upcoming").padding(.top, -6)
            if summary.upcoming.isEmpty {
                Text("Nothing scheduled").foregroundStyle(Theme.muted).padding(.horizontal, 6).padding(.vertical, 4)
            }
            ForEach(summary.upcoming) { item in
                MenuRow {
                    model.goTo(day: dayKey(item.start, calendar: model.calendar))
                    openMain()
                } label: {
                    Text("◷ \(UIFormat.dayMonthTime(item.start, model.calendar)) · \(model.displayName(item.projectId))")
                    Spacer(minLength: 8)
                    Text(item.title).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
            if !summary.pinned.isEmpty {
                SectionHeader("Pinned")
                ForEach(summary.pinned) { row in
                    MenuRow {
                        model.sidebar = .filter(.pinned)
                        model.view = .list
                        model.selectedProjectId = row.id
                        openMain()
                    } label: {
                        Text("★").foregroundStyle(Theme.star)
                        Text(row.displayName)
                        if UIFormat.isOpen(row.id, environment.coordinator.openNow) { LiveDot() }
                        Spacer(minLength: 8)
                        Text("\(Format.dirty(row.status)) dirty · \(Format.duration(row.totalSeconds))").foregroundStyle(Theme.muted)
                    }
                }
            }
            let readmeDrift = environment.model.settings.checkReadme ? summary.readmeDriftCount : 0
            if summary.uncommittedCount > 0 || readmeDrift > 0 {
                SectionHeader("Attention")
                if summary.uncommittedCount > 0 {
                    attention("Uncommitted changes in \(summary.uncommittedCount) \(summary.uncommittedCount == 1 ? "project" : "projects")", .uncommitted)
                }
                if readmeDrift > 0 {
                    attention("README may be behind in \(summary.readmeDriftCount) \(summary.readmeDriftCount == 1 ? "project" : "projects")", .readmeDrift)
                }
            }
            Divider().padding(.vertical, 8)
            MenuRow(action: openMain) {
                Text("Open Window")
                Spacer()
                Text("⌘O").foregroundStyle(Theme.muted)
            }
            .keyboardShortcut("o")
            MenuRow { environment.coordinator.requestScan(fetch: true) } label: {
                Text(environment.coordinator.isScanning ? "Scanning…" : "Scan Now")
                Spacer()
                Text(scanDetail).foregroundStyle(Theme.muted)
            }
            .keyboardShortcut("r")
            MenuRow { NSApp.terminate(nil) } label: {
                Text("Quit")
                Spacer()
                Text("⌘Q").foregroundStyle(Theme.muted)
            }
            .keyboardShortcut("q")
        }
        .font(Theme.body)
        .padding(10)
        .frame(width: 340)
        .task { environment.refreshUpcoming() }
    }

    private var scanDetail: String {
        guard let report = environment.coordinator.lastReport else { return "⌘R" }
        return "⌘R · last scan \(UIFormat.time(report.finishedAt, environment.model.calendar))"
    }

    private func attention(_ text: String, _ filter: ProjectFilter) -> some View {
        MenuRow {
            environment.model.sidebar = .filter(filter)
            environment.model.view = .list
            openMain()
        } label: {
            Text(text)
            Spacer()
            Text("›").foregroundStyle(Theme.muted)
        }
    }
}

private struct MenuRow<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) { label() }
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(hovering ? Theme.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
