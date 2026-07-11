import SwiftUI

struct ProcessListView: View {
    @ObservedObject var session: ScanSession
    @State private var processes: [ProcessInfo] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var memoryAvailable = true

    private var filteredProcesses: [ProcessInfo] {
        guard !searchText.isEmpty else { return processes }
        return processes.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            ($0.bundleID?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !memoryAvailable {
                PermissionBanner()
            }

            List(filteredProcesses) { process in
                Button {
                    session.selectProcess(process)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(process.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("PID: \(process.pid)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .searchable(text: $searchText, prompt: "搜索进程名")
            .overlay {
                if isLoading {
                    ProgressView("加载进程列表...")
                } else if filteredProcesses.isEmpty {
                    ContentUnavailableView(
                        "没有进程",
                        systemImage: "cpu",
                        description: Text("未找到可扫描的进程")
                    )
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    reloadProcesses()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .onAppear {
            memoryAvailable = MemScanBridge.isMemoryAccessAvailable()
            reloadProcesses()
        }
    }

    private func reloadProcesses() {
        isLoading = true
        Task {
            let list = await Task.detached {
                ProcessService.shared.fetchProcesses()
            }.value
            processes = list
            isLoading = false
        }
    }
}

private struct PermissionBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(MemScanBridge.memoryAccessErrorMessage() ?? "无法访问进程内存")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
    }
}

#Preview {
    NavigationStack {
        ProcessListView(session: ScanSession())
    }
}
