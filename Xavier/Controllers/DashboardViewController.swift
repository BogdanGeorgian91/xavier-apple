//
//  DashboardViewController.swift
//  Xavier
//
//  Created by OpenCode on 4/5/26.
//

import UIKit

final class DashboardViewController: UITableViewController {
    enum Scope {
        case all
        case browsers

        var title: String {
            switch self {
            case .all:
                return "Activity"
            case .browsers:
                return "Browsers"
            }
        }

        var emptyStateTitle: String {
            switch self {
            case .all:
                return "No network activity yet"
            case .browsers:
                return "No browser activity yet"
            }
        }

        var emptyStateMessage: String {
            switch self {
            case .all:
                return "Open a few apps, browse around, then pull to refresh to see recent network activity grouped by app."
            case .browsers:
                return "Visit a few sites in Safari or another browser, then come back to review the latest browser traffic."
            }
        }

        func includes(app: AppName) -> Bool {
            switch self {
            case .all:
                return true
            case .browsers:
                return BrowserAppClassifier.isBrowser(appIdentifier: app)
            }
        }
    }

    private let scope: Scope
    private let refresh = UIRefreshControl()
    private let byteFormatter = ByteCountFormatter()
    private let relativeFormatter = DateComponentsFormatter()
    private let timestampFormatter = DateFormatter()
    private var lastHeaderWidth: CGFloat = 0
    private var allSummaries = [NetworkEventAppSummary]()
    private var visibleSummaries = [NetworkEventAppSummary]()
    private var displayedScope: Scope
    private var appStatusTexts = [AppName: String]()
    private var ruleStatusesUnavailable = false
    private var activityOverview = NetworkActivityOverview(recentBytesInbound: 0,
                                                          recentBytesOutbound: 0,
                                                          activeAppCount: 0,
                                                          recentEventCount: 0,
                                                          newHostCountToday: 0,
                                                          lastActivityTimestamp: nil)
    private lazy var activitySearchBar: UISearchBar = {
        let bar = UISearchBar()
        bar.searchBarStyle = .minimal
        bar.placeholder = "Search apps"
        bar.delegate = self
        bar.searchTextField.backgroundColor = AppColors.chrome.color
        return bar
    }()

    init(scope: Scope) {
        self.scope = scope
        self.displayedScope = scope
        super.init(style: .insetGrouped)
    }

    required init?(coder aDecoder: NSCoder) {
        self.scope = .all
        self.displayedScope = .all
        super.init(coder: aDecoder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.largeTitleDisplayMode = .never
        navigationItem.backButtonDisplayMode = .minimal
        definesPresentationContext = true

        switch scope {
        case .all:
            break
        case .browsers:
            break
        }

        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 88
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        tableView.separatorColor = AppColors.separator.color
        tableView.backgroundColor = AppColors.surface.color
        tableView.tableFooterView = UIView(frame: .zero)
        tableView.sectionFooterHeight = 12
        tableView.keyboardDismissMode = .onDrag
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        tableView.addGestureRecognizer(tap)

        refresh.tintColor = AppColors.background.color
        refresh.addTarget(self, action: #selector(reloadData), for: .valueChanged)
        tableView.refreshControl = refresh

        byteFormatter.countStyle = .file
        byteFormatter.allowsNonnumericFormatting = false
        relativeFormatter.allowedUnits = [.minute, .hour, .day]
        relativeFormatter.maximumUnitCount = 1
        relativeFormatter.unitsStyle = .abbreviated
        timestampFormatter.dateStyle = .medium
        timestampFormatter.timeStyle = .short

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(reloadData),
                                               name: Constants.ObservableNotification.appBecameActive.name,
                                               object: nil)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(reloadTableView),
                                               name: NSNotification.Name("AppMetadataUpdated"),
                                               object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        reloadData()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let width = tableView.bounds.width
        guard abs(lastHeaderWidth - width) > 0.5 else {
            return
        }

        lastHeaderWidth = width
        updateHeader()
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: Constants.ObservableNotification.appBecameActive.name, object: nil)
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }


    @objc private func reloadTableView() {
        tableView.reloadData()
    }

    @objc private func reloadData() {
        do {
            let filter: ((AppName) -> Bool) = { app in
                if app.lowercased().hasPrefix(Constants.appBundleIdentifier.lowercased()) { return false }
                return self.displayedScope.includes(app: app)
            }
            let dashboardData = try NetworkEventManager.shared.fetchDashboardData(filter: filter)
            allSummaries = dashboardData.appSummaries
            activityOverview = dashboardData.activityOverview

            do {
                appStatusTexts = try loadAppStatuses(for: allSummaries)
                ruleStatusesUnavailable = false
            } catch {
                appStatusTexts = [:]
                ruleStatusesUnavailable = true
            }

            updateHeader()
            applySearch(query: activitySearchBar.text)
        } catch {
            allSummaries = []
            visibleSummaries = []
            appStatusTexts = [:]
            ruleStatusesUnavailable = false
            activityOverview = NetworkActivityOverview(recentBytesInbound: 0,
                                                      recentBytesOutbound: 0,
                                                      activeAppCount: 0,
                                                      recentEventCount: 0,
                                                      newHostCountToday: 0,
                                                      lastActivityTimestamp: nil)
            updateHeader()
            updateEmptyState(query: activitySearchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
            tableView.reloadData()
            showWarning(title: "Unable to Load Activity", body: "Xavier couldn’t load saved network activity right now. \(error)")
        }

        refresh.endRefreshing()
    }

    private func applySearch(query: String?) {
        let trimmed = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if trimmed.isEmpty {
            visibleSummaries = allSummaries
        } else {
            let normalized = trimmed.lowercased()
            visibleSummaries = allSummaries.filter {
                $0.app.commonName.lowercased().contains(normalized) || $0.app.lowercased().contains(normalized)
            }
        }

        updateEmptyState(query: trimmed)
        tableView.reloadData()
    }

    private func updateHeader() {
        let titleLabel = UILabel()
        titleLabel.font = UIFont(name: "FiraSans-Bold", size: 24) ?? UIFont.boldSystemFont(ofSize: 24)
        titleLabel.textColor = AppColors.textPrimary.color
        titleLabel.text = "Network activity"

        let windowLabel = UILabel()
        windowLabel.font = UIFont(name: "FiraSans-Medium", size: 13) ?? UIFont.systemFont(ofSize: 13, weight: .medium)
        windowLabel.textColor = AppColors.textSecondary.color
        windowLabel.text = "Last hour"

        let titleStack = UIStackView(arrangedSubviews: [titleLabel, windowLabel])
        titleStack.axis = .vertical
        titleStack.spacing = 4
        titleStack.alignment = .leading

        let stack = UIStackView(arrangedSubviews: [titleStack])
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false

        if activityOverview.recentEventCount == 0 {
            let emptyTitle = UILabel()
            emptyTitle.font = UIFont(name: "FiraSans-Bold", size: 20) ?? UIFont.boldSystemFont(ofSize: 20)
            emptyTitle.textColor = AppColors.textPrimary.color
            emptyTitle.numberOfLines = 0
            emptyTitle.text = "No network activity in the last hour"

            let emptyMessage = UILabel()
            emptyMessage.font = UIFont(name: "FiraSans-Regular", size: 15) ?? UIFont.systemFont(ofSize: 15)
            emptyMessage.textColor = AppColors.textSecondary.color
            emptyMessage.numberOfLines = 0
            emptyMessage.text = "Open another app to start seeing connections here."

            stack.addArrangedSubview(emptyTitle)
            stack.addArrangedSubview(emptyMessage)
        } else {
            let primaryMetrics = UIStackView(arrangedSubviews: [
                makeMetricView(title: "Data in", value: activityOverview.recentBytesInbound > 0 ? byteFormatter.string(fromByteCount: activityOverview.recentBytesInbound) : "0 KB"),
                makeMetricView(title: "Data out", value: activityOverview.recentBytesOutbound > 0 ? byteFormatter.string(fromByteCount: activityOverview.recentBytesOutbound) : "0 KB")
            ])
            primaryMetrics.axis = .horizontal
            primaryMetrics.alignment = .fill
            primaryMetrics.distribution = .fillEqually
            primaryMetrics.spacing = 12

            let secondaryMetrics = UIStackView(arrangedSubviews: [
                makeMetricView(title: "Apps active", value: "\(activityOverview.activeAppCount)"),
                makeMetricView(title: "Events", value: "\(activityOverview.recentEventCount)")
            ])
            secondaryMetrics.axis = .horizontal
            secondaryMetrics.alignment = .fill
            secondaryMetrics.distribution = .fillEqually
            secondaryMetrics.spacing = 12

            stack.addArrangedSubview(primaryMetrics)
            stack.addArrangedSubview(secondaryMetrics)
        }

        let footerLabel = UILabel()
        footerLabel.font = UIFont(name: "FiraSans-Regular", size: 14) ?? UIFont.systemFont(ofSize: 14)
        footerLabel.textColor = AppColors.textSecondary.color
        footerLabel.numberOfLines = 0
        footerLabel.text = footerText()
        stack.addArrangedSubview(footerLabel)

        let card = UIView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 1))
        card.backgroundColor = AppColors.surfaceElevated.color
        card.layer.cornerRadius = 20
        card.layer.borderWidth = 1
        card.layer.borderColor = AppColors.separator.color.cgColor

        let container = UIView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 1))
        container.backgroundColor = .clear
        container.addSubview(card)
        card.addSubview(stack)

        card.translatesAutoresizingMaskIntoConstraints = false
        
        if scope == .all {
            let searchBar = activitySearchBar
            searchBar.translatesAutoresizingMaskIntoConstraints = false
            searchBar.removeFromSuperview()
            container.addSubview(searchBar)
            
            NSLayoutConstraint.activate([
                searchBar.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
                searchBar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
                searchBar.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
                
                card.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 12),
                card.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
                card.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
                card.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
            ])
        } else {
            NSLayoutConstraint.activate([
                card.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
                card.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
                card.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
                card.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
            ])
        }

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18)
        ])

        let targetSize = CGSize(width: tableView.bounds.width, height: UIView.layoutFittingCompressedSize.height)
        let size = container.systemLayoutSizeFitting(targetSize,
                                                     withHorizontalFittingPriority: .required,
                                                     verticalFittingPriority: .fittingSizeLevel)
        container.frame.size.height = ceil(size.height)

        tableView.tableHeaderView = container
    }

    private func makeMetricView(title: String, value: String) -> UIView {
        let titleLabel = UILabel()
        titleLabel.font = UIFont(name: "FiraSans-Regular", size: 13) ?? UIFont.systemFont(ofSize: 13)
        titleLabel.textColor = AppColors.textSecondary.color
        titleLabel.text = title

        let valueLabel = UILabel()
        valueLabel.font = UIFont(name: "FiraSans-Bold", size: 24) ?? UIFont.boldSystemFont(ofSize: 24)
        valueLabel.textColor = AppColors.textPrimary.color
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.7
        valueLabel.text = value

        let stack = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        stack.axis = .vertical
        stack.spacing = 4

        let container = UIView()
        container.backgroundColor = AppColors.chrome.color
        container.layer.cornerRadius = 16
        container.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14)
        ])

        return container
    }

    private func footerText() -> String {
        let hostsText = "\(activityOverview.newHostCountToday) new hosts today"

        guard let lastActivity = activityOverview.lastActivityTimestamp else {
            return hostsText + " • No saved activity yet"
        }

        if Date().timeIntervalSince(lastActivity) < 60 {
            return hostsText + " • Last activity just now"
        }

        guard let relativeText = relativeFormatter.string(from: lastActivity, to: Date()) else {
            return hostsText + " • Last activity recently"
        }

        return hostsText + " • Last activity \(relativeText) ago"
    }

    private func updateEmptyState(query: String) {
        guard visibleSummaries.isEmpty else {
            tableView.backgroundView = nil
            return
        }

        let activeScope = displayedScope

        let titleLabel = UILabel()
        titleLabel.font = UIFont(name: "FiraSans-Bold", size: 22) ?? UIFont.boldSystemFont(ofSize: 22)
        titleLabel.textColor = AppColors.textPrimary.color
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.text = query.isEmpty ? activeScope.emptyStateTitle : "No matching apps"

        let messageLabel = UILabel()
        messageLabel.font = UIFont(name: "FiraSans-Regular", size: 15) ?? UIFont.systemFont(ofSize: 15)
        messageLabel.textColor = AppColors.textSecondary.color
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.text = query.isEmpty ? activeScope.emptyStateMessage : "Try another app name or clear the search field to see all recent activity."

        let stack = UIStackView(arrangedSubviews: [titleLabel, messageLabel])
        stack.axis = .vertical
        stack.spacing = 10
        stack.alignment = .fill
        stack.layoutMargins = UIEdgeInsets(top: 0, left: 28, bottom: 0, right: 28)
        stack.isLayoutMarginsRelativeArrangement = true

        let container = UIView()
        container.backgroundColor = AppColors.surface.color
        container.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor)
        ])

        tableView.backgroundView = container
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return visibleSummaries.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return "Recent connections"
    }

    override func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        guard let header = view as? UITableViewHeaderFooterView else { return }
        header.textLabel?.textColor = AppColors.textSecondary.color
        header.textLabel?.font = UIFont.systemFont(ofSize: 13, weight: .regular)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SummaryCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "SummaryCell")
        let summary = visibleSummaries[indexPath.row]

        cell.accessoryType = .disclosureIndicator
        cell.backgroundColor = AppColors.surfaceElevated.color
        
        var content = cell.defaultContentConfiguration()
        content.text = summary.app.commonName.capitalized
        content.secondaryText = detailText(for: summary)
        
        content.textProperties.font = UIFont(name: "FiraSans-Bold", size: 17) ?? UIFont.boldSystemFont(ofSize: 17)
        content.textProperties.color = AppColors.textPrimary.color
        content.textProperties.numberOfLines = 0
        
        content.secondaryTextProperties.font = UIFont(name: "FiraSans-Regular", size: 14) ?? UIFont.systemFont(ofSize: 14)
        content.secondaryTextProperties.color = AppColors.textSecondary.color
        content.secondaryTextProperties.numberOfLines = 0
        
        cell.contentConfiguration = content

        let selectedView = UIView()
        selectedView.backgroundColor = AppColors.highlight.color.withAlphaComponent(0.12)
        cell.selectedBackgroundView = selectedView

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let summary = visibleSummaries[indexPath.row]
        navigationController?.pushViewController(AppDetailViewController(appIdentifier: summary.app), animated: true)
    }

    private func detailText(for summary: NetworkEventAppSummary) -> String {
        let sumBytes = summary.totalBytesInbound + summary.totalBytesOutbound
        let totalBytes = sumBytes > 0 ? byteFormatter.string(fromByteCount: sumBytes) : "0 KB"
        let hostText = summary.lastHost ?? "Unknown host"
        let timestampText = timestampFormatter.string(from: summary.lastTimestamp)
        let eventLabel = summary.eventCount == 1 ? "event" : "events"
        let statusText = appStatusTexts[summary.app] ?? (ruleStatusesUnavailable ? "Rule status unavailable" : "No app-specific controls")
        return "\(summary.eventCount) \(eventLabel) • \(totalBytes) transferred\nLast host: \(hostText)\nStatus: \(statusText)\nLast seen: \(timestampText)"
    }

    private func loadAppStatuses(for summaries: [NetworkEventAppSummary]) throws -> [AppName: String] {
        let rules = try RuleManager().fetchAll()
        let blockedApps = Set(rules.compactMap { rule -> AppName? in
            guard case .app(let app) = rule.ruleType, !rule.isAllowed else {
                return nil
            }
            return app
        })

        let globalHostRules = rules.reduce(into: [String: Bool]()) { result, rule in
            guard case .host(let host) = rule.ruleType else {
                return
            }
            result[host] = rule.isAllowed
        }

        let appHostRules = rules.reduce(into: [AppName: [String: Bool]]()) { result, rule in
            guard case .hostFromApp(let host, let app) = rule.ruleType else {
                return
            }
            var rulesForApp = result[app] ?? [:]
            rulesForApp[host] = rule.isAllowed
            result[app] = rulesForApp
        }

        return summaries.reduce(into: [AppName: String]()) { result, summary in
            var statuses = [String]()

            if blockedApps.contains(summary.app) {
                statuses.append("Blocked for all traffic")
            } else if let host = summary.lastHost,
                      let appRule = appHostRules[summary.app]?[host] {
                statuses.append(appRule ? "Allowed host rule active" : "Blocked host rule active")
            } else if let host = summary.lastHost,
                      let globalRule = globalHostRules[host] {
                statuses.append(globalRule ? "Allowed host rule active" : "Blocked host rule active")
            } else if appHostRules[summary.app] != nil {
                statuses.append("Custom rules active")
            }

            if Constants.isNotificationMuted(for: summary.app) {
                statuses.append("Alerts off")
            } else if Constants.isAllActivityMode {
                statuses.append("All-activity alerts on")
            } else {
                statuses.append("New-host alerts on")
            }

            result[summary.app] = statuses.isEmpty ? "No app-specific controls" : statuses.joined(separator: " • ")
        }
    }
}

extension DashboardViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        applySearch(query: searchText)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}

private enum BrowserAppClassifier {
    private static let knownBrowsers = [
        "com.apple.mobilesafari",
        "com.google.chrome.ios",
        "org.mozilla.ios.firefox",
        "com.microsoft.msedge",
        "com.brave.ios.browser",
        "com.duckduckgo.mobile.ios",
        "com.opera.OperaTouch",
        "company.thebrowser.Browser"
    ]

    private static let browserKeywords = ["safari", "chrome", "firefox", "edge", "browser", "brave", "duckduckgo", "arc", "opera"]

    static func isBrowser(appIdentifier: String) -> Bool {
        if knownBrowsers.contains(appIdentifier) {
            return true
        }

        let lowercased = appIdentifier.lowercased()
        let commonName = appIdentifier.commonName.lowercased()
        return browserKeywords.contains {
            commonName.contains($0) || lowercased.contains(".\($0)") || lowercased.hasSuffix($0)
        }
    }
}
