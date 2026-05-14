import Foundation
import XavierShared

struct MacOSBundleResolver: BundleResolver {
    let modelBundle: Bundle
    let appGroupIdentifier: String
    let keychainAccessGroup: String
    let bundleIdentifier: String

    init() {
        let identifier = Bundle.main.bundleIdentifier ?? "com.example.xavier.mac"
        self.bundleIdentifier = identifier
        self.appGroupIdentifier = "group.\(identifier)"
        self.keychainAccessGroup = "\(identifier).shared"
        self.modelBundle = Bundle(for: MacOSBundleResolver.self)
    }
}
