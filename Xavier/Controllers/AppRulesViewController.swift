import UIKit
import XavierShared

class AppRulesViewController: UITableViewController {
    private let appName: AppName
    private var rules: [Rule] = []
    
    init(appName: AppName) {
        self.appName = appName
        super.init(style: .insetGrouped)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        loadRules()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = {
        switch appName {
        case "Global", "Host Rules": return "Global Rules"
        case "App Rules": return "App Rules"
        default: return appName.commonName.capitalized
        }
    }()
        navigationItem.largeTitleDisplayMode = .never
        
        tableView.backgroundColor = AppColors.surface.color
        tableView.separatorColor = AppColors.separator.color
        tableView.register(RuleCell.self, forCellReuseIdentifier: "RuleCell")
    }
    
    private func loadRules() {
        do {
            let allRules = try RuleManager().fetchAll()
            switch appName {
            case "Global":
                self.rules = allRules.filter { rule in
                    if case .host = rule.ruleType { return true }
                    return false
                }
            case "Host Rules":
                self.rules = allRules.filter { rule in
                    if case .host = rule.ruleType { return true }
                    return false
                }
            case "App Rules":
                self.rules = allRules.filter { rule in
                    if case .app = rule.ruleType { return true }
                    return false
                }
            default:
                self.rules = allRules.filter { rule in
                    switch rule.ruleType {
                    case .app(let app): return app == appName
                    case .hostFromApp(_, let app): return app == appName
                    default: return false
                    }
                }
            }
            tableView.reloadData()
        } catch {
            print("Error loading rules: \(error)")
        }
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return max(rules.count, 1)
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if rules.isEmpty {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            var content = cell.defaultContentConfiguration()
            content.text = "No rules"
            content.textProperties.alignment = .center
            content.textProperties.color = AppColors.textSecondary.color
            cell.contentConfiguration = content
            cell.backgroundColor = AppColors.surfaceElevated.color
            cell.selectionStyle = .none
            return cell
        }
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "RuleCell", for: indexPath) as! RuleCell
        cell.set(rule: rules[indexPath.row])
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if rules.isEmpty { return }
        
        let rule = rules[indexPath.row]
        let detailVC = RuleDetailViewController(rule: rule, delegate: self)
        navigationController?.pushViewController(detailVC, animated: true)
    }
}

extension AppRulesViewController: RuleDetailDelegate {
    func ruleDidUpdate() {
        loadRules()
    }
}
