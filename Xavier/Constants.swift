//
//  Constants.swift
//  Xavier
//
//

import Foundation

struct Constants {
    static let appGroupIdentifier = infoString(for: "XavierAppGroupIdentifier", fallback: "group.com.example.xavier")
    static let proxyAppGroupIdentifier = appGroupIdentifier
    static let proxyVPNDescription = "Xavier Inspector"
    static let proxyPruningDays = 7
    static let sharedKeychainAccessGroup = infoString(for: "XavierSharedKeychainAccessGroup", fallback: "com.example.xavier.shared")
    static let appBundleIdentifier = infoString(for: "XavierBaseBundleIdentifier", fallback: "com.example.xavier")
    static let appProxyUUID = infoString(for: "XavierAppProxyUUID", fallback: "AA113482-C47E-4326-9633-31C8D2BAE8A1")
    static let notificationCategory = "network_request_category"
    static let onboardingKey = "onboarding_key"
    static let pushActivityKey = "push_activity_key"
    static let notificationMuteKeyPrefix = "notification_mute_"

    static let proxiedBrowserBundleIDs = [
        "com.apple.mobilesafari",
        "com.google.chrome.ios",
        "org.mozilla.ios.firefox",
        "com.microsoft.msedge",
        "com.brave.ios.browser",
        "com.duckduckgo.mobile.ios"
    ]

    enum ProxyKeys {
        static let scriptBlocklistKey = "xavier.scriptBlocklist"
        static let scriptStrippingHostsKey = "xavier.scriptStrippingHosts"
        static let modificationRulesKey = "xavier.modificationRules"
        static let pinnedDomainsKey = "xavier.pinnedDomains"
        static let proxyEnabledKey = "xavier.proxyEnabled"
        static let mitmEnabledKey = "xavier.mitmEnabled"
        static let showFallbackFlowsKey = "xavier.showFallbackFlows"
    }

    enum NotificationAction:String {
        case edit = "network_request_edit_action"
        
        case allowThis = "network_request_allow_action"
        case allowHost = "network_request_allow_host_action"
        case allowApp = "network_request_allow_app_action"
        
        case denyThis = "network_request_deny_action"
        case denyHost = "network_request_deny_host_action"
        case denyApp = "network_request_deny_app_action"

        var id:String { return self.rawValue }
    }
    
    enum ObservableNotification {
        case appBecameActive
        case editAction
         
        var nameString:String {
            switch self {
            case .appBecameActive:
                return "app_became_active"
            case .editAction:
                return "edit_action"
            }
        }
        
        var name:NSNotification.Name {
            return NSNotification.Name(rawValue: nameString)
        }
    }
    
    static let appURL:String = infoString(for: "XavierAppURL", fallback: "https://github.com/BogdanGeorgian91/xavier-apple")
    static let promoText:String = "Xavier reveals what apps are really doing on your phone."
    
    enum WebsiteEndpoints:String {
        case faq = "faq"
        case privacy = "privacy"
        case developer = "developer"
        
        var url:String {
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
    static func notificationMuteKey(for app: String) -> String {
        return "\(notificationMuteKeyPrefix)\(app)"
    }

    static func isNotificationMuted(for app: String) -> Bool {
        let key = notificationMuteKey(for: app)
        guard let defaults = UserDefaults.group, defaults.object(forKey: key) != nil else {
            return true
        }
        return defaults.bool(forKey: key)
    }

    static func setNotificationMuted(_ muted: Bool, for app: String) {
        UserDefaults.group?.set(muted, forKey: notificationMuteKey(for: app))
    }

    static var isAllActivityMode: Bool {
        return UserDefaults.group?.bool(forKey: pushActivityKey) ?? false
    }

    static var isMITMEnabled: Bool {
        return UserDefaults.group?.bool(forKey: ProxyKeys.mitmEnabledKey) ?? false
    }

    static func setMITMEnabled(_ enabled: Bool) {
        UserDefaults.group?.set(enabled, forKey: ProxyKeys.mitmEnabledKey)
    }

    static var isShowFallbackFlowsEnabled: Bool {
        return UserDefaults.group?.bool(forKey: ProxyKeys.showFallbackFlowsKey) ?? false
    }

    static func setShowFallbackFlowsEnabled(_ enabled: Bool) {
        UserDefaults.group?.set(enabled, forKey: ProxyKeys.showFallbackFlowsKey)
    }
}

extension UserDefaults {
    static var  group:UserDefaults? {
        return UserDefaults(suiteName: Constants.appGroupIdentifier)
    }
}

func dispatchAfter(delay:Double, task:@escaping ()->Void) {
    
    let delay = DispatchTime.now() + Double(Int64(delay * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
    
    DispatchQueue.main.asyncAfter(deadline: delay) {
        task()
    }
}
