import Foundation

private final class FrameworkBundleMarker {}

public struct FrameworkBundleResolver: BundleResolver {
    public let modelBundle: Bundle = Bundle(for: FrameworkBundleMarker.self)
    public let appGroupIdentifier: String = Constants.appGroupIdentifier
    public let keychainAccessGroup: String = Constants.sharedKeychainAccessGroup
    public let bundleIdentifier: String = Constants.appBundleIdentifier

    public init() {}
}
