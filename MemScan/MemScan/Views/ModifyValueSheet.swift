import SwiftUI

struct ModifyValueSheet: View {
    @ObservedObject var session: ScanSession
    let result: ScanResult
    @Binding var isPresented: Bool

    @State private var newValueText: String
    @State private var errorMessage: String?
    @State private var didModify = false

    init(session: ScanSession, result: ScanResult, isPresented: Binding<Bool>) {
        self.session = session
        self.result = result
        self._isPresented = isPresented
        self._newValueText = State(initialValue: session.dataType.formatValue(result.value))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("地址") {
                    LabeledContent("内存地址", value: result.addressHex)
                }

                Section("当前值") {
                    LabeledContent("数值", value: session.dataType.formatValue(result.value))
                    LabeledContent("类型", value: session.dataType.rawValue)
                }

                Section("修改为") {
                    TextField("新数值", text: $newValueText)
                        .keyboardType(session.dataType.isFloatingPoint ? .decimalPad : .numberPad)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("修改内存")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("写入") {
                        applyModification()
                    }
                    .disabled(newValueText.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func applyModification() {
        do {
            try session.modifyResult(result, newValueText: newValueText)
            didModify = true
            isPresented = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    ModifyValueSheet(
        session: ScanSession(),
        result: ScanResult(address: 0x100203040, value: 999),
        isPresented: .constant(true)
    )
}
