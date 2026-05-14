import SwiftUI

struct MenuBarView: View {
    var body: some View {
        VStack {
            Text("Xavier")
                .font(.headline)
            Divider()
            Button("Open Xavier") {
                NSApp.activate(ignoringOtherApps: true)
                for window in NSApp.windows where window.isVisible {
                    window.makeKeyAndOrderFront(nil)
                }
            }
            Divider()
            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
    }
}