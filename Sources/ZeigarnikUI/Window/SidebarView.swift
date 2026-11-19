import SwiftUI
import ZeigarnikKit

struct SidebarView: View {
    @Bindable var model: AppModel

    var body: some View {
        let counts = model.counts
        List(selection: $model.sidebar) {
            Section("Views") {
                row("★ Pinned", .pinned, counts)
                row("All", .all, counts)
                if counts[.openNow] == nil {
                    Text("Open Now").badge(Text("?")).help("Could not read herdr terminals").tag(SidebarSelection.filter(.openNow))
                } else {
                    row("Open Now", .openNow, counts)
                }
            }
            Section("Attention") {
                row("Uncommitted", .uncommitted, counts)
                row("Push / Upstream", .pushOrUpstream, counts)
                if model.settings.checkReadme { row("README Behind", .readmeDrift, counts) }
                if model.settings.checkArchitecture, model.rows.contains(where: { if case .none? = $0.architecture { return false }; return $0.architecture != nil }) {
                    row("Architecture Behind", .architectureDrift, counts, help: "Projects whose architecture document predates new folders, many new files or a manifest change")
                }
                if model.settings.checkVisibility, (counts[.publicRepo] ?? 0) > 0 {
                    row("Public", .publicRepo, counts, help: "Repositories that are public on GitHub or GitLab")
                }
                row("Quiet 30+ Days", .quiet, counts)
            }
            Section("Folders") {
                ForEach(folders(counts), id: \.self) { name in
                    row(name, .folder(name), counts)
                }
                Text("Other").tag(SidebarSelection.other)
                row("Missing", .missing, counts)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 200)
    }

    /// `.tag` stays the outermost modifier: List selection ignores a row whose tag sits under `.badge` or `.help`.
    private func row(_ title: String, _ filter: ProjectFilter, _ counts: [ProjectFilter: Int], help: String = "") -> some View {
        Text(title).badge(counts[filter] ?? 0).help(help).tag(SidebarSelection.filter(filter))
    }

    private func folders(_ counts: [ProjectFilter: Int]) -> [String] {
        let names = counts.keys.compactMap { filter -> String? in
            if case .folder(let name) = filter { return name }
            return nil
        }
        func rank(_ name: String) -> Int { name == FolderLabel.root ? 1 : name == FolderLabel.outside ? 2 : 0 }
        return names.sorted { rank($0) != rank($1) ? rank($0) < rank($1) : $0 < $1 }
    }
}
