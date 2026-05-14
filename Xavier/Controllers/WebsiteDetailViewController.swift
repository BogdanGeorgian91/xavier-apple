import UIKit
import XavierShared

final class WebsiteDetailViewController: UITableViewController {
    private let host: String
    private let timestampFormatter = DateFormatter()
    private var events = [BrowserEventSnapshot]()

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
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 88
        tableView.backgroundColor = AppColors.surface.color
        tableView.separatorColor = AppColors.separator.color
        tableView.tableFooterView = UIView(frame: .zero)

        timestampFormatter.dateStyle = .medium
        timestampFormatter.timeStyle = .medium
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadData()
    }

    private func reloadData() {
        do {
            events = try BrowserEventManager.shared.fetchEvents(forPage: host)
            tableView.reloadData()
        } catch {
            events = []
            tableView.reloadData()
            showWarning(title: "Unable to Load Website Activity", body: "Xavier couldn't load saved requests for this website. \(error)")
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return "Requests"
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return max(events.count, 1)
    }

    override func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        guard let header = view as? UITableViewHeaderFooterView else { return }
        header.textLabel?.textColor = AppColors.background.color
        header.textLabel?.font = UIFont(name: "FiraSans-Bold", size: 16)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "BrowserRequestCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "BrowserRequestCell")
        cell.backgroundColor = AppColors.surfaceElevated.color
        cell.tintColor = AppColors.highlight.color

        var content = cell.defaultContentConfiguration()
        content.textProperties.font = UIFont(name: "FiraSans-Bold", size: 15) ?? UIFont.boldSystemFont(ofSize: 15)
        content.textProperties.color = AppColors.textPrimary.color
        content.textProperties.numberOfLines = 2
        content.secondaryTextProperties.font = UIFont(name: "FiraSans-Regular", size: 13) ?? UIFont.systemFont(ofSize: 13)
        content.secondaryTextProperties.color = AppColors.textSecondary.color
        content.secondaryTextProperties.numberOfLines = 3

        guard !events.isEmpty else {
            content.text = "No requests recorded"
            content.secondaryText = "Open this page in Safari, then return here."
            cell.accessoryType = .none
            cell.contentConfiguration = content
            
            let selectedView = UIView()
            selectedView.backgroundColor = AppColors.highlight.color.withAlphaComponent(0.12)
            cell.selectedBackgroundView = selectedView
            return cell
        }

        let event = events[indexPath.row]
        let method = event.httpMethod ?? "FLOW"
        let status = event.statusCode > 0 ? " • HTTP \(event.statusCode)" : ""
        content.text = "\(method) \(displayPath(for: event.url))"
        content.secondaryText = "\(timestampFormatter.string(from: event.timestamp))\(status)\n\(event.parentURL.map { "Parent: \($0)" } ?? "No parent URL")"
        cell.accessoryType = .disclosureIndicator
        cell.contentConfiguration = content
        
        let selectedView = UIView()
        selectedView.backgroundColor = AppColors.highlight.color.withAlphaComponent(0.12)
        cell.selectedBackgroundView = selectedView
        
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !events.isEmpty else { return }
        navigationController?.pushViewController(RequestDetailViewController(event: events[indexPath.row]), animated: true)
    }

    private func displayPath(for urlString: String?) -> String {
        guard let urlString = urlString, let url = URL(string: urlString) else {
            return "/"
        }

        let path = url.path.isEmpty ? "/" : url.path
        if let query = url.query, !query.isEmpty {
            return "\(path)?\(query)"
        }
        return path
    }
}
