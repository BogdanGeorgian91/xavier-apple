import Foundation
import XavierShared

final class CertificateExportHelper {
    static func exportAsDER() throws -> Data {
        return try CertificateManager.shared.exportRootCA()
    }

    static func exportAsMobileConfig(profileIdentifier: String? = nil) throws -> Data {
        let profileIdentifier = profileIdentifier ?? Constants.appBundleIdentifier + ".rootCA"
        let certificateData = try exportAsDER()
        let certificateBase64 = certificateData.base64EncodedString(options: [.lineLength64Characters])
        let payloadUUID = UUID().uuidString
        let certPayloadUUID = UUID().uuidString

        let plist = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>PayloadContent</key>
	<array>
		<dict>
			<key>PayloadCertificateFileName</key>
			<string>XavierInspectorCA.cer</string>
			<key>PayloadContent</key>
			<data>
			\(certificateBase64)
			</data>
			<key>PayloadDescription</key>
			<string>Installs the Xavier Inspector certificate authority.</string>
			<key>PayloadDisplayName</key>
			<string>Xavier Inspector CA</string>
			<key>PayloadIdentifier</key>
			<string>\(profileIdentifier).certificate</string>
			<key>PayloadOrganization</key>
			<string>Xavier</string>
			<key>PayloadType</key>
			<string>com.apple.security.root</string>
			<key>PayloadUUID</key>
			<string>\(certPayloadUUID)</string>
			<key>PayloadVersion</key>
			<integer>1</integer>
		</dict>
	</array>
	<key>PayloadDisplayName</key>
	<string>Xavier Inspector Certificate</string>
	<key>PayloadIdentifier</key>
	<string>\(profileIdentifier)</string>
	<key>PayloadOrganization</key>
	<string>Xavier</string>
	<key>PayloadRemovalDisallowed</key>
	<false/>
	<key>PayloadType</key>
	<string>Configuration</string>
	<key>PayloadUUID</key>
	<string>\(payloadUUID)</string>
	<key>PayloadVersion</key>
	<integer>1</integer>
</dict>
</plist>
"""

        return plist.data(using: .utf8) ?? Data()
    }

    static func exportProxyMobileConfig(appBundleIdentifier: String = Constants.appBundleIdentifier,
                                        proxyBundleIdentifier: String = Constants.appBundleIdentifier + ".XavierProxy") -> Data {
        let payloadUUID = "BB223482-C47E-4326-9633-31C8D2BAE8B9"
        let appProxyUUID = Constants.appProxyUUID

        let plist = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>PayloadContent</key>
	<array>
		<dict>
			<key>PayloadDescription</key>
			<string>Configures Xavier App Proxy.</string>
			<key>PayloadDisplayName</key>
			<string>Xavier App Proxy</string>
			<key>PayloadIdentifier</key>
			<string>com.apple.vpn.managed.applayer.\(appProxyUUID)</string>
			<key>PayloadType</key>
			<string>com.apple.vpn.managed.applayer</string>
			<key>PayloadUUID</key>
			<string>\(appProxyUUID)</string>
			<key>PayloadVersion</key>
			<integer>1</integer>
			<key>Proxies</key>
			<dict>
				<key>HTTPEnable</key>
				<integer>0</integer>
				<key>HTTPSEnable</key>
				<integer>0</integer>
			</dict>
			<key>UserDefinedName</key>
			<string>Xavier Proxy</string>
			<key>VPN</key>
			<dict>
				<key>AuthenticationMethod</key>
				<string>Password</string>
				<key>OnDemandEnabled</key>
				<integer>1</integer>
				<key>ProviderBundleIdentifier</key>
				<string>\(proxyBundleIdentifier)</string>
				<key>ProviderType</key>
				<string>app-proxy</string>
				<key>RemoteAddress</key>
				<string>127.0.0.1</string>
			</dict>
			<key>VPNSubType</key>
			<string>\(appBundleIdentifier)</string>
			<key>VPNType</key>
			<string>VPN</string>
			<key>VPNUUID</key>
			<string>\(appProxyUUID)</string>
			<key>OnDemandMatchAppEnabled</key>
			<true/>
		</dict>
	</array>
	<key>PayloadDisplayName</key>
	<string>Xavier Proxy Configuration</string>
	<key>PayloadIdentifier</key>
	<string>\(appBundleIdentifier).proxyconfig</string>
	<key>PayloadOrganization</key>
	<string>Xavier</string>
	<key>PayloadRemovalDisallowed</key>
	<false/>
	<key>PayloadType</key>
	<string>Configuration</string>
	<key>PayloadUUID</key>
	<string>\(payloadUUID)</string>
	<key>PayloadVersion</key>
	<integer>1</integer>
</dict>
</plist>
"""
        return plist.data(using: .utf8) ?? Data()
    }
}
