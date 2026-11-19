import SwiftUI
import ZeigarnikKit

public struct ZeigarnikScenes: Scene {
    @Environment(\.openWindow) private var openWindow
    @State private var environment = AppEnvironment()

    public init() {}

    public var body: some Scene {
        Window("Zeigarnik", id: "main") {
            RootView(environment: environment)
                .modifier(WelcomeLauncher(environment: environment))
                #if DEBUG
                .modifier(DebugWindows())
                #endif
        }
        .defaultSize(width: 1320, height: 820)
        .commands {
            WelcomeCommand()
            CommandGroup(replacing: .textEditing) {
                Button("Find Projects") { SearchFieldFocus.focus() }.keyboardShortcut("f")
            }
        }
        Window("Welcome to Zeigarnik", id: "welcome") {
            WelcomeView(environment: environment) {
                NSApp.windows.first { $0.identifier?.rawValue == "welcome" }?.close()
                openWindow(id: "main")
            }
        }
        .windowResizability(.contentSize)
        Settings {
            SettingsView(settings: Binding(get: { environment.model.settings }, set: { environment.apply($0) }),
                         calendarAccess: environment.calendarAccess,
                         calendars: environment.calendars,
                         requestCalendarAccess: { await environment.requestCalendarAccess() },
                         launchAtLoginError: environment.launchAtLoginError,
                         terminals: environment.terminals,
                         editors: environment.editors)
                .onAppear { environment.refreshSystemState() }
        }
        MenuBarExtra {
            MenubarView(environment: environment) {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
        } label: {
            let count = environment.menubarSummary.todayCount
            Image(systemName: "list.bullet.rectangle")
            if count > 0 { Text("\(count)") }
        }
        .menuBarExtraStyle(.window)
        #if DEBUG
        Window("Design Gallery", id: "gallery") {
            DesignGallery()
        }
        Window("Menu Bar Preview", id: "menubar-preview") {
            MenubarView(environment: environment) {}
        }
        #endif
    }
}

#if DEBUG
/// Audit-only launch arguments: `--gallery`, `--menubar-preview`, `--settings`.
private struct DebugWindows: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    func body(content: Content) -> some View {
        content.onAppear {
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--gallery") { openWindow(id: "gallery") }
            if arguments.contains("--menubar-preview") { openWindow(id: "menubar-preview") }
            if arguments.contains("--settings") { openSettings() }
        }
    }
}
#endif

/// Opens the welcome window on launch until it has been completed once.
private struct WelcomeLauncher: ViewModifier {
    let environment: AppEnvironment
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onAppear { if !environment.model.settings.welcomeShown { openWindow(id: "welcome") } }
    }
}

private struct WelcomeCommand: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Welcome to Zeigarnik") { openWindow(id: "welcome") }
        }
    }
}
