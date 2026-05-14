import Foundation
import NetworkExtension
import Darwin
import Security
import XavierShared

final class FilterDataProvider: NEFilterDataProvider {
    private let preferences = FilterPreferences()
    private let ruleCache = RuleCache()
    private let identityProvider = ProcessIdentityProvider()
    private var promptedProcessKeys = Set<String>()
    private var queuedFlowsByProcessKey = [String: [NEFilterFlow]]()

    override func startFilter(completionHandler: @escaping (Error?) -> Void) {
        FilterXPCListener.shared.ruleReloadHandler = { [weak self] in
            self?.ruleCache.reload()
        }
        ruleCache.reload()

        let outboundAllProtocols = NENetworkRule(remoteNetwork: nil,
                                                 remotePrefix: 0,
                                                 localNetwork: nil,
                                                 localPrefix: 0,
                                                 protocol: .any,
                                                 direction: .outbound)

        let outboundFilterRule = NEFilterRule(networkRule: outboundAllProtocols, action: .filterData)
        let settings = NEFilterSettings(rules: [outboundFilterRule], defaultAction: .allow)
        apply(settings) { error in
            completionHandler(error)
        }
    }

    override func stopFilter(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    override func handleNewFlow(_ flow: NEFilterFlow) -> NEFilterNewFlowVerdict {
        guard !preferences.isDisabled else {
            return allowVerdict()
        }

        guard let socketFlow = flow as? NEFilterSocketFlow else {
            return allowVerdict()
        }

        let identity = identityProvider.identity(for: socketFlow)
        let metadata = MacOSFlowMetadata(flow: socketFlow, identity: identity)

        if preferences.blockMode, !preferences.matchesAllowList(metadata: metadata, identity: identity) {
            ruleCache.recordRule(for: metadata, identity: identity, isAllowed: false, reason: "block_mode", scope: .process)
            return NEFilterNewFlowVerdict.drop()
        }

        if preferences.matchesBlockList(metadata: metadata, identity: identity) {
            return NEFilterNewFlowVerdict.drop()
        }

        if preferences.allowLocalhost, metadata.isLocalhost {
            return allowVerdict()
        }

        if preferences.allowDNS, metadata.transportProtocol == "udp", metadata.port == 53 {
            return allowVerdict()
        }

        if let rule = ruleCache.match(metadata: metadata) {
            return rule.isAllowed ? allowVerdict() : NEFilterNewFlowVerdict.drop()
        }

        if preferences.allowApple, identity.signer == .apple, !Graylist.contains(signingIdentifier: identity.signingIdentifier) {
            ruleCache.recordRule(for: metadata, identity: identity, isAllowed: true, reason: "apple_signed", scope: .process)
            ruleCache.reload()
            return allowVerdict()
        }

        if preferences.allowInstalled, identity.wasInstalledBeforeBaseline {
            ruleCache.recordRule(for: metadata, identity: identity, isAllowed: true, reason: "installed_before_xavier", scope: .process)
            ruleCache.reload()
            return allowVerdict()
        }

        if preferences.passiveMode || !FilterXPCListener.shared.hasConnectedClient {
            ruleCache.recordRule(for: metadata, identity: identity, isAllowed: true, reason: "passive_no_client", scope: .process)
            ruleCache.reload()
            return allowVerdict()
        }

        if promptedProcessKeys.contains(metadata.processKey) {
            queuedFlowsByProcessKey[metadata.processKey, default: []].append(flow)
            return NEFilterNewFlowVerdict.pause()
        }

        promptedProcessKeys.insert(metadata.processKey)

        let details = metadata.flowDetails(displayName: identity.displayName)
        let delivered = FilterXPCListener.shared.showAlert(flowDetails: details) { [weak self] decision in
            let verdict = decision.action == .allow ? self?.allowVerdict() : NEFilterNewFlowVerdict.drop()
            if decision.rememberDecision {
                self?.ruleCache.recordRule(for: metadata, identity: identity, isAllowed: decision.action == .allow, reason: "user_decision", scope: decision.scope)
                self?.ruleCache.reload()
            }
            self?.resumeFlow(flow, with: verdict ?? NEFilterNewFlowVerdict.drop())
            let queuedFlows = self?.queuedFlowsByProcessKey.removeValue(forKey: metadata.processKey) ?? []
            queuedFlows.forEach { self?.resumeFlow($0, with: verdict ?? NEFilterNewFlowVerdict.drop()) }
            self?.promptedProcessKeys.remove(metadata.processKey)
        }
        guard delivered else {
            promptedProcessKeys.remove(metadata.processKey)
            ruleCache.recordRule(for: metadata, identity: identity, isAllowed: true, reason: "alert_delivery_failed", scope: .process)
            ruleCache.reload()
            return allowVerdict()
        }
        return NEFilterNewFlowVerdict.pause()
    }

    private func allowVerdict() -> NEFilterNewFlowVerdict {
        let verdict = NEFilterNewFlowVerdict.allow()
        verdict.shouldReport = true
        return verdict
    }
}

private struct FilterPreferences {
    private let defaults = UserDefaults.group ?? .standard

    var allowApple: Bool { bool(for: "PREF_ALLOW_APPLE", defaultValue: true) }
    var allowDNS: Bool { bool(for: "PREF_ALLOW_DNS", defaultValue: true) }
    var allowInstalled: Bool { bool(for: "PREF_ALLOW_INSTALLED", defaultValue: true) }
    var allowLocalhost: Bool { bool(for: "PREF_ALLOW_LOCALHOST", defaultValue: true) }
    var blockMode: Bool { bool(for: "PREF_BLOCK_MODE", defaultValue: false) }
    var passiveMode: Bool { bool(for: "PREF_PASSIVE_MODE", defaultValue: false) }
    var isDisabled: Bool { bool(for: "PREF_IS_DISABLED", defaultValue: false) }

    func matchesAllowList(metadata: MacOSFlowMetadata, identity: ProcessIdentity) -> Bool {
        matchesList(key: "PREF_ALLOW_LIST", metadata: metadata, identity: identity)
    }

    func matchesBlockList(metadata: MacOSFlowMetadata, identity: ProcessIdentity) -> Bool {
        matchesList(key: "PREF_BLOCK_LIST", metadata: metadata, identity: identity)
    }

    private func bool(for key: String, defaultValue: Bool) -> Bool {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.bool(forKey: key)
    }

    private func matchesList(key: String, metadata: MacOSFlowMetadata, identity: ProcessIdentity) -> Bool {
        let entries = Set(defaults.stringArray(forKey: key) ?? [])
        guard !entries.isEmpty else { return false }
        let candidates = [
            metadata.processKey,
            identity.path,
            identity.signingIdentifier,
            metadata.host,
            metadata.endpointIP
        ].compactMap { $0 }
        return candidates.contains { entries.contains($0) }
    }
}

private enum ProcessSigner: String {
    case apple
    case developerID
    case appStore
    case adHoc
    case unsigned
    case unknown
}

private struct ProcessIdentity {
    let auditTokenHash: String
    let pid: Int32?
    let effectiveUserID: uid_t?
    let path: String?
    let signingIdentifier: String?
    let signingInfo: String?
    let displayName: String
    let signer: ProcessSigner
    let stableKey: String
    let wasInstalledBeforeBaseline: Bool
}

private final class ProcessIdentityProvider {
    func identity(for flow: NEFilterSocketFlow) -> ProcessIdentity {
        let tokenData = flow.sourceAppAuditToken
        let tokenHash = tokenData?.SHA256.hex ?? "unknown"
        let auditToken = tokenData?.auditToken
        let pid = auditToken.map { audit_token_to_pid($0) }
        let path = pid.flatMap { executablePath(for: $0) }
        let signing = signingInfo(path: path, auditToken: auditToken)
        let shortHash = String(tokenHash.prefix(12))
        let stableKey = signing.identifier ?? path ?? "audit-token-\(shortHash)"
        let displayName = path.flatMap { URL(fileURLWithPath: $0).lastPathComponent }.flatMap { $0.isEmpty ? nil : $0 } ?? "Process \(shortHash)"

        return ProcessIdentity(
            auditTokenHash: tokenHash,
            pid: pid,
            effectiveUserID: nil,
            path: path,
            signingIdentifier: signing.identifier,
            signingInfo: signing.summary,
            displayName: displayName,
            signer: signing.signer,
            stableKey: stableKey,
            wasInstalledBeforeBaseline: wasInstalledBeforeBaseline(path: path)
        )
    }

    private func executablePath(for pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let result = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard result > 0 else { return nil }
        return String(cString: buffer)
    }

    private func signingInfo(path: String?, auditToken: audit_token_t?) -> (identifier: String?, summary: String?, signer: ProcessSigner) {
        var identifier: String?
        if let auditToken, let task = SecTaskCreateWithAuditToken(nil, auditToken) {
            identifier = SecTaskCopySigningIdentifier(task, nil) as String?
        }

        guard let path else {
            return (identifier, nil, identifier == nil ? .unknown : .developerID)
        }

        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &staticCode)
        guard createStatus == errSecSuccess, let staticCode else {
            return (identifier, nil, .unsigned)
        }

        let validityStatus = SecStaticCodeCheckValidity(staticCode, [], nil)
        var info: CFDictionary?
        SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        let dictionary = info as? [String: Any]
        let staticIdentifier = dictionary?[kSecCodeInfoIdentifier as String] as? String
        let authorities = dictionary?[kSecCodeInfoCertificates as String] as? [SecCertificate]
        let authorityNames = authorities?.compactMap { SecCertificateCopySubjectSummary($0) as String? } ?? []
        let summary = authorityNames.joined(separator: " > ")
        let signer = classifySigner(identifier: identifier ?? staticIdentifier, authorities: authorityNames, validityStatus: validityStatus)
        return (identifier ?? staticIdentifier, summary.isEmpty ? nil : summary, signer)
    }

    private func classifySigner(identifier: String?, authorities: [String], validityStatus: OSStatus) -> ProcessSigner {
        guard validityStatus == errSecSuccess else { return .unsigned }
        if identifier?.hasPrefix("com.apple.") == true || authorities.contains(where: { $0.localizedCaseInsensitiveContains("Apple") }) {
            return .apple
        }
        if authorities.contains(where: { $0.localizedCaseInsensitiveContains("Developer ID") }) {
            return .developerID
        }
        if authorities.contains(where: { $0.localizedCaseInsensitiveContains("Apple Mac OS Application Signing") || $0.localizedCaseInsensitiveContains("3rd Party Mac Developer") }) {
            return .appStore
        }
        return identifier == nil ? .adHoc : .developerID
    }

    private func wasInstalledBeforeBaseline(path: String?) -> Bool {
        guard let path,
              let creationDate = try? FileManager.default.attributesOfItem(atPath: path)[.creationDate] as? Date else {
            return false
        }

        let key = "PREF_INSTALL_BASELINE_DATE"
        let defaults = UserDefaults.group ?? .standard
        let baseline: Date
        if let saved = defaults.object(forKey: key) as? Date {
            baseline = saved
        } else {
            baseline = Date()
            defaults.set(baseline, forKey: key)
        }
        return creationDate < baseline
    }
}

private extension Data {
    var auditToken: audit_token_t? {
        guard count == MemoryLayout<audit_token_t>.size else { return nil }
        return withUnsafeBytes { rawBuffer in
            rawBuffer.loadUnaligned(as: audit_token_t.self)
        }
    }
}

private struct MacOSFlowMetadata {
    let processKey: String
    let path: String?
    let signingIdentifier: String?
    let signingInfo: String?
    let host: String?
    let endpointIP: String?
    let port: Int32?
    let transportProtocol: String?
    let direction: String?

    var isLocalhost: Bool {
        let values = [host, endpointIP].compactMap { $0?.lowercased() }
        return values.contains("localhost") || values.contains("127.0.0.1") || values.contains("::1")
    }

    init(flow: NEFilterSocketFlow, identity: ProcessIdentity) {
        self.processKey = identity.stableKey
        self.path = identity.path
        self.signingIdentifier = identity.signingIdentifier
        self.signingInfo = identity.signingInfo
        self.host = flow.remoteHostname
        if let endpoint = flow.remoteEndpoint as? NWHostEndpoint {
            self.endpointIP = endpoint.hostname
            self.port = Int32(endpoint.port)
        } else {
            self.endpointIP = nil
            self.port = nil
        }

        switch flow.socketProtocol {
        case IPPROTO_TCP:
            self.transportProtocol = "tcp"
        case IPPROTO_UDP:
            self.transportProtocol = "udp"
        case IPPROTO_ICMP:
            self.transportProtocol = "icmp"
        default:
            self.transportProtocol = "proto_\(flow.socketProtocol)"
        }

        switch flow.direction {
        case .inbound:
            self.direction = "inbound"
        case .outbound:
            self.direction = "outbound"
        case .any:
            self.direction = "any"
        @unknown default:
            self.direction = nil
        }
    }

    func flowDetails(displayName: String) -> MacOSFilterFlowDetails {
        MacOSFilterFlowDetails(
            flowIdentifier: UUID().uuidString,
            processKey: processKey,
            displayName: displayName,
            signingIdentifier: signingIdentifier,
            host: host,
            endpointIP: endpointIP,
            port: port,
            transportProtocol: transportProtocol,
            direction: direction
        )
    }
}

private struct CachedRule {
    let processKey: String
    let signingID: String?
    let path: String?
    let host: String?
    let endpointAddress: String?
    let port: Int32?
    let protocolName: String?
    let direction: String?
    let signingInfo: String?
    let isAllowed: Bool
}

private final class RuleCache {
    private var rulesByProcess = [String: [CachedRule]]()
    private var globalRules = [CachedRule]()
    private let store = MacOSRuleStore(resolver: FrameworkBundleResolver())

    func reload() {
        do {
            let macRules = try store.loadRules()
            var next = [String: [CachedRule]]()
            var globals = [CachedRule]()
            for rule in macRules where !rule.isDisabled && (rule.expiration.map { $0 > Date() } ?? true) {
                let cached = CachedRule(rule: rule)
                if rule.isGlobal || rule.type == .global {
                    globals.append(cached)
                    continue
                }
                if let key = rule.signingID ?? rule.path {
                    next[key, default: []].append(cached)
                }
            }
            rulesByProcess = next
            globalRules = globals
        } catch {
            // Keep the last valid cache if reload fails.
        }
    }

    func match(metadata: MacOSFlowMetadata) -> CachedRule? {
        let candidates = (rulesByProcess[metadata.processKey] ?? []) + globalRules
        return candidates.first { rule in
            let signingMatches = rule.signingID == nil || rule.signingID == metadata.signingIdentifier
            let pathMatches = rule.path == nil || rule.path == metadata.path
            let hostMatches = rule.host == nil || rule.host == metadata.host || rule.host == metadata.endpointIP
            let endpointMatches = rule.endpointAddress == nil || rule.endpointAddress == metadata.endpointIP || rule.endpointAddress == metadata.host
            let portMatches = rule.port == nil || rule.port == metadata.port
            let protocolMatches = rule.protocolName == nil || rule.protocolName == metadata.transportProtocol
            let directionMatches = rule.direction == nil || rule.direction == metadata.direction
            let signingUnchanged = rule.signingInfo == nil || rule.signingInfo == metadata.signingInfo
            return signingMatches && pathMatches && hostMatches && endpointMatches && portMatches && protocolMatches && directionMatches && signingUnchanged
        }
    }

    func recordRule(for metadata: MacOSFlowMetadata,
                    identity: ProcessIdentity,
                    isAllowed: Bool,
                    reason: String,
                    scope: MacOSFilterDecisionScope) {
        let action: MacOSRuleAction = isAllowed ? .allow : .block
        let rule: MacOSRuleModel

        switch scope {
        case .thisEndpoint:
            rule = MacOSRuleModel(type: .processFromEndpoint,
                                  action: action,
                                  path: identity.path,
                                  signingID: identity.signingIdentifier ?? metadata.processKey,
                                  signingInfo: identity.signingInfo,
                                  endpointAddress: metadata.endpointIP,
                                  endpointPort: metadata.port,
                                  endpointHost: metadata.host,
                                  protocolName: metadata.transportProtocol,
                                  direction: metadata.direction,
                                  reason: reason)
        case .host:
            rule = MacOSRuleModel(type: .endpoint,
                                  action: action,
                                  signingID: identity.signingIdentifier ?? metadata.processKey,
                                  signingInfo: identity.signingInfo,
                                  endpointHost: metadata.host ?? metadata.endpointIP,
                                  protocolName: metadata.transportProtocol,
                                  direction: metadata.direction,
                                  reason: reason)
        case .process:
            rule = MacOSRuleModel(type: identity.signingIdentifier == nil ? .process : .signingID,
                                  action: action,
                                  path: identity.path,
                                  signingID: identity.signingIdentifier ?? metadata.processKey,
                                  signingInfo: identity.signingInfo,
                                  protocolName: metadata.transportProtocol,
                                  direction: metadata.direction,
                                  reason: reason)
        case .global:
            rule = MacOSRuleModel(type: .global,
                                  action: action,
                                  endpointHost: metadata.host,
                                  endpointAddress: metadata.endpointIP,
                                  endpointPort: metadata.port,
                                  isGlobal: true,
                                  protocolName: metadata.transportProtocol,
                                  direction: metadata.direction,
                                  reason: reason)
        }

        do {
            try store.upsert(rule)
        } catch {
            NSLog("[XavierMacFilter] failed to persist rule: %@", String(describing: error))
        }
    }
}

private extension CachedRule {
    init(rule: MacOSRuleModel) {
        self.processKey = rule.signingID ?? rule.path ?? "*"
        self.signingID = rule.signingID
        self.path = rule.path
        self.host = rule.endpointHost
        self.endpointAddress = rule.endpointAddress
        self.port = rule.endpointPort
        self.protocolName = rule.protocolName
        self.direction = rule.direction
        self.signingInfo = rule.signingInfo
        self.isAllowed = rule.action == .allow
    }
}

private enum Graylist {
    private static let signingIdentifiers: Set<String> = [
        "com.apple.nc", "com.apple.ftp", "com.apple.zsh", "com.apple.ksh",
        "com.apple.php", "com.apple.scp", "com.apple.ssh", "com.apple.bash",
        "com.apple.tcsh", "com.apple.curl", "com.apple.perl", "com.apple.ruby",
        "com.apple.sftp", "com.tcltk.tclsh", "com.apple.perl5", "com.apple.whois",
        "com.apple.python", "com.apple.telnet", "com.apple.openssh", "com.apple.python2",
        "com.apple.python3", "org.python.python", "com.apple.pythonw", "com.apple.osascript"
    ]

    static func contains(signingIdentifier: String?) -> Bool {
        guard let signingIdentifier else { return false }
        return signingIdentifiers.contains(signingIdentifier)
    }
}
