import Foundation

public enum ModificationType: String, Codable {
    case addHeader
    case removeHeader
    case replaceHeader
    case rewriteURL
    case replaceBody
}

public struct ModificationRule: Codable {
    public let identifier: UUID
    public let host: String
    public let type: ModificationType
    public let matchPattern: String?
    public let replacementValue: String?
    public let enabled: Bool

    public init(identifier: UUID, host: String, type: ModificationType, matchPattern: String?, replacementValue: String?, enabled: Bool) {
        self.identifier = identifier
        self.host = host
        self.type = type
        self.matchPattern = matchPattern
        self.replacementValue = replacementValue
        self.enabled = enabled
    }
}

public final class ModificationRuleManager {
    public static let shared = ModificationRuleManager()

    private let defaults = UserDefaults(suiteName: Constants.appGroupIdentifier)
    private let rulesKey = Constants.ProxyKeys.modificationRulesKey

    private init() {}

    public func fetchEnabledRules() -> [ModificationRule] {
        return loadRules().filter { $0.enabled }
    }

    public func fetchAllRules() -> [ModificationRule] {
        return loadRules()
    }

    public func addRule(_ rule: ModificationRule) {
        var rules = loadRules()
        rules.append(rule)
        saveRules(rules)
    }

    public func removeRule(id: UUID) {
        var rules = loadRules()
        rules.removeAll { $0.identifier == id }
        saveRules(rules)
    }

    public func updateRule(id: UUID, enabled: Bool) {
        var rules = loadRules()
        if let index = rules.firstIndex(where: { $0.identifier == id }) {
            rules[index] = ModificationRule(
                identifier: rules[index].identifier,
                host: rules[index].host,
                type: rules[index].type,
                matchPattern: rules[index].matchPattern,
                replacementValue: rules[index].replacementValue,
                enabled: enabled
            )
            saveRules(rules)
        }
    }

    private func loadRules() -> [ModificationRule] {
        guard let data = defaults?.data(forKey: rulesKey) else { return [] }
        return (try? JSONDecoder().decode([ModificationRule].self, from: data)) ?? []
    }

    private func saveRules(_ rules: [ModificationRule]) {
        if let data = try? JSONEncoder().encode(rules) {
            defaults?.set(data, forKey: rulesKey)
        }
    }
}
