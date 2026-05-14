//
//  FilterControlProvider.swift
//  XavierControl
//
//

import NetworkExtension
import UserNotifications
import XavierShared

class FilterControlProvider: NEFilterControlProvider {
    let mutex = Mutex()
    private var lastNotificationTime: [String: Date] = [:]
    private let notificationThrottleInterval: TimeInterval = 2.0
    
    override func startFilter(completionHandler: @escaping (Error?) -> Void) {
        let editAction = UNNotificationAction(identifier: Constants.NotificationAction.edit.rawValue, title: "Edit rules", options: .foreground)
        let denyAction = UNNotificationAction(identifier: Constants.NotificationAction.denyApp.rawValue, title: "Drop all for this app", options: .destructive)
        let category = UNNotificationCategory(identifier: Constants.notificationCategory, actions: [editAction, denyAction], intentIdentifiers: [], hiddenPreviewsBodyPlaceholder: "Incoming network request", options: .customDismissAction)
        UNUserNotificationCenter.current().setNotificationCategories([category])
        completionHandler(nil)
    }
    
    override func stopFilter(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        completionHandler()
    }
    
    override func handleNewFlow(_ flow: NEFilterFlow, completionHandler: @escaping (NEFilterControlVerdict) -> Void) {
        guard let rawApp = flow.sourceAppIdentifier
        else {
            completionHandler(.allow(withUpdateRules: false))
            return
        }
        
        let app = rawApp.cleanAppIdentifier()
        
        guard let host = flow.getHost() else {
            completionHandler(.allow(withUpdateRules: false))
            return
        }
        
        let shouldNotifyAllActivity = !Constants.isNotificationMuted(for: app) && Constants.isAllActivityMode
        
        do {
            _ = try NetworkEventManager.shared.logFlowMetadata(from: flow)

            guard let rule = try RuleManager.shared.getRule(for: app, hostname: host) else {
                if !Constants.isNotificationMuted(for: app) {
                    fireNotification(app: app, hostname: host)
                }
                try RuleManager.shared.create(rule: Rule(ruleType: RuleType.hostFromApp(host: host, app: app), isAllowed: true))
                completionHandler(.allow(withUpdateRules: true))
                return
            }
            
            if shouldNotifyAllActivity {
                fireNotification(app: app, hostname: host)
            }
            
            let verdict:NEFilterControlVerdict = rule.isAllowed ? .allow(withUpdateRules: false) : .drop(withUpdateRules: false)
            completionHandler(verdict)
            
        } catch {
            RuleManager.recreateShared()
            do {
                _ = try NetworkEventManager.shared.logFlowMetadata(from: flow)

                guard let rule = try RuleManager.shared.getRule(for: app, hostname: host) else {
                    if !Constants.isNotificationMuted(for: app) {
                        fireNotification(app: app, hostname: host)
                    }
                    try RuleManager.shared.create(rule: Rule(ruleType: RuleType.hostFromApp(host: host, app: app), isAllowed: true))
                    completionHandler(.allow(withUpdateRules: true))
                    return
                }
                
                if shouldNotifyAllActivity {
                    fireNotification(app: app, hostname: host)
                }
                
                let verdict:NEFilterControlVerdict = rule.isAllowed ? .allow(withUpdateRules: false) : .drop(withUpdateRules: false)
                completionHandler(verdict)
            } catch {
                fireErrorNotification(error: "\(error)")
                completionHandler(.allow(withUpdateRules: false))
            }
        }
    }

    override func handle(_ report: NEFilterReport) {
        do {
            try NetworkEventManager.shared.updateBytes(from: report)
            if let flow = report.flow {
                _ = try BrowserEventManager.shared.logFlowMetadata(from: flow)
            }
        } catch {
            fireErrorNotification(error: "\(error)")
        }
    }
    
    func fireNotification(app:String, hostname:String) {
        let now = Date()
        if let lastTime = lastNotificationTime[app], now.timeIntervalSince(lastTime) < notificationThrottleInterval {
            return
        }
        lastNotificationTime[app] = now
        
        let content = UNMutableNotificationContent()
        content.categoryIdentifier = Constants.notificationCategory
        content.userInfo = ["app": app, "host": hostname]
        content.title = app.commonName.capitalized
        content.body = "Connected to \(hostname)"
        content.threadIdentifier = app
        content.sound = .default
        
        let id = UUID().uuidString
        
        let note = UNNotificationRequest(identifier: id,
                                         content: content,
                                         trigger: nil)
        
        UNUserNotificationCenter.current().add(note) { (err) in
            if let err = err {
                print("notification error: \(err)")
            }
        }
    }
    
    func fireErrorNotification(error:String) {
        let content = UNMutableNotificationContent()
        content.title = "Error Showing Request"
        content.body = error
    
        let note = UNNotificationRequest(identifier: "xavier_error_\(Date().timeIntervalSinceNow)",
                                         content: content,
                                         trigger: nil)
        
        UNUserNotificationCenter.current().add(note) { (err) in
            if err != nil {
                print("err: \(err!)")
            }
        }
    }
}
