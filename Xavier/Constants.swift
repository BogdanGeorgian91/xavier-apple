//
//  Constants.swift
//  Xavier
//
//

import Foundation

public struct Constants {
    public static let appGroupIdentifier = infoString(for: "XavierAppGroupIdentifier", fallback: "group.com.example.xavier")
    public static let proxyAppGroupIdentifier = appGroupIdentifier
    public static let proxyVPNDescription = "Xavier Inspector"
    public static let proxyPruningDays = 7
    public static let sharedKeychainAccessGroup = infoString(for: "XavierSharedKeychainAccessGroup", fallback: "com.example.xavier.shared")
    public static let appBundleIdentifier = infoString(for: "XavierBaseBundleIdentifier", fallback: "com.example.xavier")
    public static let appProxyUUID = infoString(for: "XavierAppProxyUUID", fallback: "AA113482-C47E-4326-9633-31C8D2BAE8A1")
    public static let notificationCategory = "network_request_category"
    public static let onboardingKey = "onboarding_key"
    public static let pushActivityKey = "push_activity_key"
    public static let notificationMuteKeyPrefix = "notification_mute_"

    public static let proxiedBrowserBundleIDs = [
        "com.apple.mobilesafari",
        "com.google.chrome.ios",
        "org.mozilla.ios.firefox",
        "com.microsoft.msedge",
        "com.brave.ios.browser",
        "com.duckduckgo.mobile.ios"
    ]

    public enum ProxyKeys {
        public static let scriptBlocklistKey = "xavier.scriptBlocklist"
        public static let scriptStrippingHostsKey = "xavier.scriptStrippingHosts"
        public static let modificationRulesKey = "xavier.modificationRules"
        public static let pinnedDomainsKey = "xavier.pinnedDomains"
        public static let proxyEnabledKey = "xavier.proxyEnabled"
        public static let mitmEnabledKey = "xavier.mitmEnabled"
        public static let showFallbackFlowsKey = "xavier.showFallbackFlows"
    }

    public enum NotificationAction:String {
        case edit = "network_request_edit_action"
        
        case allowThis = "network_request_allow_action"
        case allowHost = "network_request_allow_host_action"
        case allowApp = "network_request_allow_app_action"
        
        case denyThis = "network_request_deny_action"
        case denyHost = "network_request_deny_host_action"
        case denyApp = "network_request_deny_app_action"

        public var id:String { return self.rawValue }
    }
    
    public enum ObservableNotification {
        case appBecameActive
        case editAction
         
        public var nameString:String {
            switch self {
            case .appBecameActive:
                return "app_became_active"
            case .editAction:
                return "edit_action"
            }
        }
        
        public var name:NSNotification.Name {
            return NSNotification.Name(rawValue: nameString)
        }
    }
    
    public static let appURL:String = infoString(for: "XavierAppURL", fallback: "https://github.com/BogdanGeorgian91/xavier-apple")
    public static let promoText:String = "Xavier reveals what apps are really doing on your phone."
    
    public enum WebsiteEndpoints:String {
        case faq = "faq"
        case privacy = "privacy"
        case developer = "developer"
        
        public var url:String {
            return "\(Constants.appURL)/\(self.rawValue)"
        }
    }

}

private func infoString(for key: String, fallback: String) -> String {
    guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
          !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return fallback
    }
    return value
}

extension Constants {
    public static let platformConstants = PlatformConstants(
        appGroupIdentifier: appGroupIdentifier,
        keychainAccessGroup: sharedKeychainAccessGroup,
        bundleIdentifier: appBundleIdentifier,
        proxyAppGroupIdentifier: proxyAppGroupIdentifier
    )

    public static func notificationMuteKey(for app: String) -> String {
        return "\(notificationMuteKeyPrefix)\(app)"
    }

    public static func isNotificationMuted(for app: String) -> Bool {
        let key = notificationMuteKey(for: app)
        guard let defaults = UserDefaults.group, defaults.object(forKey: key) != nil else {
            return true
        }
        return defaults.bool(forKey: key)
    }

    public static func setNotificationMuted(_ muted: Bool, for app: String) {
        UserDefaults.group?.set(muted, forKey: notificationMuteKey(for: app))
    }

    public static var isAllActivityMode: Bool {
        return UserDefaults.group?.bool(forKey: pushActivityKey) ?? false
    }

    public static var isMITMEnabled: Bool {
        return UserDefaults.group?.bool(forKey: ProxyKeys.mitmEnabledKey) ?? false
    }

    public static func setMITMEnabled(_ enabled: Bool) {
        UserDefaults.group?.set(enabled, forKey: ProxyKeys.mitmEnabledKey)
    }

    public static var isShowFallbackFlowsEnabled: Bool {
        return UserDefaults.group?.bool(forKey: ProxyKeys.showFallbackFlowsKey) ?? false
    }

    public static func setShowFallbackFlowsEnabled(_ enabled: Bool) {
        UserDefaults.group?.set(enabled, forKey: ProxyKeys.showFallbackFlowsKey)
    }
}

extension UserDefaults {
    public static var  group:UserDefaults? {
        return UserDefaults(suiteName: Constants.appGroupIdentifier)
    }
}

public func dispatchAfter(delay:Double, task:@escaping ()->Void) {
    
    let delay = DispatchTime.now() + Double(Int64(delay * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
    
    DispatchQueue.main.asyncAfter(deadline: delay) {
        task()
    }
}
