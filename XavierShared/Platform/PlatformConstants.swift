import Foundation

public struct PlatformConstants {
    public let appGroupIdentifier: String
    public let keychainAccessGroup: String
    public let bundleIdentifier: String
    public let proxyAppGroupIdentifier: String

    public init(appGroupIdentifier: String,
                keychainAccessGroup: String,
                bundleIdentifier: String,
                proxyAppGroupIdentifier: String) {
        self.appGroupIdentifier = appGroupIdentifier
        self.keychainAccessGroup = keychainAccessGroup
        self.bundleIdentifier = bundleIdentifier
        self.proxyAppGroupIdentifier = proxyAppGroupIdentifier
    }
}