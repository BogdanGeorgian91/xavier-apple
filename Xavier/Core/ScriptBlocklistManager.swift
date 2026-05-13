import Foundation

struct BlocklistEntry: Codable {
    let identifier: String
    let domainPattern: String
    let enabled: Bool
    let isPreset: Bool
    let isStripEnabled: Bool
    let createdAt: Date
    let updatedAt: Date
}

enum ScriptStrippingMode: String, Codable {
    case smartAllowlist
    case fineGrained

    var title: String {
        switch self {
        case .smartAllowlist: return "Smart Allowlist"
        case .fineGrained: return "Fine-Grained Rules"
        }
    }
}

enum ScriptRuleAction: String, Codable {
    case keep
    case remove

    var title: String {
        switch self {
        case .keep: return "Keep"
        case .remove: return "Remove"
        }
    }
}

enum ScriptRuleMatchType: String, Codable {
    case srcContains
    case srcHostMatches
    case inlineContains

    var title: String {
        switch self {
        case .srcContains: return "Script src contains"
        case .srcHostMatches: return "Script src host matches"
        case .inlineContains: return "Inline script contains"
        }
    }
}

struct ScriptRule: Codable {
    let identifier: String
    let action: ScriptRuleAction
    let matchType: ScriptRuleMatchType
    let pattern: String
    let enabled: Bool
    let createdAt: Date
    let updatedAt: Date
}

struct ScriptStrippingHost: Codable {
    let host: String
    let enabled: Bool
    let mode: ScriptStrippingMode
    let rules: [ScriptRule]
    let createdAt: Date
    let updatedAt: Date
}

final class ScriptStrippingManager {
    static let shared = ScriptStrippingManager()

    private let defaults = UserDefaults(suiteName: Constants.appGroupIdentifier)
    private let hostsKey = Constants.ProxyKeys.scriptStrippingHostsKey

    private init() {}

    func fetchAllHosts() -> [ScriptStrippingHost] {
        return migratedHosts()
    }

    func fetchEnabledHosts() -> [ScriptStrippingHost] {
        return migratedHosts().filter(\.enabled)
    }

    func hostConfiguration(for host: String) -> ScriptStrippingHost? {
        let normalized = normalize(host)
        let hosts = migratedHosts().filter(\.enabled)

        if let exact = hosts.first(where: { normalize($0.host) == normalized }) {
            return exact
        }

        return hosts.first { config in
            hostMatchesWildcard(hostname: normalized, pattern: normalize(config.host))
        }
    }

    private func hostMatchesWildcard(hostname: String, pattern: String) -> Bool {
        if pattern.hasPrefix("*.") {
            let domain = String(pattern.dropFirst(2))
            return hostname == domain || hostname.hasSuffix(".\(domain)")
        }
        if pattern.hasPrefix("*") {
            let domain = String(pattern.dropFirst(1))
            return hostname == domain || hostname.hasSuffix(".\(domain)")
        }
        return false
    }

    func upsertHost(_ host: String, enabled: Bool = true, mode: ScriptStrippingMode = .smartAllowlist) {
        let normalized = normalize(host)
        guard !normalized.isEmpty else { return }

        var hosts = migratedHosts()
        let now = Date()
        if let index = hosts.firstIndex(where: { normalize($0.host) == normalized }) {
            let current = hosts[index]
            hosts[index] = ScriptStrippingHost(host: current.host,
                                               enabled: enabled,
                                               mode: current.mode,
                                               rules: current.rules,
                                               createdAt: current.createdAt,
                                               updatedAt: now)
        } else {
            hosts.append(ScriptStrippingHost(host: normalized,
                                             enabled: enabled,
                                             mode: mode,
                                             rules: [],
                                             createdAt: now,
                                             updatedAt: now))
        }
        saveHosts(hosts)
    }

    func setEnabled(_ enabled: Bool, forHost host: String) {
        updateHost(host) { current in
            ScriptStrippingHost(host: current.host,
                                enabled: enabled,
                                mode: current.mode,
                                rules: current.rules,
                                createdAt: current.createdAt,
                                updatedAt: Date())
        }
    }

    func setMode(_ mode: ScriptStrippingMode, forHost host: String) {
        updateHost(host) { current in
            ScriptStrippingHost(host: current.host,
                                enabled: current.enabled,
                                mode: mode,
                                rules: current.rules,
                                createdAt: current.createdAt,
                                updatedAt: Date())
        }
    }

    func addRule(_ rule: ScriptRule, toHost host: String) {
        updateHost(host) { current in
            var rules = current.rules
            rules.append(rule)
            return ScriptStrippingHost(host: current.host,
                                       enabled: current.enabled,
                                       mode: current.mode,
                                       rules: rules,
                                       createdAt: current.createdAt,
                                       updatedAt: Date())
        }
    }

    func removeRule(identifier: String, fromHost host: String) {
        updateHost(host) { current in
            ScriptStrippingHost(host: current.host,
                                enabled: current.enabled,
                                mode: current.mode,
                                rules: current.rules.filter { $0.identifier != identifier },
                                createdAt: current.createdAt,
                                updatedAt: Date())
        }
    }

    func setRuleEnabled(_ enabled: Bool, identifier: String, forHost host: String) {
        updateHost(host) { current in
            let rules = current.rules.map { rule in
                guard rule.identifier == identifier else { return rule }
                return ScriptRule(identifier: rule.identifier,
                                  action: rule.action,
                                  matchType: rule.matchType,
                                  pattern: rule.pattern,
                                  enabled: enabled,
                                  createdAt: rule.createdAt,
                                  updatedAt: Date())
            }
            return ScriptStrippingHost(host: current.host,
                                       enabled: current.enabled,
                                       mode: current.mode,
                                       rules: rules,
                                       createdAt: current.createdAt,
                                       updatedAt: Date())
        }
    }

    private func updateHost(_ host: String, transform: (ScriptStrippingHost) -> ScriptStrippingHost) {
        let normalized = normalize(host)
        var hosts = migratedHosts()
        guard let index = hosts.firstIndex(where: { normalize($0.host) == normalized }) else { return }
        hosts[index] = transform(hosts[index])
        saveHosts(hosts)
    }

    private func migratedHosts() -> [ScriptStrippingHost] {
        let stored = loadHosts()
        let existingHosts = Set(stored.map { normalize($0.host) })
        let legacyHosts = ScriptBlocklistManager.shared.fetchAllEntries()
            .filter(\.isStripEnabled)
            .map { normalize($0.domainPattern) }
            .filter { !$0.isEmpty && !existingHosts.contains($0) }

        guard !legacyHosts.isEmpty else { return stored }

        let now = Date()
        let migrated = stored + legacyHosts.map {
            ScriptStrippingHost(host: $0,
                                enabled: true,
                                mode: .smartAllowlist,
                                rules: [],
                                createdAt: now,
                                updatedAt: now)
        }
        saveHosts(migrated)
        return migrated
    }

    private func loadHosts() -> [ScriptStrippingHost] {
        guard let data = defaults?.data(forKey: hostsKey) else { return [] }
        return (try? JSONDecoder().decode([ScriptStrippingHost].self, from: data)) ?? []
    }

    private func saveHosts(_ hosts: [ScriptStrippingHost]) {
        let sorted = hosts.sorted { $0.host.localizedCaseInsensitiveCompare($1.host) == .orderedAscending }
        if let data = try? JSONEncoder().encode(sorted) {
            defaults?.set(data, forKey: hostsKey)
        }
    }

    private func normalize(_ host: String) -> String {
        return host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

final class ScriptBlocklistManager {
    static let shared = ScriptBlocklistManager()

    private let defaults = UserDefaults(suiteName: Constants.appGroupIdentifier)
    private let blocklistKey = Constants.ProxyKeys.scriptBlocklistKey
    private let presetDomains = [
        "*.doubleclick.net",
        "*.googleadservices.com",
        "*.googlesyndication.com",
        "*.googletagmanager.com",
        "*.analytics.facebook.com",
        "*.analytics.google.com"
    ]

    private init() {}

    func fetchEnabledPatterns() -> [String] {
        return loadEntries().filter { $0.enabled }.map { $0.domainPattern }
    }

    func fetchStripEnabledHosts() -> Set<String> {
        return Set(ScriptStrippingManager.shared.fetchEnabledHosts().map(\.host))
    }

    func fetchAllEntries() -> [BlocklistEntry] {
        return loadEntries()
    }

    func addEntry(_ entry: BlocklistEntry) {
        var entries = loadEntries()
        entries.append(entry)
        saveEntries(entries)
    }

    func removeEntry(identifier: String) {
        var entries = loadEntries()
        entries.removeAll { $0.identifier == identifier }
        saveEntries(entries)
    }

    func updateEntry(identifier: String, enabled: Bool) {
        var entries = loadEntries()
        if let index = entries.index(where: { $0.identifier == identifier }) {
            let current = entries[index]
            entries[index] = BlocklistEntry(identifier: current.identifier,
                                            domainPattern: current.domainPattern,
                                            enabled: enabled,
                                            isPreset: current.isPreset,
                                            isStripEnabled: current.isStripEnabled,
                                            createdAt: current.createdAt,
                                            updatedAt: Date())
            saveEntries(entries)
        }
    }

    func setStripEnabled(_ stripEnabled: Bool, forHost host: String) {
        var entries = loadEntries()
        if let index = entries.index(where: { $0.domainPattern == host }) {
            let current = entries[index]
            entries[index] = BlocklistEntry(identifier: current.identifier,
                                            domainPattern: current.domainPattern,
                                            enabled: current.enabled,
                                            isPreset: current.isPreset,
                                            isStripEnabled: stripEnabled,
                                            createdAt: current.createdAt,
                                            updatedAt: Date())
            saveEntries(entries)
            return
        }

        let now = Date()
        entries.append(BlocklistEntry(identifier: UUID().uuidString,
                                      domainPattern: host,
                                      enabled: true,
                                      isPreset: false,
                                      isStripEnabled: stripEnabled,
                                      createdAt: now,
                                      updatedAt: now))
        saveEntries(entries)
    }

    private func loadEntries() -> [BlocklistEntry] {
        guard let data = defaults?.data(forKey: blocklistKey) else {
            let entries = defaultEntries()
            saveEntries(entries)
            return entries
        }

        let decoded = (try? JSONDecoder().decode([BlocklistEntry].self, from: data)) ?? defaultEntries()
        return mergeMissingPresets(into: decoded)
    }

    private func mergeMissingPresets(into entries: [BlocklistEntry]) -> [BlocklistEntry] {
        let existingPatterns = Set(entries.map(\.domainPattern))
        let missingPresets = defaultEntries().filter { !existingPatterns.contains($0.domainPattern) }
        guard !missingPresets.isEmpty else { return entries }

        let merged = entries + missingPresets
        saveEntries(merged)
        return merged
    }

    private func saveEntries(_ entries: [BlocklistEntry]) {
        if let data = try? JSONEncoder().encode(entries) {
            defaults?.set(data, forKey: blocklistKey)
        }
    }

    private func defaultEntries() -> [BlocklistEntry] {
        let now = Date()
        return presetDomains.map { domain in
            BlocklistEntry(identifier: "preset:\(domain)",
                           domainPattern: domain,
                           enabled: false,
                           isPreset: true,
                           isStripEnabled: false,
                           createdAt: now,
                           updatedAt: now)
        }
    }
}
