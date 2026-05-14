import Foundation

public let maxModifiableRequestBodySize = 65536
public let requestBufferingTimeout: TimeInterval = 10.0

public struct RequestModification {
    public let modifiedHeaders: [String: String]?
    public let modifiedBody: Data?
    public let modifiedURL: String?
    public let wasModified: Bool

    public init(modifiedHeaders: [String: String]?, modifiedBody: Data?, modifiedURL: String?, wasModified: Bool) {
        self.modifiedHeaders = modifiedHeaders
        self.modifiedBody = modifiedBody
        self.modifiedURL = modifiedURL
        self.wasModified = wasModified
    }
}

public enum RequestHandlingPath {
    case streamThrough(metadata: HTTPRequestMetadata, capturedBodySoFar: Data?)
    case bufferAndModify(metadata: HTTPRequestMetadata,
                         originalBody: Data,
                         modifications: RequestModification)
}

public final class RequestModifier {
    public static func handlingPath(requestHeaders: HTTPRequestMetadata,
                                    host: String,
                                    bodySize: Int?,
                                    rules: [ModificationRule]) -> RequestHandlingPath {
        let matchingRules = rules.filter { $0.host == host || $0.host == "*" }

        guard !matchingRules.isEmpty else {
            return .streamThrough(metadata: requestHeaders, capturedBodySoFar: nil)
        }

        let bodyIsModifiable: Bool
        if let size = bodySize, size <= maxModifiableRequestBodySize {
            bodyIsModifiable = true
        } else {
            bodyIsModifiable = false
        }

        if bodyIsModifiable {
            return .bufferAndModify(metadata: requestHeaders,
                                    originalBody: Data(),
                                    modifications: RequestModification(modifiedHeaders: nil,
                                                                       modifiedBody: nil,
                                                                       modifiedURL: nil,
                                                                       wasModified: false))
        }

        if matchingRules.allSatisfy({ $0.type == .addHeader || $0.type == .removeHeader || $0.type == .replaceHeader }) {
            return .bufferAndModify(metadata: requestHeaders,
                                    originalBody: Data(),
                                    modifications: applyHeaderRules(requestHeaders, rules: matchingRules))
        }

        return .streamThrough(metadata: requestHeaders, capturedBodySoFar: nil)
    }

    public static func modifyRequest(request: HTTPRequestMetadata,
                                     originalBody: Data?,
                                     host: String,
                                     rules: [ModificationRule]) -> RequestModification {
        var modifiedHeaders = request.headers
        var modifiedBody = originalBody
        var modifiedURL: String? = nil
        var wasModified = false

        let matchingRules = rules.filter { $0.host == host || $0.host == "*" }

        for rule in matchingRules {
            switch rule.type {
            case .addHeader:
                if let key = rule.matchPattern, let value = rule.replacementValue {
                    modifiedHeaders[key] = value
                    wasModified = true
                }
            case .removeHeader:
                if let key = rule.matchPattern {
                    modifiedHeaders.removeValue(forKey: key)
                    wasModified = true
                }
            case .replaceHeader:
                if let key = rule.matchPattern, let value = rule.replacementValue {
                    modifiedHeaders[key] = value
                    wasModified = true
                }
            case .rewriteURL:
                if let pattern = rule.matchPattern, let replacement = rule.replacementValue {
                    modifiedURL = request.url.replacingOccurrences(of: pattern, with: replacement)
                    wasModified = true
                }
            case .replaceBody:
                if let pattern = rule.matchPattern, let replacement = rule.replacementValue,
                   var bodyString = String(data: modifiedBody ?? Data(), encoding: .utf8) {
                    bodyString = bodyString.replacingOccurrences(of: pattern, with: replacement)
                    modifiedBody = bodyString.data(using: .utf8)
                    wasModified = true
                }
            }
        }

        return RequestModification(
            modifiedHeaders: wasModified ? modifiedHeaders : nil,
            modifiedBody: wasModified && modifiedBody != originalBody ? modifiedBody : nil,
            modifiedURL: modifiedURL,
            wasModified: wasModified
        )
    }

    public static func rebuildRequest(original: HTTPRequestMetadata,
                                      modification: RequestModification,
                                      body: Data?) -> Data {
        let url = modification.modifiedURL ?? original.url
        let headers = modification.modifiedHeaders ?? original.headers
        let effectiveBody = modification.modifiedBody ?? body

        var finalHeaders = headers
        if let bodyData = effectiveBody, !bodyData.isEmpty {
            let contentLengthKey = finalHeaders.keys.first(where: { $0.lowercased() == "content-length" })
            if let existingKey = contentLengthKey {
                finalHeaders[existingKey] = "\(bodyData.count)"
            } else {
                finalHeaders["Content-Length"] = "\(bodyData.count)"
            }
        }

        return HTTPParser.buildHTTPRequest(
            method: original.method,
            url: url,
            httpVersion: original.httpVersion,
            headers: finalHeaders,
            body: effectiveBody
        )
    }

    private static func applyHeaderRules(_ request: HTTPRequestMetadata, rules: [ModificationRule]) -> RequestModification {
        var modifiedHeaders = request.headers
        var wasModified = false

        for rule in rules {
            switch rule.type {
            case .addHeader:
                if let key = rule.matchPattern, let value = rule.replacementValue {
                    modifiedHeaders[key] = value
                    wasModified = true
                }
            case .removeHeader:
                if let key = rule.matchPattern {
                    modifiedHeaders.removeValue(forKey: key)
                    wasModified = true
                }
            case .replaceHeader:
                if let key = rule.matchPattern, let value = rule.replacementValue {
                    modifiedHeaders[key] = value
                    wasModified = true
                }
            default:
                break
            }
        }

        return RequestModification(
            modifiedHeaders: wasModified ? modifiedHeaders : nil,
            modifiedBody: nil,
            modifiedURL: nil,
            wasModified: wasModified
        )
    }
}
