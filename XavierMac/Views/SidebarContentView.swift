import SwiftUI

struct SidebarContentView: View {
    var body: some View {
        NavigationSplitView {
            SidebarListView()
        } detail: {
            Text("Select a section")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct SidebarListView: View {
    var body: some View {
        List(selection: .constant(nil)) {
            Section("Firewall") {
                Label("Dashboard", systemImage: "gauge")
                Label("Activity", systemImage: "chart.bar")
                Label("Firewall Rules", systemImage: "checkmark.shield")
            }
            Section("Inspector") {
                Label("Inspector", systemImage: "magnifyingglass")
                Label("Modification Rules", systemImage: "wand.and.stars")
                Label("Certificates", systemImage: "lock.shield")
            }
            Section("Proxy") {
                Label("Proxy Map", systemImage: "network")
            }
            Section("System") {
                Label("Settings", systemImage: "gear")
            }
        }
        .listStyle(.sidebar)
    }
}