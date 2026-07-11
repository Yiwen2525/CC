import Foundation

enum SearchScope: String, CaseIterable, Identifiable {
    case all = "全部"
    case heap = "堆 (Heap)"
    case stack = "栈 (Stack)"
    case anonymous = "匿名映射"
    case shared = "共享内存"
    case executable = "可执行段"

    var id: String { rawValue }

    var regionFilter: UInt32 {
        switch self {
        case .all: return 0
        case .heap: return 1
        case .stack: return 2
        case .anonymous: return 3
        case .shared: return 4
        case .executable: return 5
        }
    }
}

enum RefineMode: String, CaseIterable, Identifiable {
    case exact = "精确值"
    case increased = "数值增大"
    case decreased = "数值减小"
    case unchanged = "数值不变"
    case changed = "数值改变"

    var id: String { rawValue }
}
