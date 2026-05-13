import UIKit

final class ModificationRulesViewController: UITableViewController {
    private var rules = [ModificationRule]()

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Modification Rules"
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addRule))
        tableView.backgroundColor = AppColors.surface.color
        tableView.separatorColor = AppColors.separator.color
        tableView.tableFooterView = UIView(frame: .zero)
        reloadRules()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadRules()
    }

    private func reloadRules() {
        rules = ModificationRuleManager.shared.fetchAllRules().sorted { $0.host < $1.host }
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return max(rules.count, 1)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ModRuleCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "ModRuleCell")
        cell.backgroundColor = AppColors.surfaceElevated.color
        cell.selectionStyle = .none

        var content = cell.defaultContentConfiguration()
        content.textProperties.font = UIFont(name: "FiraSans-Bold", size: 16) ?? .boldSystemFont(ofSize: 16)
        content.textProperties.color = AppColors.textPrimary.color
        content.secondaryTextProperties.font = UIFont(name: "FiraSans-Regular", size: 13) ?? .systemFont(ofSize: 13)
        content.secondaryTextProperties.color = AppColors.textSecondary.color

        guard !rules.isEmpty else {
            content.text = "No modification rules"
            content.secondaryText = "Add rules to modify request headers, URLs, or body content."
            cell.contentConfiguration = content
            return cell
        }

        let rule = rules[indexPath.row]
        content.text = "\(rule.type.rawValue) — \(rule.host)"
        content.secondaryText = ruleDescription(for: rule)

        let toggle = UISwitch()
        toggle.isOn = rule.enabled
        toggle.onTintColor = AppColors.highlight.color
        toggle.tag = indexPath.row
        toggle.addTarget(self, action: #selector(toggleChanged(_:)), for: .valueChanged)
        cell.accessoryView = toggle
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        guard !rules.isEmpty else { return false }
        return true
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete, !rules.isEmpty else { return }
        ModificationRuleManager.shared.removeRule(id: rules[indexPath.row].identifier)
        reloadRules()
    }

    private func ruleDescription(for rule: ModificationRule) -> String {
        switch rule.type {
        case .addHeader:
            return "Add \(rule.matchPattern ?? ""): \(rule.replacementValue ?? "")"
        case .removeHeader:
            return "Remove header \(rule.matchPattern ?? "")"
        case .replaceHeader:
            return "Replace \(rule.matchPattern ?? "") with \(rule.replacementValue ?? "")"
        case .rewriteURL:
            return "Rewrite URLs matching \(rule.matchPattern ?? "")"
        case .replaceBody:
            return "Replace \(rule.matchPattern ?? "") in request body"
        }
    }

    @objc private func toggleChanged(_ sender: UISwitch) {
        guard sender.tag < rules.count else { return }
        let rule = rules[sender.tag]
        ModificationRuleManager.shared.updateRule(id: rule.identifier, enabled: sender.isOn)
        reloadRules()
    }

    @objc private func addRule() {
        let alert = UIAlertController(title: "Add Modification Rule", message: nil, preferredStyle: .alert)

        alert.addTextField { field in field.placeholder = "Host (* for all)" }
        alert.addTextField { field in field.placeholder = "Type (addHeader, removeHeader, etc.)" }
        alert.addTextField { field in field.placeholder = "Match pattern" }
        alert.addTextField { field in field.placeholder = "Replacement value" }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Add", style: .default, handler: { _ in
            guard let host = alert.textFields?[0].text?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty else { return }
            let typeString = alert.textFields?[1].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "addHeader"
            let pattern = alert.textFields?[2].text?.trimmingCharacters(in: .whitespacesAndNewlines)
            let replacement = alert.textFields?[3].text?.trimmingCharacters(in: .whitespacesAndNewlines)

            guard let type = ModificationType(rawValue: typeString) else { return }

            let rule = ModificationRule(
                identifier: UUID(),
                host: host.lowercased(),
                type: type,
                matchPattern: pattern,
                replacementValue: replacement,
                enabled: true
            )
            ModificationRuleManager.shared.addRule(rule)
            self.reloadRules()
        }))

        present(alert, animated: true, completion: nil)
    }
}