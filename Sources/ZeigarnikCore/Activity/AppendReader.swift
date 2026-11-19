import CryptoKit
import Darwin
import Foundation

public struct FileCursor: Sendable, Equatable, Codable {
    public let inode: UInt64
    public let size: Int64
    public let offset: Int64
    public let headLength: Int
    public let headHash: String

    public init(inode: UInt64, size: Int64, offset: Int64, headLength: Int, headHash: String) {
        self.inode = inode
        self.size = size
        self.offset = offset
        self.headLength = headLength
        self.headHash = headHash
    }
}

public struct AppendedRead: Sendable {
    public let lines: [Data]
    public let cursor: FileCursor
    public let restarted: Bool

    public init(lines: [Data], cursor: FileCursor, restarted: Bool) {
        self.lines = lines
        self.cursor = cursor
        self.restarted = restarted
    }
}

public func readAppended(_ file: URL, after previous: FileCursor?, maxBytes: Int = .max) throws -> AppendedRead {
    let handle = try FileHandle(forReadingFrom: file)
    defer { try? handle.close() }
    var metadata = stat()
    guard fstat(handle.fileDescriptor, &metadata) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    let inode = UInt64(metadata.st_ino)
    let size = Int64(metadata.st_size)
    guard size >= 0 else { throw CocoaError(.fileReadUnknown) }
    let headLength = Int(min(4096, size))
    let head = try readBytes(headLength, from: handle)

    var offset: Int64 = 0
    var restarted = false
    if let previous {
        let canResume = previous.inode == inode
            && previous.size <= size
            && previous.offset >= 0
            && previous.offset <= previous.size
            && previous.headLength >= 0
            && previous.headLength <= head.count
            && headDigest(Data(head.prefix(previous.headLength))) == previous.headHash
        restarted = !canResume
        if canResume { offset = previous.offset }
    }

    try handle.seek(toOffset: UInt64(offset))
    var lines: [Data] = []
    var partialLine = Data()
    var position = offset
    var completeOffset = offset
    var batchFull = false
    while position < size, !batchFull {
        let chunkSize = Int(min(65_536, size - position))
        let chunk = try readBytes(chunkSize, from: handle)
        var lineStart = chunk.startIndex
        for index in chunk.indices where chunk[index] == 10 {
            partialLine.append(chunk[lineStart..<index])
            lines.append(partialLine)
            partialLine = Data()
            lineStart = chunk.index(after: index)
            completeOffset = position + Int64(chunk.distance(from: chunk.startIndex, to: lineStart))
            if completeOffset - offset >= Int64(maxBytes) {
                batchFull = true
                break
            }
        }
        if !batchFull { partialLine.append(chunk[lineStart..<chunk.endIndex]) }
        position += Int64(chunk.count)
    }

    try handle.seek(toOffset: 0)
    guard try readBytes(headLength, from: handle) == head else {
        throw CocoaError(.fileReadUnknown)
    }
    return AppendedRead(
        lines: lines,
        cursor: FileCursor(
            inode: inode,
            size: size,
            offset: completeOffset,
            headLength: headLength,
            headHash: headDigest(head)
        ),
        restarted: restarted
    )
}

private func readBytes(_ count: Int, from handle: FileHandle) throws -> Data {
    var bytes = Data()
    while bytes.count < count {
        guard let chunk = try handle.read(upToCount: count - bytes.count), !chunk.isEmpty else {
            throw CocoaError(.fileReadUnknown)
        }
        bytes.append(chunk)
    }
    return bytes
}

private func headDigest(_ bytes: Data) -> String {
    SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
}
