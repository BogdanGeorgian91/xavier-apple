import Foundation

struct BlocklistMatcher {
    static func isBlocked(hostname: String, patterns: [String]) -> Bool {
        for pattern in patterns {
            if matchesPattern(hostname: hostname, pattern: pattern) {
                return true
            }
        }
        return false
    }

    static func loadEnabledPatterns() -> [String] {
        return ScriptBlocklistManager.shared.fetchEnabledPatterns()
    }

    static func loadStripEnabledHosts() -> Set<String> {
        return ScriptBlocklistManager.shared.fetchStripEnabledHosts()
    }

    private static func matchesPattern(hostname: String, pattern: String) -> Bool {
        if hostname == pattern {
            return true
        }

        if pattern.hasPrefix("*.") {
            let domain = String(pattern.dropFirst(2))
            return hostname == domain || hostname.hasSuffix("." + domain)
        }

        if hostname.hasSuffix("." + pattern) {
            return true
        }

        return false
    }
}
