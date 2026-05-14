import AppKit
import Foundation
import XavierShared

final class FilterXPCClient {
    private var connection: NSXPCConnection?
    private let callback = FilterAlertCallback()

    func connect() {
        let serviceName = "\(Constants.appBundleIdentifier).filter"
        let connection = NSXPCConnection(machServiceName: serviceName, options: .privileged)
        connection.setCodeSigningRequirement("anchor apple generic and identifier \"\(serviceName)\"")
        connection.remoteObjectInterface = FilterXPCInterfaceFactory.extensionInterface()
        connection.exportedInterface = FilterXPCInterfaceFactory.callbackInterface()
        connection.exportedObject = callback
        connection.interruptionHandler = { [weak self] in
            self?.connection = nil
        }
        connection.invalidationHandler = { [weak self] in
            self?.connection = nil
        }
        connection.resume()

        self.connection = connection
        let proxy = connection.remoteObjectProxyWithErrorHandler { error in
            NSLog("[XavierMac] filter XPC connection failed: %@", String(describing: error))
        } as? FilterXPCProtocol
        proxy?.registerCallback(callback) { accepted in
            NSLog("[XavierMac] filter XPC callback registered=%@", String(accepted))
        }
    }
}

private final class FilterAlertCallback: NSObject, FilterAlertCallbackProtocol {
    func showAlert(flowDetails: MacOSFilterFlowDetails, reply: @escaping (MacOSFilterDecision) -> Void) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Allow network connection?"
            alert.informativeText = Self.message(for: flowDetails)
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Allow")
            alert.addButton(withTitle: "Block")

            let response = alert.runModal()
            let action: MacOSFilterDecisionAction = response == .alertFirstButtonReturn ? .allow : .block
            reply(MacOSFilterDecision(action: action, scope: .thisEndpoint, rememberDecision: true))
        }
    }

    private static func message(for details: MacOSFilterFlowDetails) -> String {
        let destination = details.host ?? details.endpointIP ?? "Unknown destination"
        let port = details.port.map { ":\($0)" } ?? ""
        let process = details.signingIdentifier ?? details.displayName
        return "\(process) wants to connect to \(destination)\(port)."
    }
}
