import Foundation
import NetworkExtension
import XavierShared

class AppProxyProvider: NEAppProxyProvider {
    // SEMANTICS NOTE:
    // In NEAppProxyProvider (iOS): return false = refuse connection
    // In NETransparentProxyProvider (macOS): return false = allow direct, bypass proxy
    // XavierShared must handle both semantics correctly.
    // When porting to macOS, flows that should bypass proxying must return false,
    // while flows that should be refused must explicitly closeReadWithError/closeWriteWithError.

    private var flowHandlers = [UUID: FlowHandler]()
    private let maxConcurrentMITMFlows = 15
    private let tlsProxy = TLSProxy()
    private let loggingQueue = DispatchQueue(label: "\(Constants.appBundleIdentifier).proxy.logging", qos: .utility)

    override func startProxy(options: [String: Any]? = nil, completionHandler: @escaping (Error?) -> Void) {
        completionHandler(nil)
    }

    override func handleNewUDPFlow(_ flow: NEAppProxyUDPFlow, initialRemoteEndpoint remoteEndpoint: NWEndpoint) -> Bool {
        let flowID = UUID()
        let appID = flow.metaData.sourceAppSigningIdentifier ?? "unknown"
        NSLog("[XavierProxy][%@] rejecting udp flow app=%@ host=%@ endpoint=%@", flowID.uuidString, appID, flow.remoteHostname ?? "", String(describing: remoteEndpoint))
        logPassthrough(flowID: flowID, appID: appID, hostname: flow.remoteHostname, port: 443, reason: "udp_rejected")
        return false
    }

    override func stopProxy(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        for (_, handler) in flowHandlers {
            handler.cancel()
        }
        flowHandlers.removeAll()
        completionHandler()
    }

    override func handleNewFlow(_ flow: NEAppProxyFlow) -> Bool {
        let flowID = UUID()
        let appID = flow.metaData.sourceAppSigningIdentifier ?? "unknown"

        if flow is NEAppProxyUDPFlow {
            NSLog("[XavierProxy][%@] unexpected udp flow via handleNewFlow app=%@ host=%@", flowID.uuidString, appID, flow.remoteHostname ?? "")
            logPassthrough(flowID: flowID, appID: appID, hostname: flow.remoteHostname, port: 443, reason: "udp_unexpected")
            return false
        }

        guard let tcpFlow = flow as? NEAppProxyTCPFlow else {
            return false
        }

        let hostname = tcpFlow.remoteHostname ?? ""
        let port = extractPort(from: tcpFlow)
        let blockedPatterns = BlocklistMatcher.loadEnabledPatterns()
        let mitmEnabled = Constants.isMITMEnabled

        if BlocklistMatcher.isBlocked(hostname: hostname, patterns: blockedPatterns) {
            let appMetadata = AppMetadataFetcher.shared.appName(for: appID)
            _ = try? InspectionManager.shared.logRequest(InspectedRequestPayload(
                identifier: flowID.uuidString,
                appName: appMetadata,
                appBundleID: appID,
                host: hostname,
                url: nil,
                httpMethod: nil,
                requestHeaders: nil,
                requestBody: nil,
                statusCode: 0,
                responseHeaders: nil,
                responseBody: nil,
                contentType: nil,
                duration: 0,
                tlsVersion: nil,
                port: Int32(port),
                pinned: false,
                blocked: true,
                blockedReason: "domain_blocklist",
                responseModified: false,
                requestModified: false,
                originalRequestHeaders: nil,
                originalRequestBody: nil,
                originalResponseHeaders: nil,
                originalResponseBody: nil
            ))
            NSLog("[XavierProxy][%@] blocked app=%@ host=%@ port=%d", flowID.uuidString, appID, hostname, Int(port))
            return false
        }

        if CertificateManager.shared.isPinnedDomain(hostname) {
            NSLog("[XavierProxy][%@] pinned passthrough app=%@ host=%@", flowID.uuidString, appID, hostname)
            logPassthrough(flowID: flowID, appID: appID, hostname: hostname, port: port, reason: "pinned_domain")
            let handler = FlowHandler(flowID: flowID, mode: .passthrough)
            flowHandlers[flowID] = handler
            handler.startPassthroughTCP(tcpFlow: tcpFlow) { [weak self] in
                self?.flowHandlers.removeValue(forKey: flowID)
            }
            return true
        }

        let activeMITMCount = flowHandlers.values.filter { $0.mode == .mitm }.count
        if activeMITMCount >= maxConcurrentMITMFlows {
            NSLog("[XavierProxy][%@] capacity passthrough app=%@ host=%@ port=%d", flowID.uuidString, appID, hostname, Int(port))
            logPassthrough(flowID: flowID, appID: appID, hostname: hostname, port: port, reason: "mitm_capacity")
            let handler = FlowHandler(flowID: flowID, mode: .passthrough)
            flowHandlers[flowID] = handler
            handler.startPassthroughTCP(tcpFlow: tcpFlow) { [weak self] in
                self?.flowHandlers.removeValue(forKey: flowID)
            }
            return true
        }

        if !mitmEnabled {
            NSLog("[XavierProxy][%@] mitm disabled passthrough app=%@ host=%@ port=%d", flowID.uuidString, appID, hostname, Int(port))
            logPassthrough(flowID: flowID, appID: appID, hostname: hostname, port: port, reason: "mitm_disabled")
            let handler = FlowHandler(flowID: flowID, mode: .passthrough)
            flowHandlers[flowID] = handler
            handler.startPassthroughTCP(tcpFlow: tcpFlow) { [weak self] in
                self?.flowHandlers.removeValue(forKey: flowID)
            }
            return true
        }

        if port == 443 && !hostname.isEmpty {
            NSLog("[XavierProxy][%@] mitm app=%@ host=%@ port=%d", flowID.uuidString, appID, hostname, Int(port))
            let handler = FlowHandler(flowID: flowID, mode: .mitm)
            flowHandlers[flowID] = handler
            handler.startMITM(tcpFlow: tcpFlow, hostname: hostname, port: port, appID: appID) { [weak self] result in
                switch result {
                case .completed(let payload):
                    _ = try? InspectionManager.shared.logRequest(payload)
                case .pinningDetected(let pinnedHost):
                    CertificateManager.shared.markAsPinned(pinnedHost)
                case .passthrough, .error:
                    break
                }
                self?.flowHandlers.removeValue(forKey: flowID)
            }
            return true
        }

        if port == 80 {
            NSLog("[XavierProxy][%@] http observe app=%@ host=%@ port=%d", flowID.uuidString, appID, hostname, Int(port))
            let handler = FlowHandler(flowID: flowID, mode: .mitm)
            flowHandlers[flowID] = handler
            handler.startMITM(tcpFlow: tcpFlow, hostname: hostname, port: port, appID: appID) { [weak self] result in
                switch result {
                case .completed(let payload):
                    _ = try? InspectionManager.shared.logRequest(payload)
                case .pinningDetected, .passthrough, .error:
                    break
                }
                self?.flowHandlers.removeValue(forKey: flowID)
            }
            return true
        }

        NSLog("[XavierProxy][%@] tcp passthrough app=%@ host=%@ port=%d", flowID.uuidString, appID, hostname, Int(port))
        logPassthrough(flowID: flowID, appID: appID, hostname: hostname, port: port, reason: "tcp_passthrough")
        let handler = FlowHandler(flowID: flowID, mode: .passthrough)
        flowHandlers[flowID] = handler
        handler.startPassthroughTCP(tcpFlow: tcpFlow) { [weak self] in
            self?.flowHandlers.removeValue(forKey: flowID)
        }
        return true
    }

    private func extractPort(from flow: NEAppProxyTCPFlow) -> UInt16 {
        if let endpoint = flow.remoteEndpoint as? NWHostEndpoint,
           let port = UInt16(endpoint.port) {
            return port
        }
        return 0
    }

    private func logPassthrough(flowID: UUID, appID: String, hostname: String?, port: UInt16, reason: String) {
        loggingQueue.async {
            let appMetadata = AppMetadataFetcher.shared.appName(for: appID)
            let headers = [
                "X-Xavier-Handling": "passthrough",
                "X-Xavier-Reason": reason
            ]
            let responseHeaders = [
                "X-Xavier-Outcome": "No deep inspection data captured for this flow."
            ]
            _ = try? InspectionManager.shared.logRequest(InspectedRequestPayload(
                identifier: flowID.uuidString,
                appName: appMetadata,
                appBundleID: appID,
                host: hostname,
                url: nil,
                httpMethod: "FLOW",
                requestHeaders: headers,
                requestBody: nil,
                statusCode: 0,
                responseHeaders: responseHeaders,
                responseBody: nil,
                contentType: nil,
                duration: 0,
                tlsVersion: "Passthrough",
                port: Int32(port),
                pinned: reason == "pinned_domain" || reason == "pinned_fallback",
                blocked: false,
                blockedReason: reason,
                responseModified: false,
                requestModified: false,
                originalRequestHeaders: nil,
                originalRequestBody: nil,
                originalResponseHeaders: nil,
                originalResponseBody: nil
            ))
        }
    }
}

enum FlowHandlerMode {
    case passthrough
    case mitm
}

final class FlowHandler {
    let flowID: UUID
    let mode: FlowHandlerMode
    private var copyManager: FlowCopyManager?
    private var tlsProxy: TLSProxy?

    init(flowID: UUID, mode: FlowHandlerMode) {
        self.flowID = flowID
        self.mode = mode
    }

    func startPassthroughTCP(tcpFlow: NEAppProxyTCPFlow, onComplete: @escaping () -> Void) {
        let manager = FlowCopyManager(flowID: flowID, tcpFlow: tcpFlow)
        copyManager = manager
        manager.startPassthroughTCP(onComplete: onComplete)
    }

    func startPassthroughUDP(udpFlow: NEAppProxyUDPFlow, onComplete: @escaping () -> Void) {
        let manager = FlowCopyManager(flowID: flowID, udpFlow: udpFlow)
        copyManager = manager
        manager.startPassthroughUDP(onComplete: onComplete)
    }

    func startMITM(tcpFlow: NEAppProxyTCPFlow, hostname: String, port: UInt16, appID: String, completion: @escaping (TLSProxy.TLSResult) -> Void) {
        let tlsProxy = TLSProxy()
        self.tlsProxy = tlsProxy
        NSLog("[XavierProxy][%@] startMITM host=%@ port=%d app=%@", flowID.uuidString, hostname, Int(port), appID)
        tlsProxy.proxyFlow(tcpFlow, hostname: hostname, port: port, flowID: flowID, appID: appID) { [weak self] result in
            switch result {
            case .passthrough:
                NSLog("[XavierProxy][%@] MITM result=passthrough starting fallback", self?.flowID.uuidString ?? "unknown")
                self?.tlsProxy = nil
                self?.startPassthroughTCP(tcpFlow: tcpFlow, onComplete: {
                    completion(.passthrough(hostname: hostname, port: port))
                })
            case .pinningDetected(let pinnedHost):
                CertificateManager.shared.markAsPinned(pinnedHost)
                NSLog("[XavierProxy][%@] MITM result=pinningDetected host=%@ starting fallback", self?.flowID.uuidString ?? "unknown", pinnedHost)
                self?.tlsProxy = nil
                self?.startPassthroughTCP(tcpFlow: tcpFlow, onComplete: {
                    completion(.passthrough(hostname: hostname, port: port))
                })
            case .error:
                NSLog("[XavierProxy][%@] MITM result=error starting fallback", self?.flowID.uuidString ?? "unknown")
                self?.tlsProxy = nil
                self?.startPassthroughTCP(tcpFlow: tcpFlow, onComplete: {
                    completion(.passthrough(hostname: hostname, port: port))
                })
            case .completed:
                NSLog("[XavierProxy][%@] MITM result=completed", self?.flowID.uuidString ?? "unknown")
                self?.tlsProxy = nil
                completion(result)
            }
        }
    }

    func cancel() {
        tlsProxy = nil
        copyManager?.cancel()
    }
}
