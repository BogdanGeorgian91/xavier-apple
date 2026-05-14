import Foundation
import NetworkExtension

@main
struct FilterExtensionMain {
    static func main() {
        FilterXPCListener.shared.start()
        NEProvider.startSystemExtensionMode()
    }
}
