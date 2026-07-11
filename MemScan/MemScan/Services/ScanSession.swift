import Foundation

enum ScanError: LocalizedError {
    case attachFailed
    case scanFailed(String)
    case noResults
    case writeFailed(String)
    case memoryUnavailable

    var errorDescription: String? {
        switch self {
        case .attachFailed:
            return "无法附加到目标进程"
        case .scanFailed(let message):
            return message
        case .noResults:
            return "没有搜索结果"
        case .writeFailed(let message):
            return message
        case .memoryUnavailable:
            return MemScanBridge.memoryAccessErrorMessage()
        }
    }
}

@MainActor
final class ScanSession: ObservableObject {
    @Published var selectedProcess: ProcessInfo?
    @Published var dataType: DataType = .int32
    @Published var searchScope: SearchScope = .all
    @Published var refineMode: RefineMode = .exact
    @Published var searchValue: String = ""
    @Published var refineValue: String = ""
    @Published var results: [ScanResult] = []
    @Published var isScanning = false
    @Published var errorMessage: String?
    @Published var hasScanned = false

    var resultCountText: String {
        "\(results.count) 个地址"
    }

    func selectProcess(_ process: ProcessInfo) {
        selectedProcess = process
        resetResults()
        do {
            try ProcessService.shared.attach(to: process)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func firstScan() async {
        guard let value = dataType.parseValue(searchValue) else {
            errorMessage = "请输入有效的搜索数值"
            return
        }

        await performScan { [self] in
            try self.runFirstScan(value: value)
        }
    }

    func refineScan() async {
        guard hasScanned else {
            errorMessage = "请先进行首次搜索"
            return
        }

        let value = refineMode == .exact ? dataType.parseValue(refineValue) : 0
        if refineMode == .exact && value == nil {
            errorMessage = "请输入精搜数值"
            return
        }

        await performScan { [self] in
            try self.runRefineScan(value: value ?? 0)
        }
    }

    func modifyResult(_ result: ScanResult, newValueText: String) throws {
        guard let newValue = dataType.parseValue(newValueText) else {
            throw ScanError.writeFailed("无效数值")
        }

        var error: NSError?
        let ok = MemScanBridge.writeValue(
            newValue,
            dataType: dataType.bridgeType,
            address: result.address,
            error: &error
        )
        if !ok {
            throw error.map { ScanError.writeFailed($0.localizedDescription) } ?? ScanError.writeFailed("写入失败")
        }

        if let index = results.firstIndex(of: result) {
            results[index] = ScanResult(address: result.address, value: newValue)
        }
    }

    func resetResults() {
        MemScanBridge.clearResults()
        results = []
        hasScanned = false
        refineValue = ""
        errorMessage = nil
    }

    func refreshDisplayedResults(limit: Int = 500) {
        results = loadResults(limit: limit)
    }

    private func performScan(_ block: @escaping () throws -> Void) async {
        isScanning = true
        errorMessage = nil

        do {
            try await Task.detached(priority: .userInitiated) {
                try block()
            }.value
            hasScanned = true
            refreshDisplayedResults()
        } catch {
            errorMessage = error.localizedDescription
        }

        isScanning = false
    }

    private func runFirstScan(value: Double) throws {
        var error: NSError?
        let capacity = 500

        try BridgeBuffer.withScanMatchBuffer(capacity) { buffer, capacity in
            let count = MemScanBridge.firstScan(
                withValue: value,
                dataType: dataType.bridgeType,
                regionFilter: searchScope.bridgeFilter,
                matches: buffer,
                capacity: capacity,
                error: &error
            )

            if let error {
                throw ScanError.scanFailed(error.localizedDescription)
            }

            if count == 0 && MemScanBridge.storedResultCount() == 0 {
                throw ScanError.noResults
            }
        }
    }

    private func runRefineScan(value: Double) throws {
        var error: NSError?
        let capacity = 500

        try BridgeBuffer.withScanMatchBuffer(capacity) { buffer, capacity in
            let count = MemScanBridge.refineScan(
                withValue: value,
                mode: refineMode.bridgeMode,
                dataType: dataType.bridgeType,
                matches: buffer,
                capacity: capacity,
                error: &error
            )

            if let error {
                throw ScanError.scanFailed(error.localizedDescription)
            }

            if count == 0 && MemScanBridge.storedResultCount() == 0 {
                throw ScanError.noResults
            }
        }
    }

    private func loadResults(limit: Int) -> [ScanResult] {
        let total = MemScanBridge.storedResultCount()
        guard total > 0 else { return [] }

        let capacity = min(total, limit)
        return BridgeBuffer.withScanMatchBuffer(capacity) { buffer, capacity in
            let count = MemScanBridge.copyResultsTo(buffer, capacity: capacity)
            return (0..<count).map { index in
                let item = buffer[index]
                return ScanResult(address: item.address, value: item.value)
            }
        }
    }
}

private extension DataType {
    var bridgeType: MSDataType {
        switch self {
        case .int8: return .int8
        case .int16: return .int16
        case .int32: return .int32
        case .int64: return .int64
        case .uint8: return .uInt8
        case .uint16: return .uInt16
        case .uint32: return .uInt32
        case .uint64: return .uInt64
        case .float: return .float
        case .double: return .double
        }
    }
}

private extension SearchScope {
    var bridgeFilter: MSRegionFilter {
        switch self {
        case .all: return .all
        case .heap: return .heap
        case .stack: return .stack
        case .anonymous: return .anonymous
        case .shared: return .shared
        case .executable: return .executable
        }
    }
}

private extension RefineMode {
    var bridgeMode: MSRefineMode {
        switch self {
        case .exact: return .exact
        case .increased: return .increased
        case .decreased: return .decreased
        case .unchanged: return .unchanged
        case .changed: return .changed
        }
    }
}
