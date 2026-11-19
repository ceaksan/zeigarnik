import EventKit
import Foundation

public final class EventKitGateway: CalendarGateway, @unchecked Sendable {
    private let store = EKEventStore()
    /// The calendar sync actor and the main actor both call in; EKEventStore work is serialized here.
    private let lock = NSLock()

    public enum GatewayError: Error { case calendarNotFound, eventNotFound }

    public init() {}

    public var eventStore: EKEventStore { store }

    public func access() -> CalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .writeOnly: .writeOnly
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    public func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    public func calendars() -> [CalendarInfo] {
        lock.withLock {
            store.calendars(for: .event).filter(\.allowsContentModifications)
                .map { CalendarInfo(id: $0.calendarIdentifier, title: $0.title, sourceTitle: $0.source.title) }
                .sorted { ($0.sourceTitle, $0.title) < ($1.sourceTitle, $1.title) }
        }
    }

    public func event(identifier: String) throws -> CalendarEvent? {
        lock.withLock { store.event(withIdentifier: identifier).map(Self.convert) }
    }

    public func events(itemId: UUID, around: Date) throws -> [CalendarEvent] {
        let year: TimeInterval = 365 * 86_400
        return lock.withLock {
            let predicate = store.predicateForEvents(withStart: around.addingTimeInterval(-year), end: around.addingTimeInterval(year), calendars: nil)
            return store.events(matching: predicate).filter { Self.itemId(of: $0) == itemId }.map(Self.convert)
        }
    }

    public func create(_ draft: EventDraft, calendarId: String) throws -> String {
        try lock.withLock {
            guard let calendar = store.calendar(withIdentifier: calendarId) else { throw GatewayError.calendarNotFound }
            let event = EKEvent(eventStore: store)
            event.calendar = calendar
            Self.apply(draft, to: event)
            try store.save(event, span: .thisEvent, commit: true)
            return event.eventIdentifier
        }
    }

    public func update(identifier: String, with draft: EventDraft) throws {
        try lock.withLock {
            guard let event = store.event(withIdentifier: identifier) else { throw GatewayError.eventNotFound }
            Self.apply(draft, to: event)
            try store.save(event, span: .thisEvent, commit: true)
        }
    }

    public func remove(identifier: String) throws {
        try lock.withLock {
            guard let event = store.event(withIdentifier: identifier) else { return }
            try store.remove(event, span: .thisEvent, commit: true)
        }
    }

    private static func apply(_ draft: EventDraft, to event: EKEvent) {
        event.title = draft.title
        event.startDate = draft.start
        event.endDate = draft.end
        event.url = URL(string: "zeigarnik://item/\(draft.itemId.uuidString)")
        event.notes = "Zeigarnik: \(draft.itemId.uuidString)"
    }

    static func itemId(of event: EKEvent) -> UUID? {
        if let url = event.url, url.scheme == "zeigarnik", let id = UUID(uuidString: url.lastPathComponent) { return id }
        guard let notes = event.notes, let range = notes.range(of: "Zeigarnik: ") else { return nil }
        return UUID(uuidString: String(notes[range.upperBound...].prefix(36)))
    }

    private static func convert(_ event: EKEvent) -> CalendarEvent {
        CalendarEvent(identifier: event.eventIdentifier, calendarId: event.calendar.calendarIdentifier, title: event.title ?? "",
                      start: event.startDate, end: event.endDate, itemId: itemId(of: event))
    }
}
