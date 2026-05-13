import Foundation
import NetworkExtension

final class ProxyManager {
    static let shared = ProxyManager()

    private var manager: NEAppProxyProviderManager?

    var isEnabled: Bool {
        return manager?.isEnabled ?? false
    }

    func loadConfiguration(completion: @escaping (Error?) -> Void) {
        NEAppProxyProviderManager.loadAllFromPreferences { [weak self] managers, error in
            if let error = error {
                DispatchQueue.main.async { completion(error) }
                return
            }

            self?.manager = managers?.first
            
            // For development with NETestAppMapping, we don't need a manager to exist.
            // iOS creates a hidden one automatically.
            DispatchQueue.main.async { completion(nil) }
        }
    }

    func enable(completion: @escaping (Error?) -> Void) {
        // Development bypass: Since we cannot call saveToPreferences for an App Proxy
        // without MDM, we simulate success here. The actual proxy is triggered by
        // NETestAppMapping in Info.plist when the target apps (e.g. Safari) launch.
        DispatchQueue.main.async { completion(nil) }
    }

    func disable(completion: @escaping (Error?) -> Void) {
        // Development bypass
        DispatchQueue.main.async { completion(nil) }
    }

    var vpnConfigurationUUID: String? {
        return manager?.localizedDescription
    }
}

enum ProxyError: LocalizedError {
    case noConfiguration
    case notInstalled
    case notTrusted

    var errorDescription: String? {
        switch self {
        case .noConfiguration:
            return "No VPN configuration found. Install the Xavier VPN profile."
        case .notInstalled:
            return "Root CA certificate not installed."
        case .notTrusted:
            return "Root CA certificate installed but not trusted. Enable trust in Settings."
        }
    }
}
