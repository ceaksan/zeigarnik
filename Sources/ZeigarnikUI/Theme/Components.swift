import SwiftUI
import ZeigarnikKit

public struct Tag: View {
    public enum Tone: Sendable {
        case neutral, warn, ok
    }

    private let text: String
    private let tone: Tone

    public init(_ text: String, tone: Tone = .neutral) {
        self.text = text
        self.tone = tone
    }

    public var body: some View {
        Text(text)
            .font(Theme.chip)
            .foregroundStyle(foreground)
            .padding(.vertical, 1)
            .padding(.horizontal, 6)
            .background(background, in: RoundedRectangle(cornerRadius: Theme.tagCorner))
    }

    private var foreground: Color {
        switch tone {
        case .neutral: Theme.text
        case .warn: Theme.warn
        case .ok: Theme.ok
        }
    }

    private var background: Color {
        switch tone {
        case .neutral: Theme.line
        case .warn: Theme.warnSoft
        case .ok: Theme.okSoft
        }
    }
}

public struct ProjectChip: View {
    private let text: String
    private let detail: String?
    private let colorIndex: Int

    /// `detail` (for example a duration) never truncates; the name gives way first.
    public init(_ text: String, detail: String? = nil, colorIndex: Int) {
        self.text = text
        self.detail = detail
        self.colorIndex = colorIndex
    }

    public var body: some View {
        HStack(spacing: 4) {
            Text(text).lineLimit(1).truncationMode(.tail)
            if let detail { Text(detail).lineLimit(1).fixedSize() }
        }
            .font(Theme.chip)
            .foregroundStyle(Theme.text)
            .padding(.vertical, 1)
            .padding(.horizontal, 5)
            .background(Theme.chips[(colorIndex % 6 + 6) % 6], in: RoundedRectangle(cornerRadius: Theme.chipCorner))
    }
}

public struct ScheduledChip: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text("◷ " + text)
            .font(Theme.chip)
            .foregroundStyle(Theme.onAccent)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.vertical, 1)
            .padding(.horizontal, 5)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.chipCorner))
    }
}

public struct NoteMarker: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text("✎ " + text)
            .font(Theme.chip)
            .foregroundStyle(Theme.muted)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.vertical, 1)
            .padding(.leading, 2)
            .padding(.trailing, 5)
    }
}

public struct LiveDot: View {
    public init() {}

    public var body: some View {
        Circle()
            .fill(Theme.live)
            .frame(width: 7, height: 7)
            .help("Open Now")
            .accessibilityLabel("Open Now")
    }
}

public struct SpecBar: View {
    private let done: Int
    private let total: Int

    public init(done: Int, total: Int) {
        self.done = done
        self.total = total
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Theme.specTrack)
            .frame(width: 60, height: 5)
            .overlay(alignment: .leading) {
                if total > 0 {
                    Rectangle()
                        .fill(Theme.accent)
                        .frame(width: 60 * CGFloat(min(1, max(0, Double(done) / Double(total)))))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .accessibilityLabel("Spec progress")
            .accessibilityValue("\(done)/\(total)")
    }
}

public struct SectionHeader: View {
    private let title: String

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        Text(title.uppercased())
            .font(Theme.caption)
            .tracking(0.44)
            .foregroundStyle(Theme.muted)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }
}

public struct KeyValueGrid: View {
    private let rows: [(String, String)]

    public init(_ rows: [(String, String)]) {
        self.rows = rows
    }

    public var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 8, verticalSpacing: 5) {
            ForEach(rows.indices, id: \.self) { index in
                GridRow(alignment: .top) {
                    Text(rows[index].0)
                        .foregroundStyle(Theme.muted)
                        .frame(width: Theme.keyColumnWidth, alignment: .leading)
                    Text(rows[index].1)
                        .foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .font(Theme.keyValue)
    }
}

extension NoteCard where Accessory == EmptyView {
    public init(date: String, text: String, scheduled: Bool, badge: String? = nil) {
        self.init(date: date, text: text, scheduled: scheduled, badge: badge) { EmptyView() }
    }
}

/// `accessory` sits at the right of the date line, inside the card, so controls read as belonging to that note.
public struct NoteCard<Accessory: View>: View {
    private let date: String
    private let text: String
    private let scheduled: Bool
    private let badge: String?
    private let accessory: Accessory

    public init(date: String, text: String, scheduled: Bool, badge: String? = nil, @ViewBuilder accessory: () -> Accessory) {
        self.date = date
        self.text = text
        self.scheduled = scheduled
        self.badge = badge
        self.accessory = accessory()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text((scheduled ? "◷ " : "") + date)
                    .font(Theme.chip)
                    .foregroundStyle(Theme.muted)
                Spacer(minLength: 8)
                if let badge { Tag(badge) }
                accessory
            }
            Text(text)
                .font(Theme.body)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if scheduled {
                RoundedRectangle(cornerRadius: Theme.corner).fill(Theme.accentSoft)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.corner)
                .strokeBorder(scheduled ? Theme.accent : Theme.line, lineWidth: 1)
        }
    }
}

public struct Sparkline: View {
    private let values: [Double]

    public init(values: [Double]) {
        self.values = values
    }

    public var body: some View {
        let maximum = values.filter { $0.isFinite && $0 > 0 }.max() ?? 0
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(values.indices, id: \.self) { index in
                let value = values[index].isFinite ? max(0, values[index]) : 0
                let fraction = maximum > 0 ? max(0.02, value / maximum) : 0.02
                UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2)
                    .fill(Theme.accent.opacity(0.75))
                    .frame(maxWidth: .infinity)
                    .frame(height: 46 * CGFloat(fraction))
            }
        }
        .frame(height: 46, alignment: .bottom)
    }
}

public struct Banner: View {
    private let text: String
    private let tone: Tag.Tone

    public init(_ text: String, tone: Tag.Tone) {
        self.text = text
        self.tone = tone
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if case .warn = tone {
                Image(systemName: "exclamationmark.triangle")
            }
            Text(text)
        }
        .font(Theme.body)
        .foregroundStyle(foreground)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .background(background)
    }

    private var foreground: Color {
        switch tone {
        case .neutral: Theme.text
        case .warn: Theme.warn
        case .ok: Theme.ok
        }
    }

    private var background: Color {
        switch tone {
        case .neutral: Theme.side
        case .warn: Theme.warnSoft
        case .ok: Theme.okSoft
        }
    }
}
