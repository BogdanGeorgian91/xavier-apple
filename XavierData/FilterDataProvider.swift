//
//  FilterDataProvider.swift
//  XavierData
//
//

import NetworkExtension
import XavierShared

class FilterDataProvider: NEFilterDataProvider {
    private let browserPeekBytes = 16 * 1024

    override func startFilter(completionHandler: @escaping (Error?) -> Void) {
        completionHandler(nil)
    }
    
    override func stopFilter(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        completionHandler()
    }
    
    override func handleNewFlow(_ flow: NEFilterFlow) -> NEFilterNewFlowVerdict {
        guard let rawApp = flow.sourceAppIdentifier
        else {
            let verdict = NEFilterNewFlowVerdict.allow()
            verdict.shouldReport = true
            return verdict
        }
        
        let app = rawApp.cleanAppIdentifier()
        let host = flow.getHost()

        do {
            _ = try BrowserEventManager.shared.logFlowMetadata(from: flow)
        } catch {
            // Browser capture should never affect filtering decisions.
        }
        
        // ignore exceptions
        if Set(StaticRules.apps).contains(app) {
            let verdict = NEFilterNewFlowVerdict.allow()
            verdict.shouldReport = true
            return verdict
        }
        
        if let host = host, Set(StaticRules.hosts).contains(host) {
            let verdict = NEFilterNewFlowVerdict.allow()
            verdict.shouldReport = true
            return verdict
        }

        // When all-activity mode is on and the app has live alerts enabled,
        // route through the control provider so it can fire notifications
        if !Constants.isNotificationMuted(for: app) && Constants.isAllActivityMode {
            return .needRules()
        }

        do {
            guard let rule = try RuleManager.shared.getRule(for: app, hostname: host) else {
                if flow is NEFilterBrowserFlow, let host = host, Constants.isNotificationMuted(for: app) {
                    try? RuleManager.shared.create(rule: Rule(ruleType: RuleType.hostFromApp(host: host, app: app), isAllowed: true))
                    return browserDataVerdict()
                }
                return .needRules()
            }

            let verdict = rule.isAllowed ? newFlowAllowVerdict(for: flow) : NEFilterNewFlowVerdict.drop()
            verdict.shouldReport = true
            return verdict
        } catch {
            RuleManager.recreateShared()
            do {
                guard let rule = try RuleManager.shared.getRule(for: app, hostname: host) else {
                    if flow is NEFilterBrowserFlow, let host = host, Constants.isNotificationMuted(for: app) {
                        try? RuleManager.shared.create(rule: Rule(ruleType: RuleType.hostFromApp(host: host, app: app), isAllowed: true))
                        return browserDataVerdict()
                    }
                    return .needRules()
                }
                let verdict = rule.isAllowed ? newFlowAllowVerdict(for: flow) : NEFilterNewFlowVerdict.drop()
                verdict.shouldReport = true
                return verdict
            } catch {
                return .needRules()
            }
        }
    }

    override func handleInboundData(from flow: NEFilterFlow, readBytesStartOffset offset: Int, readBytes: Data) -> NEFilterDataVerdict {
        logBrowserFlow(flow)
        return NEFilterDataVerdict(passBytes: readBytes.count, peekBytes: 0)
    }

    override func handleOutboundData(from flow: NEFilterFlow, readBytesStartOffset offset: Int, readBytes: Data) -> NEFilterDataVerdict {
        logBrowserFlow(flow)
        return NEFilterDataVerdict(passBytes: readBytes.count, peekBytes: 0)
    }

    override func handleInboundDataComplete(for flow: NEFilterFlow) -> NEFilterDataVerdict {
        logBrowserFlow(flow)
        return .allow()
    }

    override func handleOutboundDataComplete(for flow: NEFilterFlow) -> NEFilterDataVerdict {
        logBrowserFlow(flow)
        return .allow()
    }

    private func newFlowAllowVerdict(for flow: NEFilterFlow) -> NEFilterNewFlowVerdict {
        if flow is NEFilterBrowserFlow {
            return browserDataVerdict()
        }

        return NEFilterNewFlowVerdict.allow()
    }

    private func browserDataVerdict() -> NEFilterNewFlowVerdict {
        let verdict = NEFilterNewFlowVerdict.filterDataVerdict(withFilterInbound: true,
                                                               peekInboundBytes: browserPeekBytes,
                                                               filterOutbound: true,
                                                               peekOutboundBytes: browserPeekBytes)
        verdict.shouldReport = true
        return verdict
    }

    private func logBrowserFlow(_ flow: NEFilterFlow) {
        do {
            _ = try BrowserEventManager.shared.logFlowMetadata(from: flow)
        } catch {
            // Browser capture should never affect filtering decisions.
        }
    }
}
