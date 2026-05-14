import UIKit
import XavierShared

final class InspectorSiteDetailViewController: UITableViewController {
    private let site: String
    private let formatter = DateFormatter()
    private var apps = [InspectorAppSummary]()

    init(site: String) {
        self.site = site
        super.init(style: .insetGrouped)
    }

    required init?(coder aDecoder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = site
        navigationItem.largeTitleDisplayMode = .never
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 88
        tableView.backgroundColor = AppColors.surface.color
        tableView.separatorColor = AppColors.separator.color
        tableView.tableFooterView = UIView(frame: .zero)
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(reloadData), for: .valueChanged)
        tableView.refreshControl = refreshControl
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadData()
    }

    @objc private func reloadData() {
        do {
            apps = try InspectionManager.shared.fetchAppSummaries(site: site)
            tableView.reloadData()
        } catch {
            apps = []
            tableView.reloadData()
            showWarning(title: "Unable to Load Apps", body: "Xavier couldn't load apps for this site.")
        }
        tableView.refreshControl?.endRefreshing()
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return "Apps Contacting Site"
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return max(apps.count, 1)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "InspectorSiteAppCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "InspectorSiteAppCell")
        cell.backgroundColor = AppColors.surfaceElevated.color
        cell.tintColor = AppColors.highlight.color

        var content = cell.defaultContentConfiguration()
        content.textProperties.font = UIFont(name: "FiraSans-Bold", size: 16) ?? .boldSystemFont(ofSize: 16)
        content.textProperties.color = AppColors.textPrimary.color
        content.textProperties.numberOfLines = 0
        content.secondaryTextProperties.font = UIFont(name: "FiraSans-Regular", size: 14) ?? .systemFont(ofSize: 14)
        content.secondaryTextProperties.color = AppColors.textSecondary.color
        content.secondaryTextProperties.numberOfLines = 0

        guard !apps.isEmpty else {
            content.text = "No apps recorded"
            content.secondaryText = "Browse this site and return here."
            cell.accessoryType = .none
            cell.contentConfiguration = content
            return cell
        }

        let app = apps[indexPath.row]
        let methods = app.methods.sorted().joined(separator: ", ")
        content.text = app.appBundleID
        content.secondaryText = "\(formatter.string(from: app.lastTimestamp)) • \(app.hostCount) host\(app.hostCount == 1 ? "" : "s") • \(app.requestCount) request\(app.requestCount == 1 ? "" : "s") • \(methods.isEmpty ? "Metadata only" : methods)"
        
        if containsHTTPMethod(app.methods) {
            content.textProperties.color = AppColors.allow.color
        }
        
        cell.accessoryType = .disclosureIndicator
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !apps.isEmpty else { return }
        navigationController?.pushViewController(InspectorAppRequestListViewController(site: site, appBundleID: apps[indexPath.row].appBundleID), animated: true)
    }

    private func containsHTTPMethod(_ methods: Set<String>) -> Bool {
        return methods.contains { method in
            let normalized = method.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            return !normalized.isEmpty && normalized != "FLOW"
        }
    }
}
