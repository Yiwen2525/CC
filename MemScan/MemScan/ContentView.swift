import SwiftUI

struct ContentView: View {
    @StateObject private var session = ScanSession()

    var body: some View {
        NavigationStack {
            Group {
                if session.selectedProcess == nil {
                    ProcessListView(session: session)
                } else {
                    ScanWorkspaceView(session: session)
                }
            }
            .navigationTitle("MemScan")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    ContentView()
}
