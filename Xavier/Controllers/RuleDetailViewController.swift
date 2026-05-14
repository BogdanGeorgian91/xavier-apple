import UIKit
import XavierShared

protocol RuleDetailDelegate: AnyObject {
    func ruleDidUpdate()
}

class RuleDetailViewController: UITableViewController {
    private var rule: Rule
    private weak var delegate: RuleDetailDelegate?
    
    init(rule: Rule, delegate: RuleDetailDelegate?) {
        self.rule = rule
        self.delegate = delegate
        super.init(style: .insetGrouped)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
                switch rule.ruleType {
        case .app(let app):
            title = app.commonName.capitalized
        case .host(let host):
            title = host
        case .hostFromApp(let host, _):
            title = host
        }
        
        tableView.backgroundColor = AppColors.surface.color
        navigationItem.largeTitleDisplayMode = .never
        tableView.separatorColor = AppColors.separator.color

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "ActionCell")
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 3
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "Rule Details"
        case 1: return "Status"
        case 2: return "Danger Zone"
        default: return nil
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
                if indexPath.section == 2 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "ActionCell", for: indexPath)
            var content = cell.defaultContentConfiguration()
            content.text = "Delete Rule"
            content.textProperties.color = AppColors.deny.color
            content.textProperties.font = UIFont(name: "FiraSans-Bold", size: 16) ?? UIFont.boldSystemFont(ofSize: 16)
            content.textProperties.alignment = .center
            cell.contentConfiguration = content
            cell.backgroundColor = AppColors.surfaceElevated.color
            return cell
        }
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        cell.selectionStyle = .none
        cell.backgroundColor = AppColors.surfaceElevated.color
        
        var content = cell.defaultContentConfiguration()
        content.textProperties.color = AppColors.textPrimary.color
        content.textProperties.font = UIFont(name: "FiraSans-Medium", size: 15) ?? UIFont.systemFont(ofSize: 15, weight: .medium)
        content.secondaryTextProperties.color = AppColors.textSecondary.color
        content.secondaryTextProperties.font = UIFont(name: "FiraSans-Regular", size: 15) ?? UIFont.systemFont(ofSize: 15)
        content.secondaryTextProperties.numberOfLines = 2
        
                if indexPath.section == 0 {
            switch rule.ruleType {
            case .app(let app):
                content.text = app.commonName.capitalized
                content.secondaryText = "Any destination"
            case .host(let host):
                content.text = host
                content.secondaryText = "From any app"
            case .hostFromApp(let host, let app):
                content.text = host
                content.secondaryText = "From \(app.commonName)"
            }
} else if indexPath.section == 1 {
            let switchView = UISwitch()
            switchView.isOn = rule.isAllowed
            switchView.onTintColor = AppColors.highlight.color
            switchView.addTarget(self, action: #selector(toggleRule), for: .valueChanged)
            
            content.text = "Allow connections"
            content.secondaryText = rule.isAllowed ? "Connections matching this rule are allowed." : "Connections matching this rule are dropped."
            cell.accessoryView = switchView
        }
        
        cell.contentConfiguration = content
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        if indexPath.section == 2 {
            confirmDelete()
        }
    }
    
    @objc private func toggleRule(_ sender: UISwitch) {
        do {
            try RuleManager().delete(rule: rule)
            let newRule = Rule(ruleType: rule.ruleType, isAllowed: sender.isOn)
            try RuleManager().create(rule: newRule)
            self.rule = newRule
            delegate?.ruleDidUpdate()
            
            let cell = tableView.cellForRow(at: IndexPath(row: 0, section: 1))
            var content = cell?.contentConfiguration as? UIListContentConfiguration ?? UIListContentConfiguration.cell()
            content.text = "Allow connections"
            content.secondaryText = rule.isAllowed ? "Connections matching this rule are allowed." : "Connections matching this rule are dropped."
            cell?.contentConfiguration = content
            
        } catch {
            sender.isOn = rule.isAllowed
            let alert = UIAlertController(title: "Update Failed", message: "Could not update the rule.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            present(alert, animated: true, completion: nil)
        }
    }
    
    private func confirmDelete() {
        let alert = UIAlertController(title: "Delete Rule?", message: "Are you sure you want to delete this rule?", preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive, handler: { [weak self] _ in
            self?.deleteRule()
        }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(alert, animated: true, completion: nil)
    }
    
    @objc private func deleteRule() {
        do {
            try RuleManager().delete(rule: rule)
            delegate?.ruleDidUpdate()
            navigationController?.popViewController(animated: true)
        } catch {
            let alert = UIAlertController(title: "Delete Failed", message: "Could not delete the rule.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            present(alert, animated: true, completion: nil)
        }
    }
}
