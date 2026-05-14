import Foundation

struct IOSBundleResolver: BundleResolver {
    let modelBundle: Bundle = Bundle(for: RuleManager.self)
    let appGroupIdentifier: String = Constants.appGroupIdentifier
    let keychainAccessGroup: String = Constants.sharedKeychainAccessGroup
    let bundleIdentifier: String = Constants.appBundleIdentifier
}
