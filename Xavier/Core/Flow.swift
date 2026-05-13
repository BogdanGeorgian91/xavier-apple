//
//  Flow.swift
//  Xavier
//
//

import Foundation
import NetworkExtension
import Darwin

extension String {
    func cleanAppIdentifier() -> String {
        var cleaned = self.trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasPrefix(".") {
            cleaned.removeFirst()
        }
        var parts = cleaned.components(separatedBy: ".")
        if parts.count > 2, let first = parts.first, first.count == 10, first.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) == nil {
            parts.removeFirst()
        }
        return parts.joined(separator: ".")
    }
}

extension NEFilterFlow {
    func flowIdentifier() -> String? {
        if #available(iOS 13.1, *) {
            return identifier.uuidString
        }

        return nil
    }

    func getHost() -> String? {
        if let host = self.url?.host {
            return host
        }

        switch self {
        case let browserFlow as NEFilterBrowserFlow:
            return browserFlow.request?.url?.host ?? browserFlow.request?.url?.absoluteString
        case let socketFlow as NEFilterSocketFlow:
            if #available(iOS 14.0, *) {
                if let host = socketFlow.remoteHostname {
                    return host
                }
            }

            if let endpoint = socketFlow.remoteEndpoint as? NWHostEndpoint {
                return endpoint.hostname
            }

            if let endpoint = socketFlow.remoteEndpoint {
                return "\(endpoint)"
            }

            return nil
        default:
            return nil
        }
    }

    func getEndpointIPAndPort() -> (ip: String?, port: Int32?) {
        guard let socketFlow = self as? NEFilterSocketFlow,
              let endpoint = socketFlow.remoteEndpoint as? NWHostEndpoint else {
            return (nil, nil)
        }

        return (endpoint.hostname, Int32(endpoint.port))
    }

    func getLocalEndpointIPAndPort() -> (ip: String?, port: Int32?) {
        guard let socketFlow = self as? NEFilterSocketFlow,
              let endpoint = socketFlow.localEndpoint as? NWHostEndpoint else {
            return (nil, nil)
        }

        return (endpoint.hostname, Int32(endpoint.port))
    }

    func getTransportProtocol() -> String? {
        guard let socketFlow = self as? NEFilterSocketFlow else {
            if self is NEFilterBrowserFlow {
                return "browser"
            }

            return nil
        }

        switch socketFlow.socketProtocol {
        case IPPROTO_TCP:
            return "tcp"
        case IPPROTO_UDP:
            return "udp"
        case IPPROTO_ICMP:
            return "icmp"
        default:
            return "proto_\(socketFlow.socketProtocol)"
        }
    }

    func getTrafficDirection() -> String? {
        if #available(iOS 13.0, *) {
            switch direction {
            case .inbound:
                return "inbound"
            case .outbound:
                return "outbound"
            case .any:
                return "any"
            @unknown default:
                return nil
            }
        }

        return nil
    }

    func networkEventPayload(timestamp: Date = Date(),
                             bytesInbound: Int64 = 0,
                             bytesOutbound: Int64 = 0) -> NetworkEventPayload? {
        guard let rawAppId = sourceAppIdentifier else {
            return nil
        }
        let app = rawAppId.cleanAppIdentifier()

        let endpoint = getEndpointIPAndPort()
        let localEndpoint = getLocalEndpointIPAndPort()

        return NetworkEventPayload(identifier: flowIdentifier(),
                                   timestamp: timestamp,
                                   app: app,
                                   host: getHost(),
                                   ipAddress: endpoint.ip,
                                   port: endpoint.port,
                                   localIP: localEndpoint.ip,
                                   localPort: localEndpoint.port,
                                   bytesInbound: bytesInbound,
                                   bytesOutbound: bytesOutbound,
                                   transportProtocol: getTransportProtocol(),
                                   direction: getTrafficDirection())

    }

    func browserFlowPayload() -> BrowserFlowPayload? {
        guard let rawAppId = sourceAppIdentifier else {
            return nil
        }

        let app = rawAppId.cleanAppIdentifier()

        if let browserFlow = self as? NEFilterBrowserFlow {
            let request = browserFlow.request
            let response = browserFlow.response
            let httpResponse = response as? HTTPURLResponse

            return BrowserFlowPayload(
                identifier: flowIdentifier(),
                app: app,
                host: request?.url?.host ?? url?.host ?? getHost(),
                url: request?.url?.absoluteString ?? url?.absoluteString,
                httpMethod: request?.httpMethod,
                requestHeaders: request?.allHTTPHeaderFields,
                requestBody: request?.httpBody,
                statusCode: Int32(httpResponse?.statusCode ?? 0),
                responseHeaders: httpResponse?.allHeaderFields.reduce(into: [String: String]()) { result, pair in
                    result[String(describing: pair.key)] = String(describing: pair.value)
                },
                parentURL: browserFlow.parentURL?.absoluteString,
                contentType: response?.mimeType
            )
        }

        guard isKnownBrowserApp(app), let host = getHost() else {
            return nil
        }

        return BrowserFlowPayload(
            identifier: flowIdentifier(),
            app: app,
            host: host,
            url: url?.absoluteString,
            httpMethod: nil,
            requestHeaders: nil,
            requestBody: nil,
            statusCode: 0,
            responseHeaders: nil,
            parentURL: nil,
            contentType: nil
        )
    }

    private func isKnownBrowserApp(_ appIdentifier: String) -> Bool {
        let knownBrowsers = [
            "com.apple.mobilesafari",
            "com.google.chrome.ios",
            "org.mozilla.ios.firefox",
            "com.microsoft.msedge",
            "com.brave.ios.browser",
            "com.duckduckgo.mobile.ios",
            "com.opera.OperaTouch",
            "company.thebrowser.Browser"
        ]

        if knownBrowsers.contains(appIdentifier) {
            return true
        }

        let lowercased = appIdentifier.lowercased()
        let browserKeywords = ["safari", "chrome", "firefox", "edge", "browser", "brave", "duckduckgo", "arc", "opera"]
        return browserKeywords.contains {
            lowercased.contains(".\($0)") || lowercased.hasSuffix($0)
        }
    }
}
