import AppKit

enum FolderChooser {
    /// Standardized paths of the folders picked in an open panel; empty when cancelled.
    @MainActor static func choose(multiple: Bool, prompt: String) -> [String] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = multiple
        panel.prompt = prompt
        guard panel.runModal() == .OK else { return [] }
        return panel.urls.map { $0.standardizedFileURL.path }
    }
}
