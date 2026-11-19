import SwiftUI
import ZeigarnikKit

/// First-run setup: folders, optional vault, which checks to run, calendar. Reopened from the Help menu.
struct WelcomeView: View {
    let environment: AppEnvironment
    var onFinish: () -> Void

    private var settings: AppSettings { environment.model.settings }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Welcome to Zeigarnik").font(.system(size: 22, weight: .semibold))
                        Text("Zeigarnik shows where each of your projects stands: last activity from Claude Code, Codex and commits, uncommitted and unpushed changes, README and architecture drift, and the work you schedule.")
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Everything stays on this Mac. Zeigarnik reads git, agent logs and your notes locally. Its network access is git fetch and, if the visibility check is on, a question per repository to GitHub or GitLab, at most once a day once answered.")
                            .font(Theme.small).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    }
                    step(1, "Folders to scan", note: "Zeigarnik finds the git repositories inside these folders.") {
                        ForEach(settings.roots, id: \.self) { path in
                            HStack {
                                Text(path).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Button { update { $0.roots.removeAll { $0 == path } } } label: { Image(systemName: "minus.circle") }
                                    .buttonStyle(.borderless).help("Remove folder")
                            }
                        }
                        Button("Add Folder…") {
                            let picked = FolderChooser.choose(multiple: true, prompt: "Add")
                            update { settings in settings.roots += picked.filter { !settings.roots.contains($0) } }
                        }
                    }
                    step(2, "Obsidian vault (optional)", note: "Used for Active Tasks counts when a project table in your root folder names a vault folder per project.") {
                        HStack {
                            Text(settings.vaultRoot ?? "None").foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button("Choose…") { if let path = FolderChooser.choose(multiple: false, prompt: "Choose").first { update { $0.vaultRoot = path } } }
                            if settings.vaultRoot != nil { Button("Remove") { update { $0.vaultRoot = nil } } }
                        }
                    }
                    step(3, "Checks", note: "Turned-off checks disappear from the list, the sidebar and the menu bar.") {
                        Toggle("README drift: flag READMEs that fell behind the code", isOn: binding(\.checkReadme))
                        Toggle("Architecture drift: flag architecture documents that predate new folders, files or dependencies", isOn: binding(\.checkArchitecture))
                        Toggle("Repository visibility: ask GitHub or GitLab whether each repository is public", isOn: binding(\.checkVisibility))
                        Link("What is a living architecture document?", destination: AboutLinks.livingArchitecture).font(Theme.small)
                    }
                    step(4, "Calendar (optional)", note: "Schedules can also be added to a macOS calendar.") {
                        switch environment.calendarAccess {
                        case .notDetermined: Button("Request Access") { Task { await environment.requestCalendarAccess() } }
                        case .denied: Text("Calendar access is off. You can allow it later in System Settings.").foregroundStyle(Theme.muted)
                        case .granted: Text("Calendar access is on. Choose the target calendar in Settings.").foregroundStyle(Theme.muted)
                        }
                    }
                }
                .padding(24)
            }
            Divider()
            HStack {
                Text("Version \(AboutLinks.version)").font(Theme.small).foregroundStyle(Theme.muted)
                Spacer()
                Button(settings.roots.isEmpty ? "Skip for Now" : "Start") {
                    update { $0.welcomeShown = true }
                    onFinish()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .font(Theme.body)
        .frame(width: 580, height: 660)
        .onAppear { environment.refreshSystemState() }
    }

    private func update(_ change: (inout AppSettings) -> Void) {
        var next = settings
        change(&next)
        environment.apply(next)
    }

    private func binding(_ key: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(get: { settings[keyPath: key] }, set: { value in update { $0[keyPath: key] = value } })
    }

    @ViewBuilder private func step(_ number: Int, _ title: String, note: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(number). \(title)").font(.system(size: 14, weight: .semibold))
            Text(note).font(Theme.small).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            content()
        }
    }
}
