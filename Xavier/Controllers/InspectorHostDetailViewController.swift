import UIKit
import XavierShared

final class InspectorAppRequestListViewController: UITableViewController {
    private let site: String
    private let appBundleID: String
    private let formatter = DateFormatter()
    private var requests = [InspectedRequestSnapshot]()

    init(site: String, appBundleID: String) {
        self.site = site
        self.appBundleID = appBundleID
        super.init(style: .insetGrouped)
    }

    required init?(coder aDecoder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = appBundleID
        navigationItem.largeTitleDisplayMode = .never
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 88
        tableView.backgroundColor = AppColors.surface.color
        tableView.separatorColor = AppColors.separator.color
        tableView.tableFooterView = UIView(frame: .zero)
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        
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
            requests = try InspectionManager.shared.fetchRequests(site: site, appBundleID: appBundleID)
            tableView.reloadData()
        } catch {
            requests = []
            tableView.reloadData()
            showWarning(title: "Unable to Load Requests", body: "Xavier couldn't load requests for this app.")
        }
        tableView.refreshControl?.endRefreshing()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return "Requests Captured"
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return max(requests.count, 1)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "InspectorHostCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "InspectorHostCell")
        cell.backgroundColor = AppColors.surfaceElevated.color
        cell.tintColor = AppColors.highlight.color

        var content = cell.defaultContentConfiguration()
        content.textProperties.font = UIFont(name: "FiraSans-Bold", size: 16) ?? .boldSystemFont(ofSize: 16)
        content.textProperties.color = AppColors.textPrimary.color
        content.textProperties.numberOfLines = 0
        content.secondaryTextProperties.font = UIFont(name: "FiraSans-Regular", size: 14) ?? .systemFont(ofSize: 14)
        content.secondaryTextProperties.color = AppColors.textSecondary.color
        content.secondaryTextProperties.numberOfLines = 0

        guard !requests.isEmpty else {
            content.text = "No requests recorded"
            content.secondaryText = "Use this app to browse the selected site and return here."
            cell.accessoryType = .none
            cell.contentConfiguration = content
            return cell
        }

        let request = requests[indexPath.row]
        let method = request.httpMethod ?? "FLOW"
        let path = displayPath(for: request.url)
        let status = request.statusCode > 0 ? "HTTP \(request.statusCode) \(HTTPStatusHelper.description(for: Int(request.statusCode)))" : (request.blocked ? "Blocked" : "Pending")
        content.text = "\(method) \(path)"
        content.secondaryText = "\(request.host ?? "Unknown Host") • \(formatter.string(from: request.timestamp)) • \(status)"
        
        if request.blocked || request.blockedReason == "script_stripped" {
            content.textProperties.color = AppColors.deny.color
        } else if method != "FLOW" {
            content.textProperties.color = AppColors.allow.color
        }
        
        cell.accessoryType = .disclosureIndicator
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !requests.isEmpty else { return }
        navigationController?.pushViewController(InspectorRequestDetailViewController(request: requests[indexPath.row]), animated: true)
    }

    private func displayPath(for urlString: String?) -> String {
        guard let urlString = urlString, let url = URL(string: urlString) else {
            return "/"
        }
        let path = url.path.isEmpty ? "/" : url.path
        if let query = url.query, !query.isEmpty {
            return path + "?" + query
        }
        return path
    }
}
