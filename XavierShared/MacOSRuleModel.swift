import Foundation

public enum MacOSRuleAction: String, Codable, Equatable {
    case allow
    case block
}

public enum MacOSRuleType: String, Codable, Equatable {
    case process
    case signingID
    case endpoint
    case processFromEndpoint
    case global
    case directory
    case temporaryPID
}

public struct MacOSRuleModel: Codable, Equatable, Identifiable {
    public let id: String
    public var type: MacOSRuleType
    public var action: MacOSRuleAction
    public var path: String?
    public var signingID: String?
    public var signingInfo: String?
    public var endpointAddress: String?
    public var endpointPort: Int32?
    public var endpointHost: String?
    public var isDirectory: Bool
    public var isGlobal: Bool
    public var isTemporary: Bool
    public var pid: Int32?
    public var expiration: Date?
    public var isDisabled: Bool
    public var protocolName: String?
    public var direction: String?
    public var reason: String?
    public var createdAt: Date

    public init(id: String = UUID().uuidString,
                type: MacOSRuleType,
                action: MacOSRuleAction,
                path: String? = nil,
                signingID: String? = nil,
                signingInfo: String? = nil,
                endpointAddress: String? = nil,
                endpointPort: Int32? = nil,
                endpointHost: String? = nil,
                isDirectory: Bool = false,
                isGlobal: Bool = false,
                isTemporary: Bool = false,
                pid: Int32? = nil,
                expiration: Date? = nil,
                isDisabled: Bool = false,
                protocolName: String? = nil,
                direction: String? = nil,
                reason: String? = nil,
                createdAt: Date = Date()) {
        self.id = id
        self.type = type
        self.action = action
        self.path = path
        self.signingID = signingID
        self.signingInfo = signingInfo
        self.endpointAddress = endpointAddress
        self.endpointPort = endpointPort
        self.endpointHost = endpointHost
        self.isDirectory = isDirectory
        self.isGlobal = isGlobal
        self.isTemporary = isTemporary
        self.pid = pid
        self.expiration = expiration
        self.isDisabled = isDisabled
        self.protocolName = protocolName
        self.direction = direction
        self.reason = reason
        self.createdAt = createdAt
    }
}

public final class MacOSRuleStore {
    public enum StoreError: Error {
        case missingAppGroupContainer
    }

    private let resolver: BundleResolver
    private let storeName: String
    private let queue = DispatchQueue(label: "xavier.mac.rules.store")

    public init(resolver: BundleResolver, storeName: String = "rules.sqlite") {
        self.resolver = resolver
        self.storeName = storeName
    }

    public func loadRules() throws -> [MacOSRuleModel] {
        try queue.sync {
            let url = try storeURL()
            guard FileManager.default.fileExists(atPath: url.path) else {
                return []
            }
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([MacOSRuleModel].self, from: data)
        }
    }

    public func saveRules(_ rules: [MacOSRuleModel]) throws {
        try queue.sync {
            let url = try storeURL()
            let data = try JSONEncoder().encode(rules)
            try data.write(to: url, options: [.atomic])
        }
    }

    public func upsert(_ rule: MacOSRuleModel) throws {
        try queue.sync {
            let url = try storeURL()
            let rules: [MacOSRuleModel]
            if FileManager.default.fileExists(atPath: url.path) {
                let data = try Data(contentsOf: url)
                rules = try JSONDecoder().decode([MacOSRuleModel].self, from: data)
            } else {
                rules = []
            }

            var next = rules.filter { existing in
                existing.type != rule.type ||
                existing.path != rule.path ||
                existing.signingID != rule.signingID ||
                existing.endpointAddress != rule.endpointAddress ||
                existing.endpointHost != rule.endpointHost ||
                existing.endpointPort != rule.endpointPort ||
                existing.protocolName != rule.protocolName ||
                existing.direction != rule.direction
            }
            next.append(rule)
            let data = try JSONEncoder().encode(next)
            try data.write(to: url, options: [.atomic])
        }
    }

    private func storeURL() throws -> URL {
        guard let directoryURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: resolver.appGroupIdentifier)?
            .appendingPathComponent("data") else {
            throw StoreError.missingAppGroupContainer
        }

        if !FileManager.default.fileExists(atPath: directoryURL.path) {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }

        return directoryURL.appendingPathComponent(storeName)
    }
}
