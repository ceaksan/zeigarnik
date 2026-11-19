import SwiftUI
import ZeigarnikKit

public struct DesignGallery: View {
    public init() {}

    public var body: some View {
        ScrollView([.horizontal, .vertical]) {
            HStack(alignment: .top, spacing: 16) {
                GalleryContent()
                    .padding(Theme.inspectorPadding)
                    .frame(width: 440)
                    .background(Theme.window)
                    .environment(\.colorScheme, .light)
                GalleryContent()
                    .padding(Theme.inspectorPadding)
                    .frame(width: 440)
                    .background(Theme.window)
                    .environment(\.colorScheme, .dark)
            }
            .padding(16)
        }
        .background(Theme.bg)
        .frame(minWidth: 700, minHeight: 600)
    }
}

private struct GalleryContent: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(colorScheme == .dark ? "Dark appearance" : "Light appearance")
                .font(Theme.title)
            HStack(spacing: 8) {
                Text("orbit").font(Theme.title)
                LiveDot()
            }
            .padding(.top, 12)

            SectionHeader("Tags")
            HStack(spacing: 6) {
                Tag("3")
                Tag("137", tone: .warn)
                Tag("no upstream", tone: .warn)
                Tag("up to date", tone: .ok)
            }

            SectionHeader("Calendar")
            calendarSamples

            SectionHeader("Spec progress")
            HStack(spacing: 12) {
                SpecBar(done: 9, total: 11)
                Text("9/11")
                SpecBar(done: 12, total: 12)
                Text("12/12")
                SpecBar(done: 0, total: 0)
                Text("no evidence")
            }
            .font(Theme.chip)

            SectionHeader("Project Details")
            KeyValueGrid([
                ("Last Activity", "today (claude)"),
                ("Last Commit", "18.11"),
                ("Branch", "main"),
                ("Dirty", "3 files"),
                ("Push", "no upstream"),
                ("README", "up to date"),
                ("Spec / Plan", "9/11 tasks"),
                ("≈ Total Time", "≈48 h · last 4 weeks avg. ≈8 h/week"),
            ])

            SectionHeader("Notes")
            VStack(spacing: 6) {
                NoteCard(date: "20.11 10:00", text: "Review the import flow with fresh sample data.", scheduled: true, badge: "In Calendar")
                NoteCard(date: "18.11", text: "Shopping list totals look right; units still to check.", scheduled: false)
            }

            SectionHeader("Last 14 Days")
            Sparkline(values: [2, 0, 3, 5, 1, 0, 4, 6, 2, 3, 0, 1, 5, 7])

            SectionHeader("Status")
            Banner("Codex sessions not found: ~/.codex/sessions", tone: .warn)
        }
        .font(Theme.body)
        .foregroundStyle(Theme.text)
    }

    private var calendarSamples: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                ProjectChip("orbit ≈4 h", colorIndex: stableColorIndex(for: "orbit"))
                ProjectChip("lumen ≈1 h", colorIndex: stableColorIndex(for: "lumen"))
            }
            ForEach(0..<6, id: \.self) { index in
                HStack(spacing: 6) {
                    ProjectChip("orbit ≈4 h", colorIndex: index)
                    ProjectChip("lumen ≈1 h", colorIndex: index)
                }
            }
            ScheduledChip("10:00 orbit")
            NoteMarker("orbit: import flow reviewed")
        }
    }
}
