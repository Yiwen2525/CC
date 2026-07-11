import Foundation

final class ProcessService {
    static let shared = ProcessService()
    private init() {}

    func fetchProcesses() -> [ProcessInfo] {
        let capacity = 2048
        return BridgeBuffer.withProcessBuffer(capacity) { buffer, capacity in
            let count = MemScanBridge.listProcesses(buffer, capacity: capacity)
            guard count > 0 else { return [] }

            return (0..<count).map { index in
                let item = buffer[index]
                let name = String(cString: item.name)
                let bundleID = String(cString: item.bundle_id)
                return ProcessInfo(
                    pid: item.pid,
                    name: name,
                    bundleID: bundleID.isEmpty ? nil : bundleID
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    func attach(to process: ProcessInfo) throws {
        var error: NSError?
        let ok = MemScanBridge.attachToPID(process.pid, error: &error)
        if !ok {
            throw error ?? ScanError.attachFailed
        }
    }

    func detach() {
        MemScanBridge.detach()
    }
}
