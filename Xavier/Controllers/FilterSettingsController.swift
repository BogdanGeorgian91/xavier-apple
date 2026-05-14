import UIKit
import XavierShared
//
//  ViewController.swift
//  Xavier
//
//

import NetworkExtension
import UserNotifications

enum CreateRuleRow: Int {
    case app = 0
    case host = 1
}

class FilterSettingsController: UITableViewController, UISearchBarDelegate {

    @IBOutlet weak var enabledSwitch:UISwitch!
    @IBOutlet weak var enabledLabel:UILabel!
    @IBOutlet weak var pushControl:UISegmentedControl!
    @IBOutlet weak var searchBar:UISearchBar!
    @IBOutlet weak var resetButton:UIButton!

    var rules:[(AppName, [Rule])] = []
    var filteredRules:[(AppName, [Rule])] = []
    var expandedSections: Set<String> = []

    var isSearching:Bool = false
    
    var timer:Timer?
    let refresh = UIRefreshControl()
    
    var showsCreateSection: Bool {
        return !isSearching
    }
    
    var shouldShowEmptyRulesState: Bool {
        return !isSearching && rules.allSatisfy { $0.1.isEmpty }
    }

    var sectionOffset: Int {
        return showsCreateSection ? 1 : 0
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.tableView.backgroundColor = AppColors.surface.color
        self.tableView.separatorColor = AppColors.separator.color
        tableView.keyboardDismissMode = .onDrag
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        tableView.addGestureRecognizer(tap)

        
        if let headerView = self.tableView.tableHeaderView {
            headerView.backgroundColor = AppColors.surface.color
            
            // Search Bar Styling
            searchBar.backgroundColor = AppColors.surface.color
            searchBar.barTintColor = AppColors.surface.color
            searchBar.isTranslucent = false
            searchBar.backgroundImage = UIImage()
            if let textField = searchBar.value(forKey: "searchField") as? UITextField {
                textField.backgroundColor = AppColors.chrome.color
                textField.textColor = AppColors.textPrimary.color
            }

            // Fix the container views styling
            if let filterStatusContainer = enabledSwitch.superview {
                filterStatusContainer.backgroundColor = AppColors.surfaceElevated.color
                filterStatusContainer.layer.cornerRadius = 18
                filterStatusContainer.layer.borderWidth = 1
                filterStatusContainer.layer.borderColor = AppColors.separator.color.cgColor
                
                // Adjust colors for subviews
                for subview in filterStatusContainer.subviews {
                    if let label = subview as? UILabel {
                        label.textColor = label == enabledLabel ? AppColors.textPrimary.color : AppColors.textSecondary.color
                    }
                }
            }

            if let liveAlertsContainer = pushControl.superview {
                liveAlertsContainer.backgroundColor = AppColors.surfaceElevated.color
                liveAlertsContainer.layer.cornerRadius = 18
                liveAlertsContainer.layer.borderWidth = 1
                liveAlertsContainer.layer.borderColor = AppColors.separator.color.cgColor
                
                for subview in liveAlertsContainer.subviews {
                    if let label = subview as? UILabel {
                        label.textColor = AppColors.textSecondary.color
                    }
                }
            }
            
            resetButton.superview?.backgroundColor = AppColors.surface.color
            resetButton.backgroundColor = .clear
            resetButton.layer.cornerRadius = 18
            resetButton.layer.borderWidth = 1
            resetButton.layer.borderColor = AppColors.deny.color.cgColor
            resetButton.setTitleColor(AppColors.deny.color, for: .normal)
            if let outlinedBtn = resetButton as? OutlinedButton {
                outlinedBtn.borderColor = AppColors.deny.color
                outlinedBtn.highlightedColor = AppColors.deny.color
                outlinedBtn.cornerRadius = 18
            }
            
            headerView.setNeedsLayout()
            headerView.layoutIfNeeded()
            let headerSize = headerView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
            headerView.frame.size.height = headerSize.height
            tableView.tableHeaderView = headerView
        }
        
        refresh.tintColor = AppColors.background.color
        refresh.addTarget(self, action: #selector(FilterSettingsController.reload), for: .valueChanged)
        tableView.refreshControl = refresh
        
        pushControl.heightAnchor.constraint(equalToConstant: 28).isActive = true
        
        if Constants.isAllActivityMode {
            pushControl.selectedSegmentIndex = 1
        }
        
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 44
        
        if let font = UIFont(name: "FiraSans-Regular", size: 16) {
            pushControl.setTitleTextAttributes([
                NSAttributedString.Key.font: font,
                NSAttributedString.Key.foregroundColor: AppColors.textSecondary.color
            ], for: .normal)
            pushControl.setTitleTextAttributes([
                NSAttributedString.Key.font: font,
                NSAttributedString.Key.foregroundColor: AppColors.textPrimary.color
            ], for: .selected)
            
            UITextField.appearance(whenContainedInInstancesOf: [UISearchBar.self]).defaultTextAttributes = [
                NSAttributedString.Key.font: font,
                NSAttributedString.Key.foregroundColor: AppColors.textPrimary.color
            ]
            UITextField.appearance(whenContainedInInstancesOf: [UISearchBar.self]).attributedPlaceholder = NSAttributedString(
                string: "Filter apps and hosts",
                attributes: [
                    NSAttributedString.Key.font: font,
                    NSAttributedString.Key.foregroundColor: AppColors.textSecondary.color
                ]
            )
            
            UIBarButtonItem.appearance().setTitleTextAttributes([
                NSAttributedString.Key.font: font,
                NSAttributedString.Key.foregroundColor: AppColors.textPrimary.color
            ], for: .normal)
        }
    
        NotificationCenter.default.addObserver(self, selector: #selector(FilterSettingsController.reload), name: Constants.ObservableNotification.appBecameActive.name, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(metadataUpdated), name: NSNotification.Name("AppMetadataUpdated"), object: nil)
        
    }
    
    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        navigationController?.setNavigationBarHidden(true, animated: animated)
        
        NEFilterManager.shared().loadFromPreferences { error in
            if let loadError = error {
                self.enabledSwitch.isOn = false
                self.enabledLabel.text = self.enabledSwitch.isOn ? "Enabled" : "Disabled"
                self.showError(title: "Error loading preferences", error: loadError, fallbackMessage: "Could not load preferences.")
                
                return
            }
            
            self.enabledSwitch.isOn = NEFilterManager.shared().isEnabled
            self.enabledLabel.text = self.enabledSwitch.isOn ? "Enabled" : "Disabled"

        }
        
        loadRules()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }
    deinit {
        NotificationCenter.default.removeObserver(self, name: Constants.ObservableNotification.appBecameActive.name, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("AppMetadataUpdated"), object: nil)
    }
    
    @objc private func metadataUpdated() {
        tableView.reloadData()
    }
    
    @IBAction func pushActivitySettingChanged(sender: UISegmentedControl) {
        let allActivity = sender.selectedSegmentIndex == 1
        UserDefaults.group?.set(allActivity, forKey: Constants.pushActivityKey)
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        filterRulesFor(searchText: searchText.lowercased())
    }
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
    
    func filterRulesFor(searchText:String) {
        if searchText.isEmpty {
            filteredRules = []
            isSearching = false
            self.tableView.reloadData()
            return
        }
 
        isSearching = true
        
        filteredRules = []
        
        for (app, rules) in rules {
            if app.contains(searchText) {
                filteredRules.append((app, rules))
                continue
            }
            
            var filteredAppRules:[Rule] = []
            for rule in rules {
                if case .hostFromApp(let host, _) = rule.ruleType, host.contains(searchText) {
                    filteredAppRules.append(rule)
                }
            }
            
            if !filteredAppRules.isEmpty {
                filteredRules.append((app, filteredAppRules))
            }
        }
        
        self.tableView.reloadData()
    }
    
    @objc func reload() {
        self.loadRules()
    }
    
    @IBAction func unwindToHome(segue:UIStoryboardSegue) {
        self.loadRules()
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
    }
    
    func loadRules() {
        do {
            let rulesList = try RuleManager().fetchAll()
            
            var appHostRules:[String: [Rule]] = [:]
            var appRules:[Rule] = []
            var hostRules:[Rule] = []
            
            for rule in rulesList {
                switch rule.ruleType {
                case .app:
                    appRules.append(rule)
                case .host:
                    hostRules.append(rule)
                case .hostFromApp(_, let app):
                    if let existingRules = appHostRules[app] {
                        let newRules = existingRules + [rule]
                        appHostRules[app] = newRules
                        
                        continue
                    }
                    
                    appHostRules[app] = [rule]
                }
            }
            
            var newRules = [(String, [Rule])]()
            
            appHostRules.sorted(by: { $0.key < $1.key }).forEach {
                newRules.append(($0.key, $0.value))
            }
            
            if !appRules.isEmpty {
                newRules.append(("App Rules", appRules))
            }
            if !hostRules.isEmpty {
                newRules.append(("Host Rules", hostRules))
            }
            
            self.rules = newRules
            
            DispatchQueue.main.async {
                self.resetButton.isHidden = rulesList.isEmpty
                
                self.tableView.reloadData()
                self.refresh.endRefreshing()
            }
            
        } catch {
            self.showError(title: "Error loading rules", error: error, fallbackMessage: "Could not load rules.")
        }

    }
    
    func enable() {
        if NEFilterManager.shared().providerConfiguration == nil {
            let newConfiguration = NEFilterProviderConfiguration()
            newConfiguration.username = "Xavier"
            newConfiguration.organization = "Xavier App"
            newConfiguration.filterBrowsers = true
            newConfiguration.filterSockets = true
            NEFilterManager.shared().providerConfiguration = newConfiguration
        }

        NEFilterManager.shared().isEnabled = true
        NEFilterManager.shared().saveToPreferences { error in
            if let err = error {
                self.showError(title: "Error Enabling Filter", error: err, fallbackMessage: "Could not enable filter.")
            }
        }
    }
    
    func disable() {
        NEFilterManager.shared().isEnabled = false
        NEFilterManager.shared().saveToPreferences { error in
            if let err = error {
                self.showError(title: "Error Disabling Filter", error: err, fallbackMessage: "Could not disable filter.")
            }
        }

    }
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    @IBAction func enableToggled() {
        enabledSwitch.isOn ? enable() : disable()
        enabledLabel.text = enabledSwitch.isOn ? "Enabled" : "Disabled"
    }
    
    @IBAction func clearAll() {
        askConfirmationIn(title: "Reset All Rules?",
                           text: "This will permanently delete all your rules. Traffic will flow unrestricted until you create new ones. This cannot be undone.",
                           accept: "Reset",
                           cancel: "Cancel") { confirmed in
            guard confirmed else { return }
            try? RuleManager().deleteAll()
            self.loadRules()
            self.showSuccess(message: "All rules have been deleted.")
        }
    }

    // MARK: TableView
        override func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if showsCreateSection && section == 0 {
            return 2 // Create App Rule, Create Host Rule
        } else if section == 0 {
            return 0
        }
        
        let rulesArray = isSearching ? filteredRules : self.rules
        if rulesArray.isEmpty {
            return 1 // Empty state
        }
        
        return rulesArray.count
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if showsCreateSection && section == 0 {
            return "Create Rule"
        }
        
        if section == 1 {
            let rulesArray = isSearching ? filteredRules : self.rules
            if rulesArray.isEmpty { return nil }
            return "Apps with rules"
        }
        return nil
    }
    
override func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        guard let header = view as? UITableViewHeaderFooterView else { return }
        header.textLabel?.textColor = AppColors.background.color
        header.textLabel?.font = UIFont(name: "FiraSans-Bold", size: 16)
    }
    
    override func tableView(_ tableView: UITableView, willDisplayFooterView view: UIView, forSection section: Int) {
        guard let footer = view as? UITableViewHeaderFooterView else { return }
        footer.textLabel?.textColor = AppColors.textSecondary.color
        footer.textLabel?.font = UIFont(name: "FiraSans-Regular", size: 12) ?? UIFont.systemFont(ofSize: 12)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if showsCreateSection && indexPath.section == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "RuleCell") as? RuleCell ?? RuleCell(style: .subtitle, reuseIdentifier: "RuleCell")
            let createRow = CreateRuleRow(rawValue: indexPath.row)!
            
            // Re-using RuleCell logic for creation buttons
            var content = cell.defaultContentConfiguration()
            content.textProperties.font = UIFont(name: "FiraSans-Bold", size: 16) ?? .boldSystemFont(ofSize: 16)
            content.textProperties.color = AppColors.textPrimary.color
            content.secondaryTextProperties.font = UIFont(name: "FiraSans-Regular", size: 13) ?? .systemFont(ofSize: 13)
            content.secondaryTextProperties.color = AppColors.textSecondary.color
            content.imageProperties.tintColor = AppColors.textSecondary.color
            content.imageProperties.maximumSize = CGSize(width: 24, height: 24)
            
            if createRow == .app {
                content.text = "Add new App Rule..."
                content.secondaryText = "Any destination"
                content.image = UIImage(systemName: "plus.app")
            } else {
                content.text = "Add new Host Rule..."
                content.secondaryText = "From any app"
                content.image = UIImage(systemName: "plus.viewfinder")
            }
            
            let statusString = NSAttributedString(string: " +", attributes: [
                .foregroundColor: AppColors.background.color,
                .font: UIFont(name: "FiraSans-Medium", size: 16) ?? .systemFont(ofSize: 16, weight: .medium)
            ])
            let secondaryString = NSMutableAttributedString(string: content.secondaryText ?? "")
            secondaryString.append(statusString)
            content.secondaryAttributedText = secondaryString
            
            cell.contentConfiguration = content
            cell.backgroundColor = AppColors.surfaceElevated.color
            return cell
        }

        let rulesArray = isSearching ? filteredRules : self.rules
        if rulesArray.isEmpty {
            let cell = tableView.dequeueReusableCell(withIdentifier: "EmptyRulesCell") as? EmptyRulesCell ?? EmptyRulesCell(style: .default, reuseIdentifier: "EmptyRulesCell")
            cell.setupFallbackStyling()
            cell.backgroundColor = AppColors.surfaceElevated.color
            cell.selectionStyle = .none
            return cell
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: "AppCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "AppCell")
        cell.selectionStyle = .default
        cell.accessoryType = .disclosureIndicator
        cell.backgroundColor = AppColors.surfaceElevated.color
        
        let selectedView = UIView()
        selectedView.backgroundColor = AppColors.highlight.color.withAlphaComponent(0.12)
        cell.selectedBackgroundView = selectedView
        
        let appName = rulesArray[indexPath.row].0
        
        var content = cell.defaultContentConfiguration()
        content.textProperties.font = UIFont(name: "FiraSans-Bold", size: 16) ?? .boldSystemFont(ofSize: 16)
        content.textProperties.color = AppColors.textPrimary.color
        content.secondaryTextProperties.font = UIFont(name: "FiraSans-Regular", size: 13) ?? .systemFont(ofSize: 13)
        content.secondaryTextProperties.color = AppColors.textSecondary.color
        content.imageProperties.tintColor = AppColors.textSecondary.color
        content.imageProperties.maximumSize = CGSize(width: 24, height: 24)
        
        if appName == "Global" || appName == "Host Rules" {
            content.text = appName == "Global" ? "Global Rules" : "Host Rules"
            content.secondaryText = "System-wide host blocks"
            content.image = UIImage(systemName: "network")
        } else if appName == "App Rules" {
            content.text = "App Rules"
            content.secondaryText = "Block or allow all traffic for an app"
            content.image = UIImage(systemName: "app.badge")
        } else {
            let ruleCount = rulesArray[indexPath.row].1.count
            let ruleLabel = ruleCount == 1 ? "1 rule" : "\(ruleCount) rules"
            content.text = appName.commonName.capitalized
            content.secondaryText = "\(appName) • \(ruleLabel)"
            content.image = UIImage(systemName: "app.dashed")
        }
        
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        
        if showsCreateSection && indexPath.section == 0 {
            guard let createRow = CreateRuleRow(rawValue: indexPath.row) else { return }
            promptCreateRule(type: createRow)
            return
        }

        let rulesArray = isSearching ? filteredRules : self.rules
        if rulesArray.isEmpty { return }
        
        let appName = rulesArray[indexPath.row].0
        let detailVC = AppRulesViewController(appName: appName)
        navigationController?.pushViewController(detailVC, animated: true)
    }

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return false // Edit from RuleDetail
    }
    private func promptCreateRule(type: CreateRuleRow) {
        let titleText = type == .app ? "New App Rule" : "New Host Rule"
        let placeholder = type == .app ? "App ID (e.g. com.apple.safari)" : "Hostname (e.g. evil.com)"
        
        let alert = UIAlertController(title: titleText, message: "Enter \(placeholder)", preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = placeholder
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Allow", style: .default, handler: { [weak self, weak alert] _ in
            guard let text = alert?.textFields?.first?.text, !text.isEmpty else { return }
            let ruleType: RuleType = type == .app ? .app(text.lowercased()) : .host(text.lowercased())
            let rule = Rule(ruleType: ruleType, isAllowed: true)
            do {
                let manager = try RuleManager()
                try? manager.delete(rule: rule)
                try manager.create(rule: rule)
                self?.loadRules()
                self?.showSuccess(message: "Successfully created allow rule.")
            } catch {
                self?.showError(title: "Error", error: error, fallbackMessage: "An error occurred.")
            }
        }))
        alert.addAction(UIAlertAction(title: "Drop", style: .destructive, handler: { [weak self, weak alert] _ in
            guard let text = alert?.textFields?.first?.text, !text.isEmpty else { return }
            let ruleType: RuleType = type == .app ? .app(text.lowercased()) : .host(text.lowercased())
            let rule = Rule(ruleType: ruleType, isAllowed: false)
            do {
                let manager = try RuleManager()
                try? manager.delete(rule: rule)
                try manager.create(rule: rule)
                self?.loadRules()
                self?.showSuccess(message: "Successfully created drop rule.")
            } catch {
                self?.showError(title: "Error", error: error, fallbackMessage: "An error occurred.")
            }
        }))
        self.present(alert, animated: true)
    }

    private func toggleRule(_ rule: Rule) {
        do {
            try RuleManager().toggle(rule: rule)
            self.loadRules()
        } catch {
            self.showError(title: "Error", error: error, fallbackMessage: "An error occurred.")
        }
    }

    private func applyHostRuleAcrossApps(host: String, isAllowed: Bool, existingRule: Rule) {
        do {
            try RuleManager().delete(rule: existingRule)
            try RuleManager().create(rule: Rule(ruleType: .host(host), isAllowed: isAllowed))
            self.loadRules()
            self.showSuccess(message: "Rule applied to all apps.")
        } catch {
            self.showError(title: "Error applying rule", error: error, fallbackMessage: "Could not apply rule across apps.")
        }
    }

}

class EmptyRulesCell: UITableViewCell {
    override func awakeFromNib() {
        super.awakeFromNib()
        setupFallbackStyling()
    }
    
    func setupFallbackStyling() {
        if self.contentView.subviews.isEmpty || self.viewWithTag(1) == nil {
            var content = self.defaultContentConfiguration()
            content.text = "No rules yet"
            content.textProperties.alignment = .center
            content.textProperties.color = AppColors.textSecondary.color
            self.contentConfiguration = content
            self.backgroundColor = .clear
        } else {
            if let label1 = self.viewWithTag(1) as? UILabel {
                label1.textColor = AppColors.textPrimary.color
            }
            if let label2 = self.viewWithTag(2) as? UILabel {
                label2.textColor = AppColors.textSecondary.color
            }
            if let container = self.viewWithTag(1)?.superview {
                container.backgroundColor = AppColors.surfaceElevated.color
                container.layer.cornerRadius = 18
                container.layer.borderWidth = 1
                container.layer.borderColor = AppColors.separator.color.cgColor
            }
            self.backgroundColor = .clear
        }
    }
}

class RuleCell: UITableViewCell {
    
    override func awakeFromNib() {
        super.awakeFromNib()
        setupUI()
    }
    
    private func setupUI() {
        let selectedView = UIView()
        selectedView.backgroundColor = AppColors.highlight.color.withAlphaComponent(0.12)
        selectedBackgroundView = selectedView
        accessoryType = .disclosureIndicator
        backgroundColor = AppColors.surfaceElevated.color
    }
    
    func set(rule: Rule) {
        if selectedBackgroundView == nil {
            setupUI()
        }
        
        var content = defaultContentConfiguration()
        var secondaryStr = ""
        
        switch rule.ruleType {
        case .app(let app):
            content.text = app.capitalized
            secondaryStr = "Any destination"
            content.image = UIImage(systemName: "app.dashed")
            
        case .host(let host):
            content.text = host
            secondaryStr = "From any app"
            content.image = UIImage(systemName: "network")
            
        case .hostFromApp(let host, let app):
            content.text = host
            secondaryStr = "From \(app.commonName)"
            content.image = UIImage(systemName: "arrow.left.arrow.right")
        }
        
        // Title styling
        content.textProperties.font = UIFont(name: "FiraSans-Bold", size: 16) ?? .boldSystemFont(ofSize: 16)
        content.textProperties.color = AppColors.textPrimary.color
        
        // Image styling
        content.imageProperties.tintColor = AppColors.textSecondary.color
        content.imageProperties.maximumSize = CGSize(width: 24, height: 24)
        
        // Append allow/drop status at the end of subtitle
        let statusString = rule.isAllowed ? " (Allow)" : " (Drop)"
        
        let secondaryAttributedString = NSMutableAttributedString(
            string: secondaryStr,
            attributes: [
                .foregroundColor: AppColors.textSecondary.color,
                .font: UIFont(name: "FiraSans-Regular", size: 13) ?? .systemFont(ofSize: 13)
            ]
        )
        
        secondaryAttributedString.append(NSAttributedString(
            string: statusString,
            attributes: [
                .foregroundColor: rule.isAllowed ? AppColors.allow.color : AppColors.deny.color,
                .font: UIFont(name: "FiraSans-Medium", size: 13) ?? .systemFont(ofSize: 13, weight: .medium)
            ]
        ))
        
        content.secondaryAttributedText = secondaryAttributedString
        self.contentConfiguration = content
    }
}



extension FilterSettingsController: RuleDetailDelegate {
    func ruleDidUpdate() {
        loadRules()
    }
}
