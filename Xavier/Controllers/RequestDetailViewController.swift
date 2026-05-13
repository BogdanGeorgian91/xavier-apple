import UIKit

final class RequestDetailViewController: UITableViewController {
    private enum Section: Int, CaseIterable {
        case overview
        case request
        case response
        case parent

        var title: String {
            switch self {
            case .overview: return "Overview"
            case .request: return "Request"
            case .response: return "Response"
            case .parent: return "Parent Page"
            }
        }
    }

    private let event: UnifiedNetworkEvent
    private let timestampFormatter = DateFormatter()
    private let byteFormatter = ByteCountFormatter()

    init(unifiedEvent: UnifiedNetworkEvent) {
        self.event = unifiedEvent
        super.init(style: .insetGrouped)
    }

    init(event: BrowserEventSnapshot) {
        self.event = UnifiedNetworkEvent(
            identifier: event.identifier,
            timestamp: event.timestamp,
            app: event.app,
            host: event.host,
            ipAddress: nil,
            port: nil,
            localIP: nil,
            localPort: nil,
            bytesInbound: 0,
            bytesOutbound: 0,
            transportProtocol: nil,
            direction: nil,
            url: event.url,
            httpMethod: event.httpMethod,
            requestHeaders: event.requestHeaders,
            requestBody: event.requestBody,
            statusCode: event.statusCode > 0 ? event.statusCode : nil,
            responseHeaders: event.responseHeaders,
            parentURL: event.parentURL,
            contentType: event.contentType
        )
        super.init(style: .insetGrouped)
    }

    required init?(coder aDecoder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = event.host ?? "Request"
        navigationItem.largeTitleDisplayMode = .never
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 88
        tableView.backgroundColor = AppColors.surface.color
        tableView.separatorColor = AppColors.separator.color
        tableView.tableFooterView = UIView(frame: .zero)

        timestampFormatter.dateStyle = .medium
        timestampFormatter.timeStyle = .medium
        byteFormatter.countStyle = .file
        byteFormatter.allowsNonnumericFormatting = false
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return Section(rawValue: section)?.title
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else { return 0 }
        switch section {
        case .overview:
            return 9
        case .request:
            return 3
        case .response:
            return 3
        case .parent:
            return 1
        }
    }

    override func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        guard let header = view as? UITableViewHeaderFooterView else { return }
        header.textLabel?.textColor = AppColors.background.color
        header.textLabel?.font = UIFont(name: "FiraSans-Bold", size: 17)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "RequestDetailCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "RequestDetailCell")
        cell.backgroundColor = AppColors.surfaceElevated.color
        cell.selectionStyle = .none

        let pair = detailPair(for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = pair.title
        content.secondaryText = pair.value
        content.textProperties.font = UIFont(name: "FiraSans-Bold", size: 15) ?? UIFont.boldSystemFont(ofSize: 15)
        content.textProperties.color = AppColors.textPrimary.color
        content.secondaryTextProperties.font = pair.monospace ? (UIFont(name: "FiraMono-Regular", size: 13) ?? UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)) : (UIFont(name: "FiraSans-Regular", size: 14) ?? UIFont.systemFont(ofSize: 14))
        content.secondaryTextProperties.color = AppColors.textSecondary.color
        content.secondaryTextProperties.numberOfLines = 0
        cell.contentConfiguration = content
        return cell
    }

    private func detailPair(for indexPath: IndexPath) -> (title: String, value: String, monospace: Bool) {
        guard let section = Section(rawValue: indexPath.section) else {
            return ("Unknown", "", false)
        }

        switch section {
        case .overview:
            switch indexPath.row {
            case 0: return ("URL", event.url ?? "URL not exposed for this flow", true)
            case 1: return ("Host", event.host ?? event.ipAddress ?? "Host not exposed for this flow", false)
            case 2: return ("App", "\(event.app.commonName) (\(event.app))", false)
            case 3: return ("Method", event.httpMethod ?? "HTTP method not exposed for this flow", false)
            case 4: return ("Timestamp", timestampFormatter.string(from: event.timestamp), false)
            case 5: return ("Protocol", event.transportProtocol?.uppercased() ?? "Unknown", false)
            case 6: return ("Direction", event.direction?.capitalized ?? "Unknown", false)
            case 7: return ("Data Transferred", "\(byteFormatter.string(fromByteCount: event.bytesInbound)) in • \(byteFormatter.string(fromByteCount: event.bytesOutbound)) out", false)
            default: return ("Content Type", event.contentType ?? "Content type not exposed for this flow", false)
            }
        case .request:
            switch indexPath.row {
            case 0: return ("Full URL", event.url ?? "Full URL not exposed for this flow", true)
            case 1: return ("Headers", nonEmpty(event.requestHeaders, fallback: "Request headers not exposed for this flow."), true)
            default: return ("Body", nonEmpty(event.requestBody, fallback: "Request body not exposed for this flow."), true)
            }
        case .response:
            switch indexPath.row {
            case 0: return ("Status", (event.statusCode ?? 0) > 0 ? "HTTP \(event.statusCode!)" : "Response status not exposed for this flow.", false)
            case 1: return ("Headers", nonEmpty(event.responseHeaders, fallback: "Response headers not exposed for this flow."), true)
            default: return ("Body", nonEmpty(nil, fallback: "Response body is not exposed as URLResponse metadata. Xavier currently captures URLRequest/URLResponse fields, not full response payloads."), true)
            }
        case .parent:
            return ("Parent URL", event.parentURL ?? "Parent page URL not exposed for this flow.", true)
        }
    }

    private func nonEmpty(_ value: String?, fallback: String) -> String {
        guard let value = value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return fallback
        }
        return value
    }
}
