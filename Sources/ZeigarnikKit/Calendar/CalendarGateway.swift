import Foundation

/// `writeOnly`: the app may add events but cannot read them back, so it cannot find or update its own events.
public enum CalendarAccess: Sendable { case granted, writeOnly, denied, notDetermined }

public struct CalendarInfo: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let sourceTitle: String

    public init(id: String, title: String, sourceTitle: String) {
        self.id = id
        self.title = title
        self.sourceTitle = sourceTitle
    }
}

public struct CalendarEvent: Sendable, Equatable {
    public let identifier: String
    public let calendarId: String
    public let title: String
    public let start: Date
    public let end: Date
    public let itemId: UUID?

    public init(identifier: String, calendarId: String, title: String, start: Date, end: Date, itemId: UUID?) {
        self.identifier = identifier
        self.calendarId = calendarId
        self.title = title
        self.start = start
        self.end = end
        self.itemId = itemId
    }
}

/// The gateway stores `itemId` in the event as `zeigarnik://item/<uuid>` (URL) and a `Zeigarnik: <uuid>` notes line.
public struct EventDraft: Sendable, Equatable {
    public let itemId: UUID
    public let title: String
    public let start: Date
    public let end: Date

    public init(itemId: UUID, title: String, start: Date, end: Date) {
        self.itemId = itemId
        self.title = title
        self.start = start
        self.end = end
    }
}

public protocol CalendarGateway: Sendable {
    func access() -> CalendarAccess
    func requestAccess() async -> Bool
    func calendars() -> [CalendarInfo]
    func event(identifier: String) throws -> CalendarEvent?
    /// Events carrying `itemId` in a window from one year before to one year after `around`, across all event calendars.
    func events(itemId: UUID, around: Date) throws -> [CalendarEvent]
    func create(_ draft: EventDraft, calendarId: String) throws -> String
    func update(identifier: String, with draft: EventDraft) throws
    func remove(identifier: String) throws
}
