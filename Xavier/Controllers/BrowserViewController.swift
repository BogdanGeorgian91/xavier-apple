import UIKit

final class BrowserViewController: UITableViewController {
    private let refresh = UIRefreshControl()
    private let timestampFormatter = DateFormatter()
    private var summaries = [BrowserHostSummary]()

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Browser"
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.backButtonDisplayMode = .minimal
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        tableView.separatorColor = AppColors.separator.color
        tableView.backgroundColor = AppColors.surface.color
        tableView.tableFooterView = UIView(frame: .zero)

        refresh.tintColor = AppColors.background.color
        refresh.addTarget(self, action: #selector(reloadData), for: .valueChanged)
        tableView.refreshControl = refresh

        timestampFormatter.dateStyle = .medium
        timestampFormatter.timeStyle = .short

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(reloadData),
                                               name: Constants.ObservableNotification.appBecameActive.name,
                                               object: nil)
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
            summaries = try BrowserEventManager.shared.fetchHostSummaries()
            updateHeader()
            tableView.reloadData()
        } catch {
            summaries = []
            updateHeader()
            tableView.reloadData()
            showWarning(title: "Unable to Load Browser Activity", body: "Xavier couldn't load saved browser activity right now. \(error)")
        }
        refresh.endRefreshing()
    }

    private func updateHeader() {
        let titleLabel = UILabel()
        titleLabel.font = UIFont(name: "FiraSans-Bold", size: 24) ?? UIFont.boldSystemFont(ofSize: 24)
        titleLabel.textColor = AppColors.textPrimary.color
        titleLabel.text = "Browser activity"

        let subtitle = UILabel()
        subtitle.font = UIFont(name: "FiraSans-Regular", size: 14) ?? UIFont.systemFont(ofSize: 14)
        subtitle.textColor = AppColors.textSecondary.color
        subtitle.numberOfLines = 0
        subtitle.text = "Recent WebKit browser activity grouped by the parent page when iOS exposes it, with request and response metadata shown in detail."

        let metric = makeMetricView(title: "Pages", value: "\(summaries.count)")

        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitle, metric])
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
        container.backgroundColor = .clear
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
        titleLabel.font = UIFont(name: "FiraSans-Regular", size: 13) ?? UIFont.systemFont(ofSize: 13)
        titleLabel.textColor = AppColors.textSecondary.color
        titleLabel.text = title

        let valueLabel = UILabel()
        valueLabel.font = UIFont(name: "FiraSans-Bold", size: 24) ?? UIFont.boldSystemFont(ofSize: 24)
        valueLabel.textColor = AppColors.textPrimary.color
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

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return max(summaries.count, 1)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "BrowserHostCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "BrowserHostCell")
        cell.accessoryType = .disclosureIndicator
        cell.backgroundColor = AppColors.surfaceElevated.color
        cell.tintColor = AppColors.highlight.color

        var content = cell.defaultContentConfiguration()
        content.textProperties.font = UIFont(name: "FiraSans-Bold", size: 18) ?? UIFont.boldSystemFont(ofSize: 18)
        content.textProperties.color = AppColors.textPrimary.color
        content.textProperties.numberOfLines = 2
        content.secondaryTextProperties.font = UIFont(name: "FiraSans-Regular", size: 13) ?? UIFont.systemFont(ofSize: 13)
        content.secondaryTextProperties.color = AppColors.textSecondary.color
        content.secondaryTextProperties.numberOfLines = 2

        guard !summaries.isEmpty else {
            content.text = "No browser activity yet"
            content.secondaryText = "Visit a few websites, then return to Xavier."
            cell.accessoryType = .none
            cell.contentConfiguration = content
            
            let selectedView = UIView()
            selectedView.backgroundColor = AppColors.highlight.color.withAlphaComponent(0.12)
            cell.selectedBackgroundView = selectedView
            return cell
        }

        let summary = summaries[indexPath.row]
        let methodText = summary.methods.sorted().joined(separator: ", ")
        let appText = summary.apps.map { $0.commonName }.sorted().joined(separator: ", ")
        content.text = summary.host
        content.secondaryText = "\(summary.requestCount) item\(summary.requestCount == 1 ? "" : "s") • \(methodText.isEmpty ? "Metadata only" : methodText) • \(appText)"
        cell.contentConfiguration = content

        let selectedView = UIView()
        selectedView.backgroundColor = AppColors.highlight.color.withAlphaComponent(0.12)
        cell.selectedBackgroundView = selectedView

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !summaries.isEmpty else { return }
        navigationController?.pushViewController(WebsiteDetailViewController(host: summaries[indexPath.row].host), animated: true)
    }
}
