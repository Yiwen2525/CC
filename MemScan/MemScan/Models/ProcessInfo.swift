import Foundation

struct ProcessInfo: Identifiable, Hashable {
    let pid: Int32
    let name: String
    let bundleID: String?

    var id: Int32 { pid }

    var displayName: String {
        if let bundleID, !bundleID.isEmpty {
            return "\(name) (\(bundleID))"
        }
        return name
    }
}

struct ScanResult: Identifiable, Hashable {
    let address: UInt64
    let value: Double

    var id: UInt64 { address }

    var addressHex: String {
        String(format: "0x%llX", address)
    }
}
