import SwiftUI
import ZeigarnikKit

struct MonthView: View {
    @Bindable var model: AppModel
    @State private var ownerData = MonthOwnerData()

    var body: some View {
        let grid = monthGrid(year: model.visibleYear, month: model.visibleMonth, today: model.today, calendar: model.calendar)
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                ForEach(Array(weekdayHeaders(calendar: model.calendar).enumerated()), id: \.offset) { _, name in
                    Text(name).font(Theme.caption).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .trailing).padding(.horizontal, 8).padding(.vertical, 6)
                }
            }
            Divider()
            GeometryReader { proxy in
                let rowHeight = max(108, proxy.size.height / 6)
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                        ForEach(grid, id: \.day) { day in
                            DayCell(model: model, day: day, items: ownerData.items[day.day] ?? [], notes: ownerData.notes[day.day] ?? [],
                                    selected: day.day == model.selectedDay)
                                .frame(height: rowHeight)
                                .contentShape(Rectangle())
                                .onTapGesture { model.selectedDay = day.day }
                        }
                    }
                }
            }
        }
        .task(id: "\(model.visibleYear)-\(model.visibleMonth)-\(model.revision)") {
            ownerData = await model.monthOwnerData(fromDay: grid.first?.day ?? model.today, toDay: grid.last?.day ?? model.today)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(Format.monthTitle(year: model.visibleYear, month: model.visibleMonth, calendar: model.calendar)).font(Theme.title)
            Spacer()
            Button { model.showMonth(offset: -1) } label: { Image(systemName: "chevron.left") }.help("Previous month")
            Button("Today") { model.showToday() }
            Button { model.showMonth(offset: 1) } label: { Image(systemName: "chevron.right") }.help("Next month")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct DayCell: View {
    let model: AppModel
    let day: GridDay
    let items: [ScheduledItem]
    let notes: [Note]
    let selected: Bool

    var body: some View {
        let slices = model.activity.slices(day: day.day)
        let projects = slices.filter { if case .project = $0.owner { return true } else { return false } }
        let total = model.activity.dayTotal(day.day)
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                if total > 0 { Text(Format.duration(total)).font(Theme.dayTotal).foregroundStyle(Theme.muted) }
                Spacer()
                dayNumber
            }
            ForEach(items.prefix(2)) { item in
                ScheduledChip("\(UIFormat.time(item.start, model.calendar)) \(model.displayName(item.projectId))")
            }
            ForEach(Array(projects.prefix(3).enumerated()), id: \.offset) { _, slice in
                if case .project(let id) = slice.owner {
                    ProjectChip(model.displayName(id), detail: slice.seconds > 0 ? Format.duration(slice.seconds) : nil, colorIndex: stableColorIndex(for: id))
                }
            }
            if projects.count > 3 {
                Text("+\(projects.count - 3)").font(Theme.chip).foregroundStyle(Theme.muted)
            }
            ForEach(notes.prefix(1)) { note in
                NoteMarker("\(model.displayName(note.projectId)): \(note.text)")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(day.inMonth ? Color.clear : Theme.side.opacity(0.6))
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.line).frame(width: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
        .overlay { if selected { Rectangle().strokeBorder(Theme.accent, lineWidth: 2) } }
        .clipped()
    }

    @ViewBuilder private var dayNumber: some View {
        let text = Text("\(day.dayOfMonth)").font(.system(size: 12))
        if day.isToday {
            text.foregroundStyle(Theme.onAccent).padding(.horizontal, 6).padding(.vertical, 1).background(Theme.today, in: Capsule())
        } else {
            text.foregroundStyle(day.inMonth ? Theme.text : Theme.muted)
        }
    }
}
