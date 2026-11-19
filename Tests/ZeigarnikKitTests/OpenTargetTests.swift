import Foundation
import Testing
@testable import ZeigarnikKit

@Suite struct OpenTargetTests {
    @Test func settingsSavedBeforeOpenActionsStillDecode() throws {
        let old = #"{"roots":["/r"],"vaultRoot":"/v","calendarId":"C","launchAtLogin":true}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(old.utf8))
        #expect(settings.roots == ["/r"])
        #expect(settings.calendarId == "C")
        #expect(settings.launchAtLogin)
        #expect(settings.terminalApp == nil)
        #expect(settings.editorApp == nil)
        #expect(settings.appearance == .system)
        #expect(settings.welcomeShown == false)
        #expect(settings.checkReadme)
        #expect(settings.checkArchitecture)
    }

    @Test func newFieldsRoundTrip() throws {
        let settings = AppSettings(roots: [], vaultRoot: nil, calendarId: nil, launchAtLogin: false,
                                   terminalApp: "com.mitchellh.ghostty", editorApp: "dev.zed.Zed", appearance: .dark,
                                   welcomeShown: true, checkReadme: false, checkArchitecture: true)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
    }

    @Test func onlyInstalledTargetsAreOfferedInCatalogOrder() {
        let installed: Set = ["com.apple.Terminal", "com.mitchellh.ghostty", "dev.zed.Zed", "com.apple.dt.Xcode"]
        #expect(OpenTarget.available(.terminal) { installed.contains($0) }.map(\.name) == ["Ghostty", "Terminal"])
        #expect(OpenTarget.available(.editor) { installed.contains($0) }.map(\.name) == ["Zed", "Xcode"])
    }

    @Test func chosenTargetWinsWhenInstalledOtherwiseFirstInstalled() {
        let installed: Set = ["com.apple.Terminal", "com.mitchellh.ghostty"]
        let isInstalled = { installed.contains($0) }
        #expect(OpenTarget.resolve(.terminal, chosen: "com.apple.Terminal", isInstalled: isInstalled)?.name == "Terminal")
        #expect(OpenTarget.resolve(.terminal, chosen: "com.googlecode.iterm2", isInstalled: isInstalled)?.name == "Ghostty")
        #expect(OpenTarget.resolve(.terminal, chosen: nil, isInstalled: isInstalled)?.name == "Ghostty")
        #expect(OpenTarget.resolve(.editor, chosen: nil, isInstalled: isInstalled) == nil)
    }
}
