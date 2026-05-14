import UIKit
import XavierShared

final class InspectorSetupViewController: UITableViewController {
    private enum Section: Int, CaseIterable {
        case proxy
        case certificate
        case pinnedDomains
        case proxyApps
    }

    private var pinnedDomains = [String]()
    private var proxyAppBundleIDs = [String]()

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Inspector Setup"
        navigationItem.largeTitleDisplayMode = .never
        tableView.backgroundColor = AppColors.surface.color
        tableView.separatorColor = AppColors.separator.color
        tableView.tableFooterView = UIView(frame: .zero)
        reloadState()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadState()
    }

    private func reloadState() {
        pinnedDomains = (UserDefaults.group?.stringArray(forKey: Constants.ProxyKeys.pinnedDomainsKey) ?? []).sorted()
        proxyAppBundleIDs = configuredProxyAppBundleIDs()
        tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else { return 0 }
        switch section {
        case .proxy:
            return 4
        case .proxyApps:
            return max(proxyAppBundleIDs.count, 1)
        case .certificate:
            return 3
        case .pinnedDomains:
            return pinnedDomains.isEmpty ? 1 : pinnedDomains.count + 1
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let section = Section(rawValue: section) else { return nil }
        switch section {
        case .proxy:
            return "Proxy"
        case .proxyApps:
            return "Proxy Apps"
        case .certificate:
            return "Certificate"
        case .pinnedDomains:
            return "Pinned Domains"
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SetupCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "SetupCell")
        cell.backgroundColor = AppColors.surfaceElevated.color
        cell.tintColor = AppColors.highlight.color
        cell.accessoryType = .none
        cell.accessoryView = nil

        var content = cell.defaultContentConfiguration()
        content.textProperties.font = UIFont(name: "FiraSans-Bold", size: 16) ?? .boldSystemFont(ofSize: 16)
        content.textProperties.color = AppColors.textPrimary.color
        content.secondaryTextProperties.font = UIFont(name: "FiraSans-Regular", size: 13) ?? .systemFont(ofSize: 13)
        content.secondaryTextProperties.color = AppColors.textSecondary.color
        content.secondaryTextProperties.numberOfLines = 2

        switch Section(rawValue: indexPath.section)! {
        case .proxy:
            if indexPath.row == 0 {
                content.text = "Development Mode"
                content.secondaryText = "App Proxy runs automatically for apps in NETestAppMapping plus local mappings."
            } else if indexPath.row == 1 {
                content.text = "HTTPS Inspection"
                content.secondaryText = Constants.isMITMEnabled ? "On. Failed handshakes fall back to passthrough." : "Off. Browser traffic uses passthrough only."
                let toggle = UISwitch()
                toggle.isOn = Constants.isMITMEnabled
                toggle.onTintColor = AppColors.highlight.color
                toggle.addTarget(self, action: #selector(mitmSwitchChanged(_:)), for: .valueChanged)
                cell.accessoryView = toggle
            } else if indexPath.row == 2 {
                content.text = "Show Fallback Flows"
                content.secondaryText = Constants.isShowFallbackFlowsEnabled ? "On. Inspector shows all passthrough and failed MITM flows." : "Off. Inspector hides FLOW entries."
                let toggle = UISwitch()
                toggle.isOn = Constants.isShowFallbackFlowsEnabled
                toggle.onTintColor = AppColors.highlight.color
                toggle.addTarget(self, action: #selector(fallbackSwitchChanged(_:)), for: .valueChanged)
                cell.accessoryView = toggle
            } else {
                content.text = "Export Proxy Profile"
                content.secondaryText = "Share the App-Layer VPN profile needed for App Proxy routing."
                cell.accessoryType = .disclosureIndicator
            }
        case .proxyApps:
            content.secondaryTextProperties.numberOfLines = 0
            if proxyAppBundleIDs.isEmpty {
                content.text = "No proxy apps configured"
                content.secondaryText = "Add private app bundle IDs to Config/NETestAppMapping.local.plist."
            } else {
                content.text = proxyAppBundleIDs[indexPath.row]
                content.secondaryText = "Included in NETestAppMapping."
            }
        case .certificate:
            if indexPath.row == 0 {
                content.text = "Trust Status"
                content.secondaryText = trustStatusText(CAStatusChecker.checkTrustStatus())
            } else if indexPath.row == 1 {
                content.text = "Generate Certificate"
                content.secondaryText = "Creates the local Xavier Inspector CA in the shared keychain."
                cell.accessoryType = .disclosureIndicator
            } else {
                content.text = "Export Certificate Profile"
                content.secondaryText = "Share the .mobileconfig needed for certificate installation."
                cell.accessoryType = .disclosureIndicator
            }
        case .pinnedDomains:
            if pinnedDomains.isEmpty {
                content.text = "No pinned domains detected"
                content.secondaryText = "Domains appear here when certificate pinning prevents safe HTTPS inspection."
            } else if indexPath.row == 0 {
                content.text = "About pinned domains"
                content.secondaryText = "Xavier skips HTTPS inspection for these hosts to avoid breaking pinned apps."
            } else {
                content.text = pinnedDomains[indexPath.row - 1]
                content.secondaryText = "MITM is skipped for this host."
            }
        }

        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch Section(rawValue: indexPath.section)! {
        case .proxy:
            if indexPath.row == 3 {
                exportProxyProfile()
            }
        case .proxyApps:
            break
        case .certificate:
            if indexPath.row == 1 {
                generateCertificate()
            } else if indexPath.row == 2 {
                exportProfile()
            }
        case .pinnedDomains:
            break
        }
    }

    @objc private func mitmSwitchChanged(_ sender: UISwitch) {
        Constants.setMITMEnabled(sender.isOn)
        reloadState()
    }

    @objc private func fallbackSwitchChanged(_ sender: UISwitch) {
        Constants.setShowFallbackFlowsEnabled(sender.isOn)
        reloadState()
    }

    private func toggleProxy() {
        ProxyManager.shared.loadConfiguration { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                self.showError(title: "Unable to Load Proxy", error: error, fallbackMessage: "Xavier couldn't load the proxy configuration.")
                return
            }

            let completion: (Error?) -> Void = { saveError in
                if let saveError = saveError {
                    self.showError(title: "Proxy Update Failed", error: saveError, fallbackMessage: "Xavier couldn't update the proxy configuration.")
                    return
                }
                self.showSuccess(message: ProxyManager.shared.isEnabled ? "Proxy enabled." : "Proxy disabled.")
                self.reloadState()
            }

            if ProxyManager.shared.isEnabled {
                ProxyManager.shared.disable(completion: completion)
            } else {
                ProxyManager.shared.enable(completion: completion)
            }
        }
    }

    private func generateCertificate() {
        do {
            try CertificateManager.shared.createRootCA()
            showSuccess(message: "Certificate created.")
            reloadState()
        } catch {
            showError(title: "Certificate Error", error: error, fallbackMessage: "Xavier couldn't create the certificate.")
        }
    }

    private func exportProxyProfile() {
        let data = CertificateExportHelper.exportProxyMobileConfig()
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("XavierProxy.mobileconfig")
        do {
            try data.write(to: url, options: .atomic)
            let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            if let popover = controller.popoverPresentationController {
                popover.sourceView = self.view
                popover.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            present(controller, animated: true, completion: nil)
        } catch {
            showError(title: "Export Failed", error: error, fallbackMessage: "Xavier couldn't export the proxy profile.")
        }
    }


    private func exportProfile() {
        do {
            let data = try CertificateExportHelper.exportAsMobileConfig()
            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("XavierInspector.mobileconfig")
            try data.write(to: url, options: .atomic)
            let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            if let popover = controller.popoverPresentationController {
                popover.sourceView = self.view
                popover.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            present(controller, animated: true, completion: nil)
        } catch {
            showError(title: "Export Failed", error: error, fallbackMessage: "Xavier couldn't export the certificate profile.")
        }
    }

    private func trustStatusText(_ status: CACheckStatus) -> String {
        switch status {
        case .notInstalled: return "Not installed"
        case .installedButNotTrusted: return "Installed but not trusted"
        case .trusted: return "Trusted"
        }
    }

    private func configuredProxyAppBundleIDs() -> [String] {
        guard let mapping = Bundle.main.object(forInfoDictionaryKey: "NETestAppMapping") as? [String: Any] else {
            return []
        }

        let bundleIDs = mapping.values.compactMap { $0 as? [String] }.flatMap { $0 }
        return Array(Set(bundleIDs)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
