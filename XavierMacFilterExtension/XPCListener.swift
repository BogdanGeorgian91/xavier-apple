import Foundation
import Security
import XavierShared

final class FilterXPCListener: NSObject, NSXPCListenerDelegate, FilterXPCProtocol {
    static let shared = FilterXPCListener()

    private var listener: NSXPCListener?
    private var callback: FilterAlertCallbackProtocol?
    var ruleReloadHandler: (() -> Void)?

    var hasConnectedClient: Bool {
        callback != nil
    }

    func start() {
        guard listener == nil else { return }
        let serviceName = "\(Constants.appBundleIdentifier).filter"
        let listener = NSXPCListener(machServiceName: serviceName)
        listener.delegate = self
        listener.resume()
        self.listener = listener
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        guard validateClient(newConnection) else {
            return false
        }

        newConnection.exportedInterface = FilterXPCInterfaceFactory.extensionInterface()
        newConnection.exportedObject = self
        newConnection.remoteObjectInterface = FilterXPCInterfaceFactory.callbackInterface()
        newConnection.invalidationHandler = { [weak self] in
            self?.callback = nil
        }
        newConnection.interruptionHandler = { [weak self] in
            self?.callback = nil
        }
        newConnection.resume()
        return true
    }

    func registerCallback(_ callback: FilterAlertCallbackProtocol, withReply reply: @escaping (Bool) -> Void) {
        self.callback = callback
        reply(true)
    }

    func rulesChanged(withReply reply: @escaping (Bool) -> Void) {
        ruleReloadHandler?()
        reply(true)
    }

    func showAlert(flowDetails: MacOSFilterFlowDetails, reply: @escaping (MacOSFilterDecision) -> Void) -> Bool {
        guard let callback else {
            return false
        }
        callback.showAlert(flowDetails: flowDetails, reply: reply)
        return true
    }

    private func validateClient(_ connection: NSXPCConnection) -> Bool {
        guard connection.processIdentifier > 0,
              let path = executablePath(for: connection.processIdentifier) else {
            return false
        }

        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &staticCode)
        guard createStatus == errSecSuccess, let staticCode else {
            return false
        }

        guard SecStaticCodeCheckValidity(staticCode, [], nil) == errSecSuccess else {
            return false
        }

        var info: CFDictionary?
        SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        let signingIdentifier = (info as? [String: Any])?[kSecCodeInfoIdentifier as String] as? String
        return signingIdentifier == Constants.appBundleIdentifier
    }

    private func executablePath(for pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let result = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard result > 0 else { return nil }
        return String(cString: buffer)
    }
}
