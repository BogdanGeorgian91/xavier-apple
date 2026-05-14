import AppKit
import SwiftUI

final class XavierMacAppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    private let filterXPCClient = FilterXPCClient()

    func applicationDidFinishLaunching(_ notification: Notification) {
        filterXPCClient.connect()
    }
}
