import Foundation

public protocol BundleResolver {
    var modelBundle: Bundle { get }
    var appGroupIdentifier: String { get }
    var keychainAccessGroup: String { get }
    var bundleIdentifier: String { get }
}