import Foundation

final class ProcessService {
    static let shared = ProcessService()
    private init() {}

    func fetchProcesses() -> [ProcessInfo] {
        let list = MemScanBridge.fetchProcessList()
        return list.compactMap { item in
            guard let dict = item as? [String: Any],
                  let pidNumber = dict["pid"] as? NSNumber,
                  let name = dict["name"] as? String else {
                return nil
            }
            let bundleID = dict["bundleID"] as? String
            return ProcessInfo(
                pid: pidNumber.int32Value,
                name: name,
                bundleID: bundleID?.isEmpty == true ? nil : bundleID
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func attach(to process: ProcessInfo) throws {
        do {
            try MemScanBridge.attach(toPID: process.pid)
        } catch {
            throw ScanError.attachFailed
        }
    }

    func detach() {
        MemScanBridge.detach()
    }
}
