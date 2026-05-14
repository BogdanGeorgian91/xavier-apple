import Foundation

private final class FrameworkBundleMarker {}

struct FrameworkBundleResolver: BundleResolver {
    let modelBundle: Bundle = Bundle(for: FrameworkBundleMarker.self)
    let appGroupIdentifier: String = Constants.appGroupIdentifier
    let keychainAccessGroup: String = Constants.sharedKeychainAccessGroup
    let bundleIdentifier: String = Constants.appBundleIdentifier
}
