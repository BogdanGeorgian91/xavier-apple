//
//  Rule.swift
//  Xavier
//
//

import Foundation

struct Rule {
    let ruleType:RuleType
    let isAllowed:Bool
    let date:Date
}

extension Rule {
    init(ruleType:RuleType, isAllowed:Bool) {
        self.init(ruleType: ruleType, isAllowed: isAllowed, date: Date())
    }
}

enum RuleType {
    case host(String)
    case app(AppName)
    case hostFromApp(host:String, app:AppName)
}


typealias AppName = String
extension AppName {    
    var commonName:String {
        return AppMetadataFetcher.shared.appName(for: self)
    }
}

class AppMetadataFetcher {
    static let shared = AppMetadataFetcher()
    
    private let userDefaults = UserDefaults(suiteName: Constants.appGroupIdentifier) ?? UserDefaults.standard
    private let cacheKey = "Xavier.AppMetadataCache"
    
    private let hardcodedApps: [String: String] = [
        "com.apple.mobilesafari": "Safari",
        "com.apple.Maps": "Maps",
        "com.apple.weather": "Weather",
        "com.apple.Notes": "Notes",
        "com.apple.Preferences": "Settings",
        "com.apple.camera": "Camera",
        "com.apple.Photos": "Photos",
        "com.apple.Music": "Music",
        "com.apple.MobileStore": "App Store",
        "com.apple.news": "News",
        "com.apple.stocks": "Stocks",
        "com.apple.calculator": "Calculator",
        "com.apple.VoiceMemos": "Voice Memos",
        "com.apple.podcasts": "Podcasts",
        "com.apple.Translate": "Translate",
        "com.apple.tv": "Apple TV",
        "com.apple.Fitness": "Fitness",
        "com.apple.Health": "Health",
        "com.apple.findmy": "Find My",
        "com.apple.shortcuts": "Shortcuts",
        "com.apple.Home": "Home",
        "com.apple.tips": "Tips",
        "com.apple.Books": "Books",
        "com.apple.Mail": "Mail",
        "com.apple.compass": "Compass",
        "com.apple.contacts": "Contacts",
        "com.apple.MobileSMS": "Messages",
        "com.apple.mobilephone": "Phone",
        "com.apple.mobilecal": "Calendar",
        "com.apple.mobiletimer": "Clock",
        "com.apple.reminders": "Reminders",
        "com.apple.facetime": "FaceTime",
        "com.apple.clock": "Clock",
        "com.apple.Wallet": "Wallet"
    ]
    
    private var inMemoryCache: [String: String] = [:]
    private var fetchingBundleIds: Set<String> = []
    
    init() {
        if let savedCache = userDefaults.dictionary(forKey: cacheKey) as? [String: String] {
            inMemoryCache = savedCache
        }
    }
    
    func appName(for bundleId: String) -> String {
        // 1. Check hardcoded Apple apps
        if let name = hardcodedApps[bundleId] {
            return name
        }
        
        // 2. Check local cache
        if let name = inMemoryCache[bundleId] {
            return name
        }
        
        // 3. Trigger async fetch from iTunes Search API if not fetched yet
        fetchFromITunes(bundleId: bundleId)
        
        // 4. Return fallback (last component) while fetching
        var fallbackParts = bundleId.components(separatedBy: ".")
        if fallbackParts.count > 1, ["ios", "app", "mobile"].contains(fallbackParts.last!.lowercased()) {
            fallbackParts.removeLast()
        }
        let fallback = fallbackParts.last ?? bundleId
        return fallback.capitalized
    }
    
    private func fetchFromITunes(bundleId: String) {
        guard !fetchingBundleIds.contains(bundleId) else { return }
        fetchingBundleIds.insert(bundleId)
        
        var fallbackParts = bundleId.components(separatedBy: ".")
        if fallbackParts.count > 1, ["ios", "app", "mobile"].contains(fallbackParts.last!.lowercased()) {
            fallbackParts.removeLast()
        }
        let fallback = fallbackParts.last ?? bundleId
        
        guard let url = URL(string: "https://itunes.apple.com/lookup?bundleId=\(bundleId)") else {
            fetchingBundleIds.remove(bundleId)
            return
        }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }
            
            defer {
                DispatchQueue.main.async {
                    self.fetchingBundleIds.remove(bundleId)
                }
            }
            
            guard let data = data, error == nil else { return }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let results = json["results"] as? [[String: Any]] {
                    
                    let trackName: String
                    if let firstResult = results.first, let name = firstResult["trackName"] as? String {
                        trackName = name
                    } else {
                        // Not found on iTunes (e.g. system app), cache the fallback so we don't query repeatedly
                        trackName = fallback.capitalized
                    }
                    
                    DispatchQueue.main.async {
                        self.inMemoryCache[bundleId] = trackName
                        self.userDefaults.set(self.inMemoryCache, forKey: self.cacheKey)
                        NotificationCenter.default.post(name: NSNotification.Name("AppMetadataUpdated"), object: nil)
                    }
                }
            } catch {
                print("Failed to parse iTunes lookup for \(bundleId): \(error)")
            }
        }.resume()
    }
}

struct Wildcard {
    let app:AppName
    let isAllowed:Bool
}

