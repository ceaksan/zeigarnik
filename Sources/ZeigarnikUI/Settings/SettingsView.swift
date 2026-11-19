import AppKit
import SwiftUI
import ZeigarnikKit

@MainActor
public struct SettingsView: View {
    @Binding private var settings: AppSettings
    private let calendarAccess: CalendarAccess
    private let calendars: [CalendarInfo]
    private let requestCalendarAccess: () async -> Void
    private let launchAtLoginError: String?
    private let terminals: [OpenTarget]
    private let editors: [OpenTarget]

    public init(
        settings: Binding<AppSettings>,
        calendarAccess: CalendarAccess,
        calendars: [CalendarInfo],
        requestCalendarAccess: @escaping () async -> Void,
        launchAtLoginError: String?,
        terminals: [OpenTarget] = [],
        editors: [OpenTarget] = []
    ) {
        self._settings = settings
        self.calendarAccess = calendarAccess
        self.calendars = calendars
        self.requestCalendarAccess = requestCalendarAccess
        self.launchAtLoginError = launchAtLoginError
        self.terminals = terminals
        self.editors = editors
    }

    public var body: some View {
        Form {
            rootsSection
            vaultSection
            calendarSection
            generalSection
            checksSection
            advancedSection
            aboutSection
        }
        .formStyle(.grouped)
        .font(Theme.body)
        .foregroundStyle(Theme.text)
        .frame(width: 520).frame(minHeight: 760)
    }

    private var rootsSection: some View {
        Section("Folders") {
            if settings.roots.isEmpty {
                Banner("Choose a folder to scan. Zeigarnik only reads git repositories in the folders you select.", tone: .warn)
            }
            ForEach(settings.roots, id: \.self) { path in
                HStack {
                    Text(path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(path)
                    Spacer(minLength: 8)
                    Button {
                        settings.roots.removeAll { $0 == path }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                    .help("Remove folder")
                    .accessibilityLabel("Remove folder: \(path)")
                }
            }
            Button("Add Folder…", action: addRoots)
        }
    }

    private var vaultSection: some View {
        Section("Vault") {
            Text(settings.vaultRoot ?? "None")
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(settings.vaultRoot ?? "None")
            HStack {
                Button("Choose…") {
                    if let path = FolderChooser.choose(multiple: false, prompt: "Choose").first {
                        settings.vaultRoot = path
                    }
                }
                if settings.vaultRoot != nil {
                    Button("Remove") { settings.vaultRoot = nil }
                }
            }
            Text("Obsidian vault folder for Active Tasks counts. Optional.")
                .font(Theme.small)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var calendarSection: some View {
        Section("Calendar") {
            switch calendarAccess {
            case .notDetermined:
                Text("Zeigarnik has not requested calendar access.")
                Button("Request Access") {
                    Task { await requestCalendarAccess() }
                }
            case .denied:
                Banner("Calendar access is disabled. Schedules stay in the app and are not added to your calendar.", tone: .warn)
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                        NSWorkspace.shared.open(url)
                    }
                }
            case .granted:
                Picker("Target Calendar", selection: $settings.calendarId) {
                    Text("None").tag(nil as String?)
                    ForEach(calendars) { calendar in
                        Text("\(calendar.title) (\(calendar.sourceTitle))")
                            .tag(Optional(calendar.id))
                    }
                }
            }
        }
    }

    private var checksSection: some View {
        Section("Checks") {
            Toggle("README drift", isOn: $settings.checkReadme)
            Toggle("Architecture drift", isOn: $settings.checkArchitecture)
            Toggle("Repository visibility", isOn: $settings.checkVisibility)
            Text("Asks GitHub or GitLab whether each repository is public: once a day after a clear answer, each scan while the answer is unknown. Uses the gh command when it is installed, so private repositories you own are recognised.")
                .font(Theme.small).foregroundStyle(Theme.muted)
            Link("What is a living architecture document?", destination: AboutLinks.livingArchitecture).font(Theme.small)
        }
    }

    private var advancedSection: some View {
        Section("Advanced") {
            Picker("Scan Every", selection: $settings.scanIntervalHours) {
                ForEach(AppSettings.scanIntervalChoices, id: \.self) { Text($0 == 1 ? "1 hour" : "\($0) hours").tag($0) }
            }
            Picker("Activity Gap", selection: $settings.activityGapMinutes) {
                ForEach(AppSettings.activityGapChoices, id: \.self) { Text("\($0) minutes").tag($0) }
            }
            Text("Agent messages closer together than the activity gap count as one stretch of work. A shorter gap gives lower time estimates.")
                .font(Theme.small).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: AboutLinks.version)
            if AboutLinks.labPageLive { Link("Zeigarnik on lab.ceaksan.com", destination: AboutLinks.labPage) }
            Link("Living Architecture", destination: AboutLinks.livingArchitecture)
            HStack(spacing: 14) {
                Link("Website", destination: AboutLinks.website)
                Link("X", destination: AboutLinks.x)
                Link("LinkedIn", destination: AboutLinks.linkedIn)
                Link("Buy Me a Coffee", destination: AboutLinks.buyMeACoffee)
            }
        }
    }

    private var generalSection: some View {
        Section("General") {
            Picker("Appearance", selection: $settings.appearance) {
                Text("System").tag(AppAppearance.system)
                Text("Light").tag(AppAppearance.light)
                Text("Dark").tag(AppAppearance.dark)
            }
            .pickerStyle(.segmented)
            appPicker("Terminal", options: terminals, selection: $settings.terminalApp)
            appPicker("Editor", options: editors, selection: $settings.editorApp)
            Toggle("Launch at Login", isOn: $settings.launchAtLogin)
            if let launchAtLoginError {
                Text(launchAtLoginError)
                    .font(Theme.small)
                    .foregroundStyle(Theme.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Lists installed apps only; with no choice saved, the first installed one is shown and used.
    @ViewBuilder private func appPicker(_ title: String, options: [OpenTarget], selection: Binding<String?>) -> some View {
        if options.isEmpty {
            LabeledContent(title) { Text("None installed").foregroundStyle(Theme.muted) }
        } else {
            Picker(title, selection: Binding(
                get: { options.first { $0.bundleId == selection.wrappedValue }?.bundleId ?? options[0].bundleId },
                set: { selection.wrappedValue = $0 }
            )) {
                ForEach(options) { Text($0.name).tag($0.bundleId) }
            }
        }
    }

    private func addRoots() {
        let paths = FolderChooser.choose(multiple: true, prompt: "Add")
        var roots = settings.roots
        var existing = Set(roots)
        for path in paths where existing.insert(path).inserted {
            roots.append(path)
        }
        if roots != settings.roots { settings.roots = roots }
    }
}
