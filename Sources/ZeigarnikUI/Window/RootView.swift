import SwiftUI
import ZeigarnikKit

public struct RootView: View {
    let environment: AppEnvironment
    @Bindable var model: AppModel
    @State private var inspectorShown = false
    @State private var showGoTo = false
    @State private var scheduleDraft: ScheduleDraft?

    public init(environment: AppEnvironment) {
        self.environment = environment
        self.model = environment.model
    }

    public var body: some View {
        NavigationSplitView {
            SidebarView(model: model, showOpenNow: environment.herdrAvailable)
        } detail: {
            VStack(spacing: 0) {
                banners
                content
            }
            .inspector(isPresented: $inspectorShown) {
                inspector.inspectorColumnWidth(min: 300, ideal: 340, max: 460)
            }
        }
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Search projects")
        .toolbar { toolbar }
        .background(shortcuts)
        .onChange(of: model.sidebar) { _, _ in model.view = .list }
        .onChange(of: model.revision) { _, _ in environment.refreshUpcoming() }
        .onChange(of: model.selectedProjectId) { _, id in if id != nil { inspectorShown = true } }
        .onChange(of: model.selectedDay) { _, _ in if model.view == .calendar { inspectorShown = true } }
        .frame(minWidth: 1000, minHeight: 620)
        .sheet(isPresented: $showGoTo) { GoToDateSheet(model: model) }
        .sheet(isPresented: Binding(get: { scheduleDraft != nil }, set: { if !$0 { scheduleDraft = nil } })) {
            if let draft = scheduleDraft {
                ScheduleSheet(model: model, draft: draft, calendarTitle: environment.calendarTitle, calendarWarning: environment.calendarWarning) { saved in
                    if saved.addToCalendar { environment.ensureCalendarAccess() }
                }
            }
        }
        .onAppear { environment.start() }
        #if DEBUG
        .onChange(of: model.isLoaded) { _, loaded in
            guard loaded else { return }
            let args = ProcessInfo.processInfo.arguments
            func value(_ flag: String) -> String? { args.firstIndex(of: flag).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } }
            if let name = value("--select") { model.selectedProjectId = model.rows.first { $0.displayName == name }?.id }
            if let day = value("--day") { model.goTo(day: day) }
        }
        #endif
    }

    @ViewBuilder private var content: some View {
        switch model.view {
        case .list:
            if case .other = model.sidebar { OtherBucketView(model: model) } else { ProjectTableView(environment: environment, model: model) }
        case .calendar:
            MonthView(model: model)
        }
    }

    @ViewBuilder private var inspector: some View {
        if model.view == .calendar {
            DayInspector(model: model, day: model.selectedDay) { scheduleDraft = $0 }
        } else if let id = model.selectedProjectId, let row = model.row(id) {
            ProjectInspector(environment: environment, model: model, row: row) { scheduleDraft = $0 }
        } else {
            Text(model.view == .list ? "Select a project" : "Select a day").foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private var banners: some View {
        if let error = environment.startupError { Banner(error, tone: .warn) }
        if let error = model.loadError { Banner(error, tone: .warn) }
        if let error = model.ownerDataError { Banner(error, tone: .warn) }
        ForEach(model.sourceProblems, id: \.path) { problem in
            Banner(problem.message, tone: .warn)
                .overlay(alignment: .trailing) {
                    if problem.kind == .root || problem.kind == .vault {
                        SettingsLink { Text("Open Settings") }.padding(.trailing, 14)
                    }
                }
        }
        if let report = environment.coordinator.lastReport, !report.relinks.isEmpty {
            Banner("Moved projects found again (\(report.relinks.count)): " + report.relinks.prefix(3).map { model.displayName($0.projectId) }.joined(separator: ", "), tone: .neutral)
                .help(report.relinks.map { "\($0.fromPath) → \($0.toPath)" }.joined(separator: "\n"))
        }
        if let report = environment.coordinator.lastReport, !report.errors.isEmpty {
            Banner("Errors in last scan (\(report.errors.count)): " + report.errors.prefix(2).map { error in (error.projectPath.map { ($0 as NSString).lastPathComponent + ": " } ?? "") + error.message }.joined(separator: "; "), tone: .warn)
                .help(report.errors.map { ($0.projectPath ?? "") + " " + $0.message }.joined(separator: "\n"))
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("View", selection: $model.view) {
                Text("List").tag(MainView.list)
                Text("Calendar").tag(MainView.calendar)
            }
            .pickerStyle(.segmented)
            .fixedSize()
        }
        ToolbarItem {
            Button { showGoTo = true } label: { Label("Go to Date…", systemImage: "calendar.badge.clock") }
                .keyboardShortcut("l")
                .help("Go to date (⌘L)")
        }
        ToolbarItem {
            Button { environment.coordinator.requestScan(fetch: true) } label: {
                if environment.coordinator.isScanning { ProgressView().controlSize(.small) } else { Label("Scan", systemImage: "arrow.clockwise") }
            }
            .keyboardShortcut("r")
            .help(scanHelp)
        }
        ToolbarItem {
            Button { inspectorShown.toggle() } label: { Label("Details", systemImage: "sidebar.right") }
        }
    }

    private var scanHelp: String {
        guard let report = environment.coordinator.lastReport else { return "Scan now (⌘R)" }
        return "Scan now (⌘R) · last scan \(UIFormat.time(report.finishedAt, model.calendar))"
    }

    private var shortcuts: some View {
        Group {
            Button("") { model.view = .list }.keyboardShortcut("1")
            Button("") { model.view = .calendar }.keyboardShortcut("2")
        }
        .opacity(0)
        .allowsHitTesting(false)
    }
}
