import Foundation

/// An app that opens a project folder: a terminal or an editor.
public struct OpenTarget: Sendable, Equatable, Hashable, Identifiable {
    public enum Kind: Sendable { case terminal, editor }

    public let kind: Kind
    public let name: String
    public let bundleId: String
    public var id: String { bundleId }

    /// Apps known to open a folder handed to them by Launch Services; order is the default preference.
    public static let catalog: [OpenTarget] = [
        OpenTarget(kind: .terminal, name: "Ghostty", bundleId: "com.mitchellh.ghostty"),
        OpenTarget(kind: .terminal, name: "iTerm", bundleId: "com.googlecode.iterm2"),
        OpenTarget(kind: .terminal, name: "Warp", bundleId: "dev.warp.Warp-Stable"),
        OpenTarget(kind: .terminal, name: "Terminal", bundleId: "com.apple.Terminal"),
        OpenTarget(kind: .editor, name: "Visual Studio Code", bundleId: "com.microsoft.VSCode"),
        OpenTarget(kind: .editor, name: "Cursor", bundleId: "com.todesktop.230313mzl4w4u92"),
        OpenTarget(kind: .editor, name: "Zed", bundleId: "dev.zed.Zed"),
        OpenTarget(kind: .editor, name: "Windsurf", bundleId: "com.exafunction.windsurf"),
        OpenTarget(kind: .editor, name: "Sublime Text", bundleId: "com.sublimetext.4"),
        OpenTarget(kind: .editor, name: "Xcode", bundleId: "com.apple.dt.Xcode"),
    ]

    public static func available(_ kind: Kind, isInstalled: (String) -> Bool) -> [OpenTarget] {
        catalog.filter { $0.kind == kind && isInstalled($0.bundleId) }
    }

    /// The chosen app when it is installed, otherwise the first installed one, otherwise nil.
    public static func resolve(_ kind: Kind, chosen: String?, isInstalled: (String) -> Bool) -> OpenTarget? {
        let options = available(kind, isInstalled: isInstalled)
        return options.first { $0.bundleId == chosen } ?? options.first
    }
}
