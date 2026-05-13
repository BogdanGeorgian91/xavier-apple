//
//  AppDelegate.swift
//  Xavier
//
//

import UIKit
import CoreData
import UserNotifications

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    var window: UIWindow?


    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.backgroundColor = AppColors.surface.color
        window?.rootViewController = MainTabBarController()
        window?.makeKeyAndVisible()
        
        UNUserNotificationCenter.current().delegate = self
        
        DispatchQueue.main.async {
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                if settings.authorizationStatus == .authorized {
                    UNUserNotificationCenter.current().setNotificationCategories([Notifications.authorizeCategory])
                }
            }
        }

        ProxyManager.shared.loadConfiguration { _ in }

        return true
    }
    
    func registerForNotifications(completion:@escaping ((Bool, Error?)->())) {
        DispatchQueue.main.async {
            UNUserNotificationCenter.current().setNotificationCategories([Notifications.authorizeCategory])
            UNUserNotificationCenter.current().requestAuthorization(options: [.badge, .sound, .alert], completionHandler: { (success, error) in
                if let err = error {
                    print("got error requesting push notifications: \(err)")
                    DispatchQueue.main.async {
                        completion(false, err)
                    }
                    return
                }
                
                print("registered for push: \(success)")
                DispatchQueue.main.async {
                    completion(success, nil)
                }
            })
        }
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
        do {
            try NetworkEventManager.shared.pruneOldData(days: 7)
            try BrowserEventManager.shared.pruneOldData(days: 7)
            try InspectionManager.shared.pruneOldData(days: Constants.proxyPruningDays)
        } catch {
            print("failed pruning old data: \(error)")
        }
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
        
        NotificationCenter.default.post(name: Constants.ObservableNotification.appBecameActive.name, object: nil)
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate.
    }
}
