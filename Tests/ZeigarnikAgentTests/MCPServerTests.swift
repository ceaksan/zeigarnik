import Foundation
import Testing
@testable import ZeigarnikAgent
@testable import ZeigarnikCore

@Suite struct MCPServerTests {
    let store: Store
    let server: MCPServer
    let orbit: String

    init() throws {
        store = try Store.inMemory()
        orbit = try store.upsertProject(resolution: .new, path: "/root/02_Products/orbit", displayName: "orbit", identity: nil)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        server = MCPServer(service: AgentService(store: store, now: { Date(timeIntervalSince1970: 1_795_046_400) }, calendar: calendar))
    }

    func send(_ json: String) throws -> [String: Any]? {
        guard let line = server.handle(line: json) else { return nil }
        #expect(!line.contains("\n"))
        return try #require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
    }

    func call(_ name: String, _ arguments: String, id: Int = 9) throws -> (text: String, isError: Bool) {
        let response = try #require(try send(#"{"jsonrpc":"2.0","id":\#(id),"method":"tools/call","params":{"name":"\#(name)","arguments":\#(arguments)}}"#))
        let result = try #require(response["result"] as? [String: Any])
        let content = try #require(result["content"] as? [[String: Any]])
        return (content.first?["text"] as? String ?? "", result["isError"] as? Bool ?? false)
    }

    @Test func initializeEchoesAKnownProtocolVersion() throws {
        let response = try #require(try send(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}"#))
        let result = try #require(response["result"] as? [String: Any])
        #expect(result["protocolVersion"] as? String == "2025-06-18")
        #expect((result["capabilities"] as? [String: Any])?["tools"] != nil)
        #expect((result["serverInfo"] as? [String: Any])?["name"] as? String == "zeigarnik")
        #expect(response["id"] as? Int == 1)
    }

    @Test func notificationsGetNoResponse() throws {
        #expect(try send(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)
    }

    @Test func toolListHasNoDeleteTool() throws {
        let response = try #require(try send(#"{"jsonrpc":"2.0","id":"a","method":"tools/list"}"#))
        let tools = try #require((response["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        let names = tools.compactMap { $0["name"] as? String }
        #expect(names == ["list_projects", "project_status", "list_notes", "get_note", "add_note", "update_note", "list_note_drafts"])
        #expect(!names.contains { $0.contains("delete") })
        #expect(tools.allSatisfy { ($0["inputSchema"] as? [String: Any])?["type"] as? String == "object" })
        #expect(response["id"] as? String == "a")
    }

    @Test func notesCanBeAddedListedAndEdited() throws {
        let added = try call("add_note", #"{"project":"orbit","text":"Rust port"}"#)
        #expect(!added.isError)
        let note = try #require(JSONSerialization.jsonObject(with: Data(added.text.utf8)) as? [String: Any])
        let id = try #require(note["id"] as? String)
        #expect(note["day"] as? String == "2026-11-19")

        let edited = try call("update_note", #"{"id":"\#(id.prefix(8))","text":"Rust port, phase 2"}"#)
        #expect(!edited.isError)
        let listed = try call("list_notes", #"{"project":"orbit"}"#)
        #expect(listed.text.contains("Rust port, phase 2"))
        #expect(try store.notes(projectId: orbit).map(\.text) == ["Rust port, phase 2"])
    }

    @Test func aToolFailureIsAnErrorResultNotAProtocolError() throws {
        let result = try call("add_note", #"{"project":"nova","text":"x"}"#)
        #expect(result.isError)
        #expect(result.text.contains("nova"))
        let missing = try call("get_note", #"{}"#)
        #expect(missing.isError)
        #expect(missing.text.contains("id"))
    }

    @Test func unknownToolsMethodsAndBadJSONAreProtocolErrors() throws {
        let tool = try #require(try send(#"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"delete_note","arguments":{"id":"x"}}}"#))
        #expect((tool["error"] as? [String: Any])?["code"] as? Int == -32602)
        let method = try #require(try send(#"{"jsonrpc":"2.0","id":3,"method":"resources/list"}"#))
        #expect((method["error"] as? [String: Any])?["code"] as? Int == -32601)
        let parse = try #require(try send("{not json"))
        #expect((parse["error"] as? [String: Any])?["code"] as? Int == -32700)
        #expect(parse["id"] is NSNull)
    }
}
