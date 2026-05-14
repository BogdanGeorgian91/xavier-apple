import Foundation

@objc public enum MacOSFilterDecisionAction: Int {
    case allow = 0
    case block = 1
}

@objc public enum MacOSFilterDecisionScope: Int {
    case thisEndpoint = 0
    case host = 1
    case process = 2
    case global = 3
}

@objc(MacOSFilterFlowDetails)
public final class MacOSFilterFlowDetails: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    @objc public let flowIdentifier: String
    @objc public let processKey: String
    @objc public let displayName: String
    @objc public let signingIdentifier: String?
    @objc public let host: String?
    @objc public let endpointIP: String?
    @objc public let port: NSNumber?
    @objc public let transportProtocol: String?
    @objc public let direction: String?

    public init(flowIdentifier: String,
                processKey: String,
                displayName: String,
                signingIdentifier: String?,
                host: String?,
                endpointIP: String?,
                port: Int32?,
                transportProtocol: String?,
                direction: String?) {
        self.flowIdentifier = flowIdentifier
        self.processKey = processKey
        self.displayName = displayName
        self.signingIdentifier = signingIdentifier
        self.host = host
        self.endpointIP = endpointIP
        self.port = port.map { NSNumber(value: $0) }
        self.transportProtocol = transportProtocol
        self.direction = direction
        super.init()
    }

    public convenience init?(coder: NSCoder) {
        guard let flowIdentifier = coder.decodeObject(of: NSString.self, forKey: "flowIdentifier") as? String,
              let processKey = coder.decodeObject(of: NSString.self, forKey: "processKey") as? String,
              let displayName = coder.decodeObject(of: NSString.self, forKey: "displayName") as? String else {
            return nil
        }

        self.init(
            flowIdentifier: flowIdentifier,
            processKey: processKey,
            displayName: displayName,
            signingIdentifier: coder.decodeObject(of: NSString.self, forKey: "signingIdentifier") as? String,
            host: coder.decodeObject(of: NSString.self, forKey: "host") as? String,
            endpointIP: coder.decodeObject(of: NSString.self, forKey: "endpointIP") as? String,
            port: (coder.decodeObject(of: NSNumber.self, forKey: "port"))?.int32Value,
            transportProtocol: coder.decodeObject(of: NSString.self, forKey: "transportProtocol") as? String,
            direction: coder.decodeObject(of: NSString.self, forKey: "direction") as? String
        )
    }

    public func encode(with coder: NSCoder) {
        coder.encode(flowIdentifier, forKey: "flowIdentifier")
        coder.encode(processKey, forKey: "processKey")
        coder.encode(displayName, forKey: "displayName")
        coder.encode(signingIdentifier, forKey: "signingIdentifier")
        coder.encode(host, forKey: "host")
        coder.encode(endpointIP, forKey: "endpointIP")
        coder.encode(port, forKey: "port")
        coder.encode(transportProtocol, forKey: "transportProtocol")
        coder.encode(direction, forKey: "direction")
    }
}

@objc(MacOSFilterDecision)
public final class MacOSFilterDecision: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    @objc public let actionRawValue: Int
    @objc public let scopeRawValue: Int
    @objc public let rememberDecision: Bool

    public var action: MacOSFilterDecisionAction {
        MacOSFilterDecisionAction(rawValue: actionRawValue) ?? .allow
    }

    public var scope: MacOSFilterDecisionScope {
        MacOSFilterDecisionScope(rawValue: scopeRawValue) ?? .thisEndpoint
    }

    public init(action: MacOSFilterDecisionAction,
                scope: MacOSFilterDecisionScope,
                rememberDecision: Bool) {
        self.actionRawValue = action.rawValue
        self.scopeRawValue = scope.rawValue
        self.rememberDecision = rememberDecision
        super.init()
    }

    public convenience init?(coder: NSCoder) {
        self.init(
            action: MacOSFilterDecisionAction(rawValue: coder.decodeInteger(forKey: "actionRawValue")) ?? .allow,
            scope: MacOSFilterDecisionScope(rawValue: coder.decodeInteger(forKey: "scopeRawValue")) ?? .thisEndpoint,
            rememberDecision: coder.decodeBool(forKey: "rememberDecision")
        )
    }

    public func encode(with coder: NSCoder) {
        coder.encode(actionRawValue, forKey: "actionRawValue")
        coder.encode(scopeRawValue, forKey: "scopeRawValue")
        coder.encode(rememberDecision, forKey: "rememberDecision")
    }
}

@objc(FilterXPCProtocol)
public protocol FilterXPCProtocol {
    func registerCallback(_ callback: FilterAlertCallbackProtocol, withReply reply: @escaping (Bool) -> Void)
    func rulesChanged(withReply reply: @escaping (Bool) -> Void)
}

@objc(FilterAlertCallbackProtocol)
public protocol FilterAlertCallbackProtocol {
    func showAlert(flowDetails: MacOSFilterFlowDetails, reply: @escaping (MacOSFilterDecision) -> Void)
}

public enum FilterXPCInterfaceFactory {
    public static func extensionInterface() -> NSXPCInterface {
        let interface = NSXPCInterface(with: FilterXPCProtocol.self)
        interface.setInterface(callbackInterface(), for: #selector(FilterXPCProtocol.registerCallback(_:withReply:)), argumentIndex: 0, ofReply: false)
        return interface
    }

    public static func callbackInterface() -> NSXPCInterface {
        return NSXPCInterface(with: FilterAlertCallbackProtocol.self)
    }
}
