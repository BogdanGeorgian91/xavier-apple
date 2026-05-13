import Foundation
import Security
import X509

final class CertificateManager {
    static let shared = CertificateManager()

    private let rootCAKeyTag = "\(Constants.appBundleIdentifier).rootCA.privateKey"
    private let rootCACertTag = "\(Constants.appBundleIdentifier).rootCA.certificate"
    private let rootCAStoreService = "\(Constants.appBundleIdentifier).certificateStore"
    private let keychainAccessGroup = Constants.sharedKeychainAccessGroup

    private var leafCache = [String: (identity: SecIdentity, certificate: SecCertificate, expires: Date)]()
    private let leafCacheMaxSize = 50
    private let leafCacheValidity: TimeInterval = 3600
    private var pinnedDomains = Set<String>()
    private let knownPinnedDomains = Set<String>()

    private init() {}

    var isRootCACreated: Bool {
        return loadRootCertificate() != nil && loadRootPrivateKey() != nil
    }

    var rootCAPublicKeyData: Data? {
        guard let certificate = loadRootCertificate() else { return nil }
        return SecCertificateCopyData(certificate) as Data
    }

    func createRootCA() throws {
        if isRootCACreated {
            return
        }

        try deleteRootCA()

        var error: Unmanaged<CFError>?
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: rootCAKeyTag.data(using: .utf8)!,
                kSecAttrAccessGroup as String: keychainAccessGroup,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]
        ]

        guard let rootKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw error?.takeRetainedValue() ?? CertificateManagerError.keyGenerationFailed
        }

        let subject = try distinguishedName(commonName: "Xavier Inspector CA", organization: "Xavier")
        var extensions = Certificate.Extensions()
        try extensions.append(Certificate.Extension(BasicConstraints.isCertificateAuthority(maxPathLength: nil), critical: true))
        try extensions.append(Certificate.Extension(KeyUsage(keyCertSign: true, cRLSign: true), critical: true))

        let rootPrivateKey = try Certificate.PrivateKey(rootKey)
        let now = Date()
        let certificate = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: rootPrivateKey.publicKey,
            notValidBefore: now.addingTimeInterval(-300),
            notValidAfter: now.addingTimeInterval(60 * 60 * 24 * 3650),
            issuer: subject,
            subject: subject,
            signatureAlgorithm: .sha256WithRSAEncryption,
            extensions: extensions,
            issuerPrivateKey: rootPrivateKey
        )

        let secCertificate = try SecCertificate.makeWithCertificate(certificate)
        let certificateData = SecCertificateCopyData(secCertificate) as Data
        try storeCertificateData(certificateData, account: rootCACertTag)
    }

    func generateLeafCertificate(for hostname: String) throws -> (SecIdentity, SecCertificate) {
        if let cached = leafCache[hostname], cached.expires > Date() {
            return (cached.identity, cached.certificate)
        }

        guard let rootKey = loadRootPrivateKey(),
              let rootCertificate = loadRootCertificate() else {
            throw CertificateManagerError.rootCANotAvailable
        }

        let leafTag = "\(Constants.appBundleIdentifier).leaf.\(hostname)"
        try deleteLeafMaterial(hostname: hostname)

        var error: Unmanaged<CFError>?
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: leafTag.data(using: .utf8)!,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]
        ]

        guard let leafKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw error?.takeRetainedValue() ?? CertificateManagerError.keyGenerationFailed
        }

        let issuerCertificate = try Certificate(rootCertificate)
        let subject = try distinguishedName(commonName: hostname, organization: nil)
        var extensions = Certificate.Extensions()
        try extensions.append(Certificate.Extension(BasicConstraints.notCertificateAuthority, critical: true))
        try extensions.append(Certificate.Extension(KeyUsage(digitalSignature: true, keyEncipherment: true), critical: true))
        try extensions.append(Certificate.Extension(ExtendedKeyUsage([.serverAuth]), critical: false))
        try extensions.append(Certificate.Extension(SubjectAlternativeNames([.dnsName(hostname)]), critical: false))

        let issuerPrivateKey = try Certificate.PrivateKey(rootKey)
        let leafPrivateKey = try Certificate.PrivateKey(leafKey)
        let now = Date()
        let certificate = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: leafPrivateKey.publicKey,
            notValidBefore: now.addingTimeInterval(-300),
            notValidAfter: now.addingTimeInterval(60 * 60 * 24),
            issuer: issuerCertificate.subject,
            subject: subject,
            signatureAlgorithm: .sha256WithRSAEncryption,
            extensions: extensions,
            issuerPrivateKey: issuerPrivateKey
        )

        let secCertificate = try SecCertificate.makeWithCertificate(certificate)
        try storeLeafCertificate(secCertificate, hostname: hostname)

        guard let identity = SecIdentityCreate(nil, secCertificate, leafKey) else {
            throw CertificateManagerError.identityCreationFailed(errSecAllocate)
        }

        leafCache[hostname] = (identity, secCertificate, now.addingTimeInterval(leafCacheValidity))
        trimLeafCacheIfNeeded()
        return (identity, secCertificate)
    }

    func exportRootCA() throws -> Data {
        guard let data = rootCAPublicKeyData else {
            throw CertificateManagerError.rootCANotAvailable
        }
        return data
    }

    func deleteRootCA() throws {
        leafCache.removeAll()

        SecItemDelete([
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: rootCAKeyTag.data(using: .utf8)!,
            kSecAttrAccessGroup as String: keychainAccessGroup
        ] as CFDictionary)

        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: rootCACertTag,
            kSecAttrService as String: rootCAStoreService,
            kSecAttrAccessGroup as String: keychainAccessGroup
        ] as CFDictionary)
    }

    func isPinnedDomain(_ hostname: String) -> Bool {
        return knownPinnedDomains.contains(hostname) || pinnedDomains.contains(hostname)
    }

    func markAsPinned(_ hostname: String) {
        pinnedDomains.insert(hostname)
        var persisted = UserDefaults.group?.stringArray(forKey: Constants.ProxyKeys.pinnedDomainsKey) ?? []
        if !persisted.contains(hostname) {
            persisted.append(hostname)
            UserDefaults.group?.set(persisted, forKey: Constants.ProxyKeys.pinnedDomainsKey)
        }
    }

    func loadRootCertificate() -> SecCertificate? {
        guard let data = loadCertificateData(account: rootCACertTag) else {
            return nil
        }
        return SecCertificateCreateWithData(nil, data as CFData)
    }

    private func loadRootPrivateKey() -> SecKey? {
        var item: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: rootCAKeyTag.data(using: .utf8)!,
            kSecAttrAccessGroup as String: keychainAccessGroup,
            kSecReturnRef as String: true
        ] as CFDictionary, &item)

        guard status == errSecSuccess else { return nil }
        return (item as! SecKey)
    }

    private func storeCertificateData(_ data: Data, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: rootCAStoreService,
            kSecAttrAccessGroup as String: keychainAccessGroup
        ]
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CertificateManagerError.keychainOperationFailed(status)
        }
    }

    private func loadCertificateData(account: String) -> Data? {
        var item: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: rootCAStoreService,
            kSecAttrAccessGroup as String: keychainAccessGroup,
            kSecReturnData as String: true
        ] as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    private func storeLeafCertificate(_ certificate: SecCertificate, hostname: String) throws {
        let label = "\(Constants.appBundleIdentifier).leafcert.\(hostname)"
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: label
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let status = SecItemAdd([
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: label,
            kSecValueRef as String: certificate
        ] as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CertificateManagerError.keychainOperationFailed(status)
        }
    }

    private func deleteLeafMaterial(hostname: String) throws {
        let keyTag = "\(Constants.appBundleIdentifier).leaf.\(hostname)"
        let certLabel = "\(Constants.appBundleIdentifier).leafcert.\(hostname)"

        SecItemDelete([
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag.data(using: .utf8)!
        ] as CFDictionary)

        SecItemDelete([
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: certLabel
        ] as CFDictionary)
    }

    private func trimLeafCacheIfNeeded() {
        if leafCache.count <= leafCacheMaxSize { return }
        let sorted = leafCache.sorted { $0.value.expires < $1.value.expires }
        if let oldest = sorted.first {
            leafCache.removeValue(forKey: oldest.key)
        }
    }

    private func distinguishedName(commonName: String, organization: String?) throws -> DistinguishedName {
        var attributes = [RelativeDistinguishedName.Attribute]()
        if let organization = organization {
            attributes.append(try RelativeDistinguishedName.Attribute(type: .RDNAttributeType.organizationName, printableString: organization))
        }
        attributes.append(try RelativeDistinguishedName.Attribute(type: .RDNAttributeType.commonName, printableString: commonName))
        return try DistinguishedName(attributes)
    }
}

enum CertificateManagerError: Error {
    case keyGenerationFailed
    case rootCANotAvailable
    case identityCreationFailed(OSStatus)
    case keychainOperationFailed(OSStatus)
}
