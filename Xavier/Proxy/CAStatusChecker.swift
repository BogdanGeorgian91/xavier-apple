import Foundation
import Security

enum CACheckStatus {
    case notInstalled
    case installedButNotTrusted
    case trusted
}

final class CAStatusChecker {
    static func checkTrustStatus() -> CACheckStatus {
        guard let certificate = CertificateManager.shared.loadRootCertificate() else {
            return .notInstalled
        }

        let policy = SecPolicyCreateBasicX509()
        var trust: SecTrust?
        let status = SecTrustCreateWithCertificates(certificate, policy, &trust)
        guard status == errSecSuccess, let builtTrust = trust else {
            return .installedButNotTrusted
        }

        if SecTrustEvaluateWithError(builtTrust, nil) {
            return .trusted
        }

        return .installedButNotTrusted
    }
}
