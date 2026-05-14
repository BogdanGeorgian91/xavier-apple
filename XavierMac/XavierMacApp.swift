import SwiftUI

@main
struct XavierMacApp: App {
    @NSApplicationDelegateAdaptor(XavierMacAppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            SidebarContentView()
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 900, height: 600)
        MenuBarExtra("Xavier", systemImage: "shield") {
            MenuBarView()
        }
    }
}