import SwiftUI

struct ScanWorkspaceView: View {
    @ObservedObject var session: ScanSession
    @State private var selectedResult: ScanResult?
    @State private var showModifySheet = false

    var body: some View {
        VStack(spacing: 0) {
            ProcessHeaderView(session: session)

            ScanControlPanel(session: session)

            Divider()

            ResultsListView(
                session: session,
                onSelect: { result in
                    selectedResult = result
                    showModifySheet = true
                }
            )
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("换进程") {
                    ProcessService.shared.detach()
                    session.selectedProcess = nil
                    session.resetResults()
                }
            }
        }
        .sheet(isPresented: $showModifySheet) {
            if let result = selectedResult {
                ModifyValueSheet(
                    session: session,
                    result: result,
                    isPresented: $showModifySheet
                )
            }
        }
        .alert("提示", isPresented: Binding(
            get: { session.errorMessage != nil },
            set: { if !$0 { session.errorMessage = nil } }
        )) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(session.errorMessage ?? "")
        }
    }
}

private struct ProcessHeaderView: View {
    @ObservedObject var session: ScanSession

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.selectedProcess?.name ?? "未知进程")
                    .font(.headline)
                if let pid = session.selectedProcess?.pid {
                    Text("PID \(pid)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(session.resultCountText)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.blue)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
    }
}

private struct ScanControlPanel: View {
    @ObservedObject var session: ScanSession

    var body: some View {
        Form {
            Section("数据类型") {
                Picker("类型", selection: $session.dataType) {
                    ForEach(DataType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("搜索范围") {
                Picker("范围", selection: $session.searchScope) {
                    ForEach(SearchScope.allCases) { scope in
                        Text(scope.rawValue).tag(scope)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("首次搜索") {
                HStack {
                    TextField("输入数值", text: $session.searchValue)
                        .keyboardType(session.dataType.isFloatingPoint ? .decimalPad : .numberPad)
                    Button("搜索") {
                        Task { await session.firstScan() }
                    }
                    .disabled(session.isScanning || session.searchValue.isEmpty)
                }
            }

            Section("进一步搜索") {
                Picker("模式", selection: $session.refineMode) {
                    ForEach(RefineMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)

                if session.refineMode == .exact {
                    HStack {
                        TextField("新数值", text: $session.refineValue)
                            .keyboardType(session.dataType.isFloatingPoint ? .decimalPad : .numberPad)
                        Button("精搜") {
                            Task { await session.refineScan() }
                        }
                        .disabled(session.isScanning || !session.hasScanned)
                    }
                } else {
                    Button("精搜 (\(session.refineMode.rawValue))") {
                        Task { await session.refineScan() }
                    }
                    .disabled(session.isScanning || !session.hasScanned)
                }
            }

            if session.isScanning {
                HStack {
                    ProgressView()
                    Text("扫描中...")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxHeight: 380)
    }
}

private struct ResultsListView: View {
    @ObservedObject var session: ScanSession
    let onSelect: (ScanResult) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("搜索结果")
                    .font(.headline)
                Spacer()
                if session.hasScanned {
                    Button("清空") {
                        session.resetResults()
                    }
                    .font(.subheadline)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            if session.results.isEmpty {
                ContentUnavailableView(
                    session.hasScanned ? "无匹配地址" : "尚未搜索",
                    systemImage: "magnifyingglass",
                    description: Text(session.hasScanned ? "尝试更换数值或搜索范围" : "输入数值后开始首次搜索")
                )
            } else {
                List(session.results) { result in
                    Button {
                        onSelect(result)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.addressHex)
                                    .font(.subheadline.monospaced())
                                Text("值: \(session.dataType.formatValue(result.value))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "pencil.circle")
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .listStyle(.plain)

                if MemScanBridge.storedResultCount() > session.results.count {
                    Text("仅显示前 \(session.results.count) 条，共 \(MemScanBridge.storedResultCount()) 条")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        ScanWorkspaceView(session: {
            let s = ScanSession()
            s.selectedProcess = ProcessInfo(pid: 1234, name: "DemoApp", bundleID: nil)
            return s
        }())
    }
}
