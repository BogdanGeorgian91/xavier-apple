import UIKit

final class StripScriptsViewController: UITableViewController {
    private var hosts = [ScriptStrippingHost]()

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Strip Scripts"
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addHost))
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72
        tableView.backgroundColor = AppColors.surface.color
        tableView.separatorColor = AppColors.separator.color
        tableView.tableFooterView = UIView(frame: .zero)
        reloadEntries()
    }

    private func reloadEntries() {
        hosts = ScriptStrippingManager.shared.fetchAllHosts().sorted { $0.host < $1.host }
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return "Script stripping modifies HTML responses only for hosts you enable. Use *. to match subdomains (e.g. *.example.com matches www.example.com). Keep rules always win to protect scripts needed for page functionality."
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return max(hosts.count, 1)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "StripScriptsCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "StripScriptsCell")
        cell.backgroundColor = AppColors.surfaceElevated.color
        cell.selectionStyle = .default

        var content = cell.defaultContentConfiguration()
        content.textProperties.font = UIFont(name: "FiraSans-Bold", size: 16) ?? .boldSystemFont(ofSize: 16)
        content.textProperties.color = AppColors.textPrimary.color
        content.secondaryTextProperties.font = UIFont(name: "FiraSans-Regular", size: 13) ?? .systemFont(ofSize: 13)
        content.secondaryTextProperties.color = AppColors.textSecondary.color

        guard !hosts.isEmpty else {
            content.text = "No strip-script hosts"
            content.secondaryText = "Add a site where Xavier may rewrite HTML and manage script rules."
            cell.selectionStyle = .none
            cell.contentConfiguration = content
            return cell
        }

        let host = hosts[indexPath.row]
        let keepCount = host.rules.filter { $0.action == .keep }.count
        let removeCount = host.rules.filter { $0.action == .remove }.count
        content.text = host.host
        content.secondaryText = "\(host.mode.title) • \(keepCount) keep rule\(keepCount == 1 ? "" : "s") • \(removeCount) remove rule\(removeCount == 1 ? "" : "s")\nTap to manage rules"
        content.secondaryTextProperties.numberOfLines = 0
        cell.contentConfiguration = content

        let toggle = UISwitch()
        toggle.isOn = host.enabled
        toggle.onTintColor = AppColors.highlight.color
        toggle.tag = indexPath.row
        toggle.addTarget(self, action: #selector(toggleChanged(_:)), for: .valueChanged)
        cell.accessoryView = toggle
        return cell
    }

    @objc private func toggleChanged(_ sender: UISwitch) {
        let host = hosts[sender.tag]
        ScriptStrippingManager.shared.setEnabled(sender.isOn, forHost: host.host)
        reloadEntries()
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !hosts.isEmpty else { return }
        navigationController?.pushViewController(ScriptStrippingHostDetailViewController(host: hosts[indexPath.row].host), animated: true)
    }

    @objc private func addHost() {
        let alert = UIAlertController(title: "Add Site", message: "Enter the host where HTML script stripping should be enabled. Use *. to match subdomains (e.g. *.example.com).", preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "*.example.com"
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Add", style: .default, handler: { _ in
            guard let host = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty else { return }
            ScriptStrippingManager.shared.upsertHost(host.lowercased())
            self.reloadEntries()
        }))
        present(alert, animated: true, completion: nil)
    }
}

final class ScriptStrippingHostDetailViewController: UITableViewController {
    private enum Section: Int, CaseIterable {
        case mode
        case keepRules
        case removeRules
    }

    private let host: String
    private var configuration: ScriptStrippingHost?

    init(host: String) {
        self.host = host
        super.init(style: .insetGrouped)
    }

    required init?(coder aDecoder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = host
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addRule))
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 88
        tableView.backgroundColor = AppColors.surface.color
        tableView.separatorColor = AppColors.separator.color
        tableView.tableFooterView = UIView(frame: .zero)
        reloadConfiguration()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadConfiguration()
    }

    private func reloadConfiguration() {
        configuration = ScriptStrippingManager.shared.fetchAllHosts().first { $0.host == host }
        tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else { return 0 }
        switch section {
        case .mode:
            return 2
        case .keepRules:
            return max(rules(action: .keep).count, 1)
        case .removeRules:
            guard configuration?.mode == .fineGrained else { return 0 }
            return max(rules(action: .remove).count, 1)
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let section = Section(rawValue: section) else { return nil }
        switch section {
        case .mode: return "Mode"
        case .keepRules: return "Keep Rules"
        case .removeRules: return "Remove Rules"
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard let section = Section(rawValue: section) else { return nil }
        switch section {
        case .mode:
            return "Smart Allowlist removes scripts from blocked domains unless a keep rule matches. Fine-Grained mode removes only scripts matching remove rules."
        case .keepRules:
            return "Keep rules override removals and protect scripts needed for sign-in, checkout, payments, or site functionality."
        case .removeRules:
            return configuration?.mode == .fineGrained ? "Remove rules are used only in Fine-Grained mode." : nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ScriptRuleCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "ScriptRuleCell")
        cell.backgroundColor = AppColors.surfaceElevated.color
        cell.selectionStyle = .none
        cell.accessoryView = nil

        var content = cell.defaultContentConfiguration()
        content.textProperties.font = UIFont(name: "FiraSans-Bold", size: 16) ?? .boldSystemFont(ofSize: 16)
        content.textProperties.color = AppColors.textPrimary.color
        content.secondaryTextProperties.font = UIFont(name: "FiraSans-Regular", size: 13) ?? .systemFont(ofSize: 13)
        content.secondaryTextProperties.color = AppColors.textSecondary.color
        content.secondaryTextProperties.numberOfLines = 0

        guard let section = Section(rawValue: indexPath.section), let configuration = configuration else {
            cell.contentConfiguration = content
            return cell
        }

        switch section {
        case .mode:
            if indexPath.row == 0 {
                content.text = configuration.mode.title
                content.secondaryText = configuration.mode == .smartAllowlist ? "Blocklist-driven removal with keep-rule overrides." : "Explicit keep and remove rules for this host."
            } else {
                return makeModeControlCell(configuration: configuration)
            }
        case .keepRules:
            configureRuleCell(cell, content: &content, rule: rules(action: .keep).safeValue(at: indexPath.row), emptyTitle: "No keep rules", emptySubtitle: "Add patterns for scripts that must stay on the page.")
        case .removeRules:
            configureRuleCell(cell, content: &content, rule: rules(action: .remove).safeValue(at: indexPath.row), emptyTitle: "No remove rules", emptySubtitle: "Add patterns for scripts to remove in Fine-Grained mode.")
        }

        cell.contentConfiguration = content
        return cell
    }

    private func makeModeControlCell(configuration: ScriptStrippingHost) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.backgroundColor = AppColors.surfaceElevated.color
        cell.selectionStyle = .none

        let control = UISegmentedControl(items: [ScriptStrippingMode.smartAllowlist.title, ScriptStrippingMode.fineGrained.title])
        control.selectedSegmentIndex = configuration.mode == .smartAllowlist ? 0 : 1
        control.addTarget(self, action: #selector(modeChanged(_:)), for: .valueChanged)
        control.translatesAutoresizingMaskIntoConstraints = false

        cell.contentView.addSubview(control)
        NSLayoutConstraint.activate([
            control.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
            control.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
            control.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 10),
            control.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -10)
        ])

        return cell
    }

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        guard let section = Section(rawValue: indexPath.section) else { return false }
        switch section {
        case .mode:
            return false
        case .keepRules:
            return rules(action: .keep).safeValue(at: indexPath.row) != nil
        case .removeRules:
            return rules(action: .remove).safeValue(at: indexPath.row) != nil
        }
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete, let section = Section(rawValue: indexPath.section) else { return }
        let action: ScriptRuleAction = section == .keepRules ? .keep : .remove
        guard let rule = rules(action: action).safeValue(at: indexPath.row) else { return }
        ScriptStrippingManager.shared.removeRule(identifier: rule.identifier, fromHost: host)
        reloadConfiguration()
    }

    private func configureRuleCell(_ cell: UITableViewCell, content: inout UIListContentConfiguration, rule: ScriptRule?, emptyTitle: String, emptySubtitle: String) {
        guard let rule = rule else {
            content.text = emptyTitle
            content.secondaryText = emptySubtitle
            return
        }

        content.text = rule.pattern
        content.secondaryText = rule.matchType.title
        let toggle = UISwitch()
        toggle.isOn = rule.enabled
        toggle.onTintColor = AppColors.highlight.color
        toggle.accessibilityIdentifier = rule.identifier
        toggle.addTarget(self, action: #selector(ruleToggleChanged(_:)), for: .valueChanged)
        cell.accessoryView = toggle
    }

    private func rules(action: ScriptRuleAction) -> [ScriptRule] {
        return (configuration?.rules ?? [])
            .filter { $0.action == action }
            .sorted { $0.pattern.localizedCaseInsensitiveCompare($1.pattern) == .orderedAscending }
    }

    @objc private func modeChanged(_ sender: UISegmentedControl) {
        let mode: ScriptStrippingMode = sender.selectedSegmentIndex == 0 ? .smartAllowlist : .fineGrained
        ScriptStrippingManager.shared.setMode(mode, forHost: host)
        reloadConfiguration()
    }

    @objc private func ruleToggleChanged(_ sender: UISwitch) {
        guard let identifier = sender.accessibilityIdentifier else { return }
        ScriptStrippingManager.shared.setRuleEnabled(sender.isOn, identifier: identifier, forHost: host)
        reloadConfiguration()
    }

    @objc private func addRule() {
        let sheet = UIAlertController(title: "Add Script Rule", message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Keep Rule", style: .default) { _ in
            self.presentRuleEditor(action: .keep)
        })
        if configuration?.mode == .fineGrained {
            sheet.addAction(UIAlertAction(title: "Remove Rule", style: .default) { _ in
                self.presentRuleEditor(action: .remove)
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        if let popover = sheet.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItem
        }
        present(sheet, animated: true)
    }

    private func presentRuleEditor(action: ScriptRuleAction) {
        let sheet = UIAlertController(title: "Choose Match Type", message: nil, preferredStyle: .actionSheet)
        [ScriptRuleMatchType.srcContains, .srcHostMatches, .inlineContains].forEach { matchType in
            sheet.addAction(UIAlertAction(title: matchType.title, style: .default) { _ in
                self.presentPatternEditor(action: action, matchType: matchType)
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        if let popover = sheet.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItem
        }
        present(sheet, animated: true)
    }

    private func presentPatternEditor(action: ScriptRuleAction, matchType: ScriptRuleMatchType) {
        let alert = UIAlertController(title: "Add \(action.title) Rule", message: matchType.title, preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "Pattern, e.g. stripe or doubleclick.net"
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Add", style: .default) { _ in
            let pattern = alert.textFields?[0].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !pattern.isEmpty else { return }

            let now = Date()
            let rule = ScriptRule(identifier: UUID().uuidString,
                                  action: action,
                                  matchType: matchType,
                                  pattern: pattern.lowercased(),
                                  enabled: true,
                                  createdAt: now,
                                  updatedAt: now)
            ScriptStrippingManager.shared.addRule(rule, toHost: self.host)
            self.reloadConfiguration()
        })
        present(alert, animated: true)
    }
}

private extension Array {
    func safeValue(at index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
