import AppKit

/// `.searchable` in the toolbar does not take ⌘F on macOS 14 (`searchFocused` needs macOS 15), so the Find command focuses the field itself.
@MainActor enum SearchFieldFocus {
    static func focus() {
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) ?? NSApp.mainWindow else { return }
        window.makeKeyAndOrderFront(nil)
        if let item = window.toolbar?.items.lazy.compactMap({ $0 as? NSSearchToolbarItem }).first {
            item.beginSearchInteraction()
        } else if let field = searchField(in: window.contentView?.superview) {
            window.makeFirstResponder(field)
        }
    }

    private static func searchField(in view: NSView?) -> NSSearchField? {
        guard let view else { return nil }
        if let field = view as? NSSearchField { return field }
        for subview in view.subviews {
            if let field = searchField(in: subview) { return field }
        }
        return nil
    }
}
