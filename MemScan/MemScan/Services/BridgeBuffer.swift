import Foundation

enum BridgeBuffer {
    static func withProcessBuffer<T>(_ capacity: Int, _ work: (UnsafeMutablePointer<MSProcessInfo>, Int) throws -> T) rethrows -> T {
        var sample = MSProcessInfo()
        let bytes = capacity * MemoryLayout.size(ofValue: sample)
        var storage = [UInt8](repeating: 0, count: bytes)
        return try storage.withUnsafeMutableBytes { raw in
            let base = raw.baseAddress!.assumingMemoryBound(to: MSProcessInfo.self)
            return try work(base, capacity)
        }
    }

    static func withScanMatchBuffer<T>(_ capacity: Int, _ work: (UnsafeMutablePointer<MSScanMatch>, Int) throws -> T) rethrows -> T {
        var sample = MSScanMatch()
        let bytes = capacity * MemoryLayout.size(ofValue: sample)
        var storage = [UInt8](repeating: 0, count: bytes)
        return try storage.withUnsafeMutableBytes { raw in
            let base = raw.baseAddress!.assumingMemoryBound(to: MSScanMatch.self)
            return try work(base, capacity)
        }
    }
}
