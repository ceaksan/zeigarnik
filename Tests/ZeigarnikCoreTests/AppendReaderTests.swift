import CryptoKit
import Foundation
import Testing
@testable import ZeigarnikCore

@Suite("AppendReader")
struct AppendReaderTests {
    @Test func readsCompleteLinesAndAdvances() throws {
        let directory = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("activity.jsonl")
        let original = Data("a\nb\n".utf8)
        try original.write(to: file)

        let first = try readAppended(file, after: nil)
        #expect(first.lines == [Data("a".utf8), Data("b".utf8)])
        #expect(first.cursor.offset == 4)
        #expect(first.cursor.size == 4)
        #expect(first.cursor.headLength == 4)
        #expect(first.cursor.headHash == digest(original))
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let inode = try #require(attributes[.systemFileNumber] as? NSNumber)
        #expect(first.cursor.inode == inode.uint64Value)

        try append(Data("c\n".utf8), to: file)
        let second = try readAppended(file, after: first.cursor)
        #expect(second.lines == [Data("c".utf8)])
        #expect(second.cursor.offset == 6)
        #expect(second.cursor.size == 6)
        #expect(second.cursor.headLength == 6)
        #expect(second.cursor.headHash == digest(Data("a\nb\nc\n".utf8)))
        #expect(!second.restarted)
    }

    @Test func partialLastLineIsNotConsumed() throws {
        let directory = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("activity.jsonl")
        try Data("a\nb".utf8).write(to: file)

        let first = try readAppended(file, after: nil)
        #expect(first.lines == [Data("a".utf8)])
        #expect(first.cursor.offset == 2)
        #expect(first.cursor.size == 3)
        try append(Data("c\n".utf8), to: file)

        let second = try readAppended(file, after: first.cursor)
        #expect(second.lines == [Data("bc".utf8)])
        #expect(second.cursor.offset == 5)
        #expect(second.cursor.size == 5)
        #expect(!second.restarted)
    }

    @Test func truncationRestarts() throws {
        let directory = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("activity.jsonl")
        try Data("a\nb\nc\n".utf8).write(to: file)
        let first = try readAppended(file, after: nil)
        try overwrite(Data("a\n".utf8), at: file)

        let second = try readAppended(file, after: first.cursor)
        #expect(second.restarted)
        #expect(second.lines == [Data("a".utf8)])
        #expect(second.cursor.offset == 2)
        #expect(second.cursor.size == 2)
        #expect(second.cursor.headLength == 2)
    }

    @Test func replacementWithSameSizeRestarts() throws {
        let directory = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("activity.jsonl")
        try Data("a\nb\n".utf8).write(to: file)
        let first = try readAppended(file, after: nil)
        try overwrite(Data("x\ny\n".utf8), at: file)

        let second = try readAppended(file, after: first.cursor)
        #expect(second.cursor.inode == first.cursor.inode)
        #expect(second.cursor.size == first.cursor.size)
        #expect(second.cursor.headHash != first.cursor.headHash)
        #expect(second.restarted)
        #expect(second.lines == [Data("x".utf8), Data("y".utf8)])
        #expect(second.cursor.offset == 4)
    }

    @Test func unchangedFileReadsNothing() throws {
        let directory = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("activity.jsonl")
        try Data("a\nb\n".utf8).write(to: file)
        let first = try readAppended(file, after: nil)
        #expect(first.cursor.offset == 4)

        let second = try readAppended(file, after: first.cursor)
        #expect(second.lines.isEmpty)
        #expect(second.cursor == first.cursor)
        #expect(!second.restarted)
    }

    @Test func growthAcross4096BytesIsNotReplacement() throws {
        let directory = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("activity.jsonl")
        let firstLine = Data(String(repeating: "a", count: 2999).utf8)
        let secondLine = Data(String(repeating: "b", count: 2999).utf8)
        let original = firstLine + Data([10])
        let added = secondLine + Data([10])
        try original.write(to: file)
        let first = try readAppended(file, after: nil)
        #expect(first.lines == [firstLine])
        #expect(first.cursor.offset == 3000)
        #expect(first.cursor.headLength == 3000)
        try append(added, to: file)

        let second = try readAppended(file, after: first.cursor)
        #expect(second.lines == [secondLine])
        #expect(!second.restarted)
        #expect(second.cursor.offset == 6000)
        #expect(second.cursor.size == 6000)
        #expect(second.cursor.headLength == 4096)
        #expect(second.cursor.headHash == digest(Data((original + added).prefix(4096))))
    }

    @Test func replacementWithSameContentAndNewInodeRestarts() throws {
        let directory = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("activity.jsonl")
        let bytes = Data("a\nb\n".utf8)
        try bytes.write(to: file)
        let first = try readAppended(file, after: nil)
        try FileManager.default.moveItem(at: file, to: directory.appendingPathComponent("previous.jsonl"))
        try bytes.write(to: file)

        let second = try readAppended(file, after: first.cursor)
        #expect(second.cursor.inode != first.cursor.inode)
        #expect(second.cursor.headHash == first.cursor.headHash)
        #expect(second.restarted)
        #expect(second.lines == [Data("a".utf8), Data("b".utf8)])
    }

    @Test func utf8OffsetsAreByteCounts() throws {
        let directory = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("activity.jsonl")
        try Data("ç\nğ".utf8).write(to: file)
        let first = try readAppended(file, after: nil)
        #expect(first.lines == [Data("ç".utf8)])
        #expect(first.cursor.offset == 3)
        #expect(first.cursor.size == 5)
        try append(Data([10]), to: file)

        let second = try readAppended(file, after: first.cursor)
        #expect(second.lines == [Data("ğ".utf8)])
        #expect(second.cursor.offset == 6)
        #expect(!second.restarted)
    }

    private func append(_ data: Data, to file: URL) throws {
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        _ = try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    private func overwrite(_ data: Data, at file: URL) throws {
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.truncate(atOffset: 0)
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: data)
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    @Test func readsInBoundedBatches() throws {
        let dir = try makeTempDir()
        let file = dir.appendingPathComponent("batch.jsonl")
        try Data((0..<5).map { "line-\($0)xxx\n" }.joined().utf8).write(to: file)
        let first = try readAppended(file, after: nil, maxBytes: 15)
        #expect(first.lines.count == 2)
        #expect(first.cursor.offset == 20)
        let second = try readAppended(file, after: first.cursor, maxBytes: 15)
        #expect(second.lines.count == 2)
        let third = try readAppended(file, after: second.cursor, maxBytes: 15)
        #expect(third.lines.count == 1)
        #expect(third.cursor.offset == 50)
        let done = try readAppended(file, after: third.cursor, maxBytes: 15)
        #expect(done.lines.isEmpty)
    }
}
