import Foundation

enum ModificationType: String, Codable {
    case addHeader
    case removeHeader
    case replaceHeader
    case rewriteURL
    case replaceBody
}

struct ModificationRule: Codable {
    let identifier: UUID
    let host: String
    let type: ModificationType
    let matchPattern: String?
    let replacementValue: String?
    let enabled: Bool
}

final class ModificationRuleManager {
    static let shared = ModificationRuleManager()

    private let defaults = UserDefaults(suiteName: Constants.appGroupIdentifier)
    private let rulesKey = Constants.ProxyKeys.modificationRulesKey

    private init() {}

    func fetchEnabledRules() -> [ModificationRule] {
        return loadRules().filter { $0.enabled }
    }

    func fetchAllRules() -> [ModificationRule] {
        return loadRules()
    }

    func addRule(_ rule: ModificationRule) {
        var rules = loadRules()
        rules.append(rule)
        saveRules(rules)
    }

    func removeRule(id: UUID) {
        var rules = loadRules()
        rules.removeAll { $0.identifier == id }
        saveRules(rules)
    }

    func updateRule(id: UUID, enabled: Bool) {
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