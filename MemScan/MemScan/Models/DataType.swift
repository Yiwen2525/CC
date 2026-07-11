import Foundation

enum DataType: String, CaseIterable, Identifiable {
    case int8 = "Int8"
    case int16 = "Int16"
    case int32 = "Int32"
    case int64 = "Int64"
    case uint8 = "UInt8"
    case uint16 = "UInt16"
    case uint32 = "UInt32"
    case uint64 = "UInt64"
    case float = "Float"
    case double = "Double"

    var id: String { rawValue }

    var byteSize: Int {
        switch self {
        case .int8, .uint8: return 1
        case .int16, .uint16: return 2
        case .int32, .uint32, .float: return 4
        case .int64, .uint64, .double: return 8
        }
    }

    var isFloatingPoint: Bool {
        self == .float || self == .double
    }

    func parseValue(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed)
    }

    func formatValue(_ value: Double) -> String {
        if isFloatingPoint {
            return String(format: "%.6g", value)
        }
        return String(format: "%.0f", value)
    }
}
