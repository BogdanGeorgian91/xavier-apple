import UIKit
import XavierShared

final class InspectorViewController: UITableViewController {
    private enum Section: Int, CaseIterable {
        case actions
        case search
        case sites
    }

    private let actionRows = [
        ("Inspector Setup", "Proxy profile, certificate trust, and pinned-domain state."),
        ("Domain Blocklist", "Block matching hosts and manage tracker presets."),
        ("Strip Scripts", "Choose which hosts allow HTML script stripping."),
        ("Modification Rules", "Add headers, rewrite URLs, or modify request content.")
    ]

    private var summaries = [InspectorSiteSummary]()
    private var searchQuery = ""
    private let formatter = DateFormatter()
    private lazy var siteSearchField: UITextField = {
        let field = UITextField()
        field.placeholder = "Search sites or app bundle IDs"
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.returnKeyType = .search
        field.font = UIFont(name: "FiraSans-Regular", size: 14) ?? .systemFont(ofSize: 14)
        field.backgroundColor = .clear
        field.borderStyle = .none
        field.textColor = AppColors.textPrimary.color
        field.tintColor = AppColors.highlight.color
        field.addTarget(self, action: #selector(searchTextChanged(_:)), for: .editingChanged)
        field.addTarget(self, action: #selector(searchFieldSearchTapped(_:)), for: .primaryActionTriggered)
        return field
    }()

    private var visibleSummaries: [InspectorSiteSummary] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return summaries }

        return summaries.filter { summary in
            if summary.site.lowercased().contains(query) {
                return true
            }

            return summary.apps.contains { appBundleID in
                appBundleID.lowercased().contains(query)
            }
        }
    }

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Inspector"
        navigationItem.largeTitleDisplayMode = .never
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 96
        tableView.backgroundColor = AppColors.surface.color
        tableView.separatorColor = AppColors.separator.color
        tableView.tableFooterView = UIView(frame: .zero)
        tableView.keyboardDismissMode = .onDrag

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(reloadData),
                                               name: Constants.ObservableNotification.appBecameActive.name,
                                               object: nil)
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(reloadData), for: .valueChanged)
        tableView.refreshControl = refreshControl
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        reloadData()
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: Constants.ObservableNotification.appBecameActive.name, object: nil)
    }

    @objc private func reloadData() {
        do {
            summaries = try InspectionManager.shared.fetchSiteSummaries()
            updateHeader()
            tableView.reloadData()
        } catch {
            summaries = []
            updateHeader()
            tableView.reloadData()
            showWarning(title: "Unable to Load Inspector", body: "Xavier couldn't load saved inspection data right now.")
        }
        tableView.refreshControl?.endRefreshing()
    }

    private func updateHeader() {
        let titleLabel = UILabel()
        titleLabel.font = UIFont(name: "FiraSans-Bold", size: 25) ?? .boldSystemFont(ofSize: 25)
        titleLabel.textColor = AppColors.textPrimary.color
        titleLabel.text = "Deep inspection"

        let subtitle = UILabel()
        subtitle.font = UIFont(name: "FiraSans-Regular", size: 15) ?? .systemFont(ofSize: 15)
        subtitle.textColor = AppColors.textSecondary.color
        subtitle.numberOfLines = 0
        subtitle.text = "HTTPS traffic captured by the app proxy appears here once the certificate is trusted and the proxy profile is enabled."

        let proxyMetric = makeMetricView(title: "Proxy", value: "Dev")
        let certMetric = makeMetricView(title: "Certificate", value: trustStatusText(CAStatusChecker.checkTrustStatus()))
        let blockedMetric = makeMetricView(title: "Blocked", value: "\(summaries.reduce(0) { $0 + $1.blockedCount })")

        let metricsRow = UIStackView(arrangedSubviews: [proxyMetric, certMetric, blockedMetric])
        metricsRow.axis = .horizontal
        metricsRow.spacing = 10
        metricsRow.distribution = .fillEqually

        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitle, metricsRow])
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        let card = UIView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 1))
        card.backgroundColor = AppColors.surfaceElevated.color
        card.layer.cornerRadius = 20
        card.layer.borderWidth = 1
        card.layer.borderColor = AppColors.separator.color.cgColor
        card.addSubview(stack)

        let container = UIView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 1))
        container.addSubview(card)
        card.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            card.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            card.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            card.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
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
        titleLabel.font = UIFont(name: "FiraSans-Regular", size: 13) ?? .systemFont(ofSize: 13)
        titleLabel.textColor = AppColors.textSecondary.color
        titleLabel.text = title

        let valueLabel = UILabel()
        valueLabel.font = UIFont(name: "FiraSans-Bold", size: 19) ?? .boldSystemFont(ofSize: 19)
        valueLabel.textColor = AppColors.textPrimary.color
        valueLabel.text = value
        valueLabel.adjustsFontSizeToFitWidth = true

        let stack = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        stack.axis = .vertical
        stack.spacing = 2

        let container = UIView()
        container.backgroundColor = AppColors.chrome.color
        container.layer.cornerRadius = 16
        container.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12)
        ])
        return container
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .actions:
            return actionRows.count
        case .search:
            return 1
        case .sites:
            return max(visibleSummaries.count, 1)
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .actions:
            return "Controls"
        case .search:
            return nil
        case .sites:
            return "Sites Contacted"
        }
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        guard Section(rawValue: section) == .search else {
            return UITableView.automaticDimension
        }
        return CGFloat.leastNormalMagnitude
    }

    override func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        switch Section(rawValue: section)! {
        case .actions, .search:
            return 4
        case .sites:
            return UITableView.automaticDimension
        }
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard Section(rawValue: indexPath.section) == .search else {
            return UITableView.automaticDimension
        }
        return 52
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "InspectorCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "InspectorCell")
        cell.backgroundColor = AppColors.surfaceElevated.color
        cell.tintColor = AppColors.highlight.color

        var content = cell.defaultContentConfiguration()
        content.textProperties.font = UIFont(name: "FiraSans-Bold", size: 17) ?? .boldSystemFont(ofSize: 17)
        content.textProperties.color = AppColors.textPrimary.color
        content.textProperties.numberOfLines = 0
        content.secondaryTextProperties.font = UIFont(name: "FiraSans-Regular", size: 14) ?? .systemFont(ofSize: 14)
        content.secondaryTextProperties.color = AppColors.textSecondary.color
        content.secondaryTextProperties.numberOfLines = 0

        switch Section(rawValue: indexPath.section)! {
        case .actions:
            cell.accessoryType = .disclosureIndicator
            let (title, subtitle) = actionRows[indexPath.row]
            content.text = title
            content.secondaryText = subtitle
        case .search:
            let cell = tableView.dequeueReusableCell(withIdentifier: "InspectorSearchCell") as? InspectorSearchCell ?? InspectorSearchCell(style: .default, reuseIdentifier: "InspectorSearchCell")
            cell.configure(with: siteSearchField)
            return cell
        case .sites:
            let siteSummaries = visibleSummaries
            if siteSummaries.isEmpty {
                let hasSearch = !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                content.text = hasSearch ? "No matching inspected requests" : "No inspected requests yet"
                content.secondaryText = hasSearch ? "Try a site name or an app bundle ID." : "Enable the proxy, trust the certificate, and browse from a mapped app."
                cell.accessoryType = .none
            } else {
                let summary = siteSummaries[indexPath.row]
                let methods = summary.methods.sorted().joined(separator: ", ")
                let apps = summary.apps.sorted().joined(separator: ", ")
                content.text = summary.site
                content.secondaryText = "\(apps) • \(formatter.string(from: summary.lastTimestamp)) • \(summary.hostCount) host\(summary.hostCount == 1 ? "" : "s") • \(summary.requestCount) request\(summary.requestCount == 1 ? "" : "s") • \(methods.isEmpty ? "Metadata only" : methods)"
                
                if containsHTTPMethod(summary.methods) {
                    content.textProperties.color = AppColors.allow.color
                }
                
                cell.accessoryType = .disclosureIndicator
            }
        }

        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch Section(rawValue: indexPath.section)! {
        case .actions:
            switch indexPath.row {
            case 0:
                navigationController?.pushViewController(InspectorSetupViewController(), animated: true)
            case 1:
                navigationController?.pushViewController(BlocklistViewController(), animated: true)
            case 2:
                navigationController?.pushViewController(StripScriptsViewController(), animated: true)
            case 3:
                navigationController?.pushViewController(ModificationRulesViewController(), animated: true)
            default:
                break
            }
        case .search:
            siteSearchField.becomeFirstResponder()
        case .sites:
            let siteSummaries = visibleSummaries
            guard !siteSummaries.isEmpty else { return }
            navigationController?.pushViewController(InspectorSiteDetailViewController(site: siteSummaries[indexPath.row].site), animated: true)
        }
    }

    private func trustStatusText(_ status: CACheckStatus) -> String {
        switch status {
        case .notInstalled: return "Missing"
        case .installedButNotTrusted: return "Needs trust"
        case .trusted: return "Trusted"
        }
    }

    private func containsHTTPMethod(_ methods: Set<String>) -> Bool {
        return methods.contains { method in
            let normalized = method.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            return !normalized.isEmpty && normalized != "FLOW"
        }
    }

    @objc private func searchTextChanged(_ sender: UITextField) {
        searchQuery = sender.text ?? ""
        tableView.reloadSections(IndexSet(integer: Section.sites.rawValue), with: .none)
    }

    @objc private func searchFieldSearchTapped(_ sender: UITextField) {
        sender.resignFirstResponder()
    }
}

private final class InspectorSearchCell: UITableViewCell {
    private let searchIcon = UIImageView(image: UIImage(systemName: "magnifyingglass"))

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        selectionStyle = .none
        backgroundColor = AppColors.surfaceElevated.color
        contentView.backgroundColor = AppColors.surfaceElevated.color
        searchIcon.tintColor = AppColors.textSecondary.color
        searchIcon.contentMode = .scaleAspectFit
        searchIcon.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(searchIcon)

        NSLayoutConstraint.activate([
            searchIcon.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            searchIcon.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            searchIcon.widthAnchor.constraint(equalToConstant: 18),
            searchIcon.heightAnchor.constraint(equalToConstant: 18)
        ])
    }

    func configure(with searchField: UITextField) {
        if searchField.superview !== contentView {
            searchField.removeFromSuperview()
            searchField.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(searchField)

            NSLayoutConstraint.activate([
                searchField.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: 10),
                searchField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
                searchField.topAnchor.constraint(equalTo: contentView.topAnchor),
                searchField.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            ])
        }
    }
}
