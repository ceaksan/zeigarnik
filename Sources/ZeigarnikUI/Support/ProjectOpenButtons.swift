import AppKit
import SwiftUI
import ZeigarnikKit

/// Finder, copy path and open-in actions for one project. `compact` is the inspector row (copy sits beside the path there); otherwise menu items.
struct ProjectOpenButtons: View {
    let environment: AppEnvironment
    let path: String
    var compact = false

    var body: some View {
        Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) } label: {
            label("Show in Finder", short: "Finder", icon: "folder")
        }
        if !compact {
            Button { environment.copyPath(path) } label: { label("Copy Path", short: "Copy Path", icon: "doc.on.doc") }
        }
        if let terminal = environment.terminal {
            Button { environment.open(path, with: terminal) } label: { label("Open in \(terminal.name)", short: terminal.name, icon: "terminal") }
                .help("Open in \(terminal.name)")
        }
        if environment.herdrAvailable {
            Button { environment.openInHerdr(path) } label: { label("Open in herdr", short: "herdr", icon: "rectangle.split.3x1") }
                .help("Open a shell in a new herdr terminal here")
        }
        if let editor = environment.editor {
            Button { environment.open(path, with: editor) } label: { label("Open in \(editor.name)", short: editor.name, icon: "chevron.left.forwardslash.chevron.right") }
                .help("Open in \(editor.name)")
        }
    }

    @ViewBuilder private func label(_ full: String, short: String, icon: String) -> some View {
        if compact { Label(short, systemImage: icon).lineLimit(1).fixedSize() } else { Text(full) }
    }
}
