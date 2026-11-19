import Foundation

/// A minimal MCP server over stdio: one JSON-RPC 2.0 message per line, tools only (ADR-006).
public final class MCPServer {
    static let supportedVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]
    static let fallbackVersion = "2025-06-18"

    let service: AgentService
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    public init(service: AgentService) {
        self.service = service
    }

    /// The response line for one request line, or nil for a notification.
    public func handle(line: String) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)), let message = object as? [String: Any] else {
            return encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]])
        }
        guard let id = message["id"] else { return nil }
        guard let method = message["method"] as? String else { return error(id, -32600, "Invalid request") }
        let params = message["params"] as? [String: Any] ?? [:]
        switch method {
        case "initialize":
            let requested = params["protocolVersion"] as? String ?? ""
            return result(id, [
                "protocolVersion": Self.supportedVersions.contains(requested) ? requested : Self.fallbackVersion,
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "zeigarnik", "version": zeigarnikVersion],
                "instructions": "The owner's Zeigarnik projects and notes. Read, add and edit notes; notes cannot be deleted here. "
                    + "Drafts are suggestions from project state; the owner approves them in the app.",
            ])
        case "ping":
            return result(id, [String: Any]())
        case "tools/list":
            return result(id, ["tools": Self.tools])
        case "tools/call":
            guard let name = params["name"] as? String, Self.tools.contains(where: { $0["name"] as? String == name }) else {
                return error(id, -32602, "Unknown tool: \(params["name"] as? String ?? "")")
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            do {
                return result(id, ["content": [["type": "text", "text": try call(name, arguments)]], "isError": false])
            } catch {
                return result(id, ["content": [["type": "text", "text": "\(error)"]], "isError": true])
            }
        default:
            return error(id, -32601, "Method not found: \(method)")
        }
    }

    private func call(_ name: String, _ arguments: [String: Any]) throws -> String {
        func string(_ key: String) -> String? {
            (arguments[key] as? String).flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        }
        func required(_ key: String) throws -> String {
            guard let value = arguments[key] as? String else { throw AgentError.missingArgument(key) }
            return value
        }
        let limit = (arguments["limit"] as? NSNumber)?.intValue
        switch name {
        case "list_projects": return try json(service.projects(matching: string("query")))
        case "project_status": return try json(service.projectStatus(required("project")))
        case "list_notes":
            return try json(service.notes(project: string("project"), since: string("since"), until: string("until"), limit: limit ?? 50))
        case "get_note": return try json(service.note(required("id")))
        case "add_note": return try json(service.addNote(project: required("project"), text: required("text"), day: string("day")))
        case "update_note": return try json(service.updateNote(required("id"), text: required("text")))
        case "list_note_drafts": return try json(service.drafts(project: string("project")))
        default: throw AgentError.missingArgument("name")
        }
    }

    private func json<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private func result(_ id: Any, _ result: [String: Any]) -> String {
        encode(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private func error(_ id: Any, _ code: Int, _ message: String) -> String {
        encode(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
    }

    private func encode(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]) else {
            return #"{"jsonrpc":"2.0","id":null,"error":{"code":-32603,"message":"Internal error"}}"#
        }
        return String(decoding: data, as: UTF8.self)
    }

    static var tools: [[String: Any]] {
        func schema(_ properties: [String: [String: Any]], required: [String] = []) -> [String: Any] {
            ["type": "object", "properties": properties, "required": required, "additionalProperties": false]
        }
        let project: [String: Any] = ["type": "string", "description": "Project id, display name or path, as list_projects shows them."]
        let day: [String: Any] = ["type": "string", "description": "A day as YYYY-MM-DD."]
        let noteId: [String: Any] = ["type": "string", "description": "Note id, or a unique prefix of at least 4 characters."]
        return [
            ["name": "list_projects",
             "description": "List the owner's projects with their state: last activity, branch, unpushed commits, uncommitted files, "
                + "README and architecture drift, note count and open draft count.",
             "inputSchema": schema(["query": ["type": "string", "description": "Only projects whose name or path contains this."]])],
            ["name": "project_status",
             "description": "One project's full state, its 20 most recent notes and its open note drafts.",
             "inputSchema": schema(["project": project], required: ["project"])],
            ["name": "list_notes",
             "description": "The owner's notes, newest first. Filter by project and by day range; 50 notes unless limit says otherwise.",
             "inputSchema": schema(["project": project, "since": day, "until": day,
                                    "limit": ["type": "integer", "minimum": 1, "description": "Maximum number of notes."]])],
            ["name": "get_note",
             "description": "One note by id.",
             "inputSchema": schema(["id": noteId], required: ["id"])],
            ["name": "add_note",
             "description": "Add a note to a project. The day defaults to today.",
             "inputSchema": schema(["project": project, "text": ["type": "string", "description": "The note text."], "day": day],
                                   required: ["project", "text"])],
            ["name": "update_note",
             "description": "Replace a note's text. Its day and project stay the same.",
             "inputSchema": schema(["id": noteId, "text": ["type": "string", "description": "The new text."]], required: ["id", "text"])],
            ["name": "list_note_drafts",
             "description": "Note drafts derived from project state (README or architecture behind, unpushed commits, uncommitted changes) "
                + "that the owner has not accepted or dismissed. The owner approves drafts in the app.",
             "inputSchema": schema(["project": project])],
        ]
    }
}
