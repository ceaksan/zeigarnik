/// FNV-1a 64 over UTF-8; `hashValue` is seeded per launch and would recolor projects on every start.
public func stableColorIndex(for id: String) -> Int {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in id.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x0000_0100_0000_01b3
    }
    return Int(hash % 6)
}
