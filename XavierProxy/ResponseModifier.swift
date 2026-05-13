import Foundation

struct ModificationResult {
    let modifiedBody: Data?
    let modifiedHeaders: [String: String]?
    let wasModified: Bool
    let strippedScriptCount: Int
}

final class ResponseModifier {
    static let maxModifiableBodySize = 256 * 1024

    static func modifyResponse(body: Data,
                               headers: [String: String],
                               host: String,
                               blockedDomains: Set<String>,
                               stripConfiguration: ScriptStrippingHost?) -> ModificationResult? {
        guard let stripConfiguration = stripConfiguration, stripConfiguration.enabled else { return nil }

        guard let contentType = headers["Content-Type"]?.lowercased() ?? headers["content-type"]?.lowercased(),
              contentType.contains("text/html") else {
            return nil
        }

        guard body.count < maxModifiableBodySize else { return nil }

        let contentEncoding = (headers["Content-Encoding"] ?? headers["content-encoding"])?.lowercased()
        var workingBody = body
        var wasCompressed = false

        if let encoding = contentEncoding {
            switch encoding {
            case "gzip":
                guard let decompressed = try? body.gunzipped() else { return nil }
                workingBody = decompressed
                wasCompressed = true
            case "deflate":
                guard let decompressed = try? body.inflated() else { return nil }
                workingBody = decompressed
                wasCompressed = true
            case "br":
                return nil
            default:
                break
            }
        }

        guard let htmlString = String(data: workingBody, encoding: .utf8) else { return nil }

        let (strippedHTML, strippedCount) = stripScriptTags(from: htmlString,
                                                           blockedDomains: blockedDomains,
                                                           configuration: stripConfiguration)
        guard strippedCount > 0 else { return nil }

        var modifiedHeaders = headers
        if wasCompressed {
            modifiedHeaders.removeValue(forKey: "Content-Encoding")
            modifiedHeaders.removeValue(forKey: "content-encoding")
        }
        modifiedHeaders["Content-Length"] = "\(strippedHTML.utf8.count)"

        let isChunked = (headers["Transfer-Encoding"] ?? headers["transfer-encoding"])?.lowercased().contains("chunked") ?? false
        if isChunked {
            modifiedHeaders.removeValue(forKey: "Transfer-Encoding")
            modifiedHeaders.removeValue(forKey: "transfer-encoding")
            modifiedHeaders["Content-Length"] = "\(strippedHTML.utf8.count)"
        }

        guard let finalBody = strippedHTML.data(using: .utf8) else { return nil }

        return ModificationResult(
            modifiedBody: finalBody,
            modifiedHeaders: modifiedHeaders,
            wasModified: true,
            strippedScriptCount: strippedCount
        )
    }

    static func canModify(responseHeaders: [String: String], bodySize: Int) -> Bool {
        guard bodySize < maxModifiableBodySize else { return false }
        let contentType = (responseHeaders["Content-Type"] ?? responseHeaders["content-type"])?.lowercased() ?? ""
        return contentType.contains("text/html")
    }

    private static func stripScriptTags(from html: String,
                                        blockedDomains: Set<String>,
                                        configuration: ScriptStrippingHost) -> (String, Int) {
        var result = html
        var count = 0

        let scriptPattern = try? NSRegularExpression(
            pattern: "<script[^>]*\\ssrc=[\"']([^\"']+)[\"'][^>]*>[\\s\\S]*?</script>",
            options: [.caseInsensitive]
        )

        if let pattern = scriptPattern {
            let nsResult = NSMutableString(string: result)
            let fullRange = NSRange(location: 0, length: nsResult.length)
            let matches = pattern.matches(in: result, options: [], range: fullRange)

            for match in matches.reversed() {
                guard match.numberOfRanges > 1 else { continue }
                let srcRange = match.range(at: 1)
                guard srcRange.location != NSNotFound else { continue }
                let srcValue = (nsResult as NSString).substring(with: srcRange)

                if shouldRemoveExternalScript(src: srcValue, blockedDomains: blockedDomains, configuration: configuration) {
                    nsResult.replaceCharacters(in: match.range, with: "")
                    count += 1
                }
            }
            result = nsResult as String
        }

        let inlinePattern = try? NSRegularExpression(
            pattern: "<script[^>]*>[\\s\\S]*?</script>",
            options: [.caseInsensitive]
        )

        if let pattern = inlinePattern {
            let nsResult = NSMutableString(string: result)
            let fullRange = NSRange(location: 0, length: nsResult.length)
            let matches = pattern.matches(in: result, options: [], range: fullRange)

            for match in matches.reversed() {
                let matchString = (nsResult as NSString).substring(with: match.range)
                if shouldRemoveInlineScript(matchString, blockedDomains: blockedDomains, configuration: configuration) {
                    nsResult.replaceCharacters(in: match.range, with: "")
                    count += 1
                }
            }
            result = nsResult as String
        }

        let noscriptPattern = try? NSRegularExpression(
            pattern: "<noscript[^>]*>[\\s\\S]*?</noscript>",
            options: [.caseInsensitive]
        )

        if let pattern = noscriptPattern {
            let nsResult = NSMutableString(string: result)
            let fullRange = NSRange(location: 0, length: nsResult.length)
            let matches = pattern.matches(in: result, options: [], range: fullRange)

            for match in matches.reversed() {
                let matchString = (nsResult as NSString).substring(with: match.range)
                if shouldRemoveInlineScript(matchString, blockedDomains: blockedDomains, configuration: configuration) {
                    nsResult.replaceCharacters(in: match.range, with: "")
                    count += 1
                }
            }
            result = nsResult as String
        }

        return (result, count)
    }

    private static func shouldRemoveExternalScript(src: String,
                                                   blockedDomains: Set<String>,
                                                   configuration: ScriptStrippingHost) -> Bool {
        if matchesRule(action: .keep, src: src, inlineScript: nil, rules: configuration.rules) {
            return false
        }

        switch configuration.mode {
        case .smartAllowlist:
            return shouldBlock(src: src, blockedDomains: blockedDomains)
        case .fineGrained:
            return matchesRule(action: .remove, src: src, inlineScript: nil, rules: configuration.rules)
        }
    }

    private static func shouldRemoveInlineScript(_ script: String,
                                                 blockedDomains: Set<String>,
                                                 configuration: ScriptStrippingHost) -> Bool {
        if matchesRule(action: .keep, src: nil, inlineScript: script, rules: configuration.rules) {
            return false
        }

        switch configuration.mode {
        case .smartAllowlist:
            return containsBlockedDomain(text: script, blockedDomains: blockedDomains)
        case .fineGrained:
            return matchesRule(action: .remove, src: nil, inlineScript: script, rules: configuration.rules)
        }
    }

    private static func shouldBlock(src: String, blockedDomains: Set<String>) -> Bool {
        guard let url = URL(string: src) else {
            return blockedDomains.contains { domain in
                src.lowercased().contains(domain.replacingOccurrences(of: "*.", with: ""))
            }
        }
        let host = url.host?.lowercased() ?? ""
        return blockedDomains.contains(where: { domain in
            let normalized = domain.hasPrefix("*.") ? String(domain.dropFirst(2)) : domain
            return host == normalized || host.hasSuffix(".\(normalized)")
        })
    }

    private static func containsBlockedDomain(text: String, blockedDomains: Set<String>) -> Bool {
        let lower = text.lowercased()
        return blockedDomains.contains { domain in
            let normalized = domain.hasPrefix("*.") ? String(domain.dropFirst(2)) : domain
            return lower.contains(normalized)
        }
    }

    private static func matchesRule(action: ScriptRuleAction,
                                    src: String?,
                                    inlineScript: String?,
                                    rules: [ScriptRule]) -> Bool {
        return rules.contains { rule in
            guard rule.enabled, rule.action == action else { return false }
            let pattern = rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !pattern.isEmpty else { return false }

            switch rule.matchType {
            case .srcContains:
                return src?.lowercased().contains(pattern) ?? false
            case .srcHostMatches:
                guard let src = src else { return false }
                let host = URL(string: src)?.host?.lowercased() ?? src.lowercased()
                return host == pattern || host.hasSuffix(".\(pattern)")
            case .inlineContains:
                return inlineScript?.lowercased().contains(pattern) ?? false
            }
        }
    }
}

extension Data {
    func gunzipped() throws -> Data {
        let nsData = self as NSData
        let gzipAlgorithm = NSData.CompressionAlgorithm(rawValue: 2)!
        guard let decompressed = try? nsData.decompressed(using: gzipAlgorithm) else {
            throw ResponseModifierError.decompressionFailed
        }
        return decompressed as Data
    }

    func inflated() throws -> Data {
        let nsData = self as NSData
        guard let decompressed = try? nsData.decompressed(using: .zlib) else {
            throw ResponseModifierError.decompressionFailed
        }
        return decompressed as Data
    }
}

enum ResponseModifierError: Error {
    case decompressionFailed
}
