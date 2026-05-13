import UIKit

final class InspectorRequestDetailViewController: UITableViewController {
    private enum Section: Int, CaseIterable {
        case overview
        case request
        case response
        case modifications
    }

    private let requestSnapshot: InspectedRequestSnapshot
    private let formatter = DateFormatter()
    private let byteFormatter = ByteCountFormatter()

    init(request: InspectedRequestSnapshot) {
        self.requestSnapshot = request
        super.init(style: .insetGrouped)
    }

    required init?(coder aDecoder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = requestSnapshot.host ?? "Request"
        navigationItem.largeTitleDisplayMode = .never
        tableView.backgroundColor = AppColors.surface.color
        tableView.separatorColor = AppColors.separator.color
        tableView.tableFooterView = UIView(frame: .zero)
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        byteFormatter.countStyle = .file
        byteFormatter.allowedUnits = [.useKB, .useMB, .useGB, .useBytes]
        byteFormatter.includesUnit = true
        byteFormatter.isAdaptive = true
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return requestSnapshot.requestModified || requestSnapshot.responseModified ? Section.allCases.count : Section.allCases.count - 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let resolved = visibleSection(for: section)
        switch resolved {
        case .overview:
            return 10
        case .request:
            return 3
        case .response:
            return 3
        case .modifications:
            return 4
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch visibleSection(for: section) {
        case .overview: return "Overview"
        case .request: return "Request"
        case .response: return "Response"
        case .modifications:
            if requestSnapshot.requestModified && requestSnapshot.responseModified {
                return "Modifications"
            } else if requestSnapshot.requestModified {
                return "Request Modifications"
            } else {
                return "Response Modifications"
            }
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "InspectorRequestDetailCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "InspectorRequestDetailCell")
        cell.selectionStyle = .none
        cell.backgroundColor = AppColors.surfaceElevated.color

        let pair = detailPair(for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = pair.title
        content.secondaryText = pair.value
        content.textProperties.font = UIFont(name: "FiraSans-Bold", size: 15) ?? .boldSystemFont(ofSize: 15)
        content.textProperties.color = AppColors.textPrimary.color
        content.secondaryTextProperties.font = pair.monospace ? (UIFont(name: "FiraMono-Regular", size: 13) ?? UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)) : (UIFont(name: "FiraSans-Regular", size: 14) ?? .systemFont(ofSize: 14))
        content.secondaryTextProperties.color = AppColors.textSecondary.color
        content.secondaryTextProperties.numberOfLines = 0
        cell.contentConfiguration = content
        return cell
    }

    private func visibleSection(for section: Int) -> Section {
        if requestSnapshot.requestModified || requestSnapshot.responseModified {
            return Section(rawValue: section)!
        }
        return [Section.overview, .request, .response][section]
    }

    private func detailPair(for indexPath: IndexPath) -> (title: String, value: String, monospace: Bool) {
        switch visibleSection(for: indexPath.section) {
        case .overview:
            switch indexPath.row {
            case 0: return ("URL", requestSnapshot.url ?? "Unknown", true)
            case 1: return ("Host", requestSnapshot.host ?? "Unknown", false)
            case 2: return ("App", appIdentifier(for: requestSnapshot), false)
            case 3: return ("Method", requestSnapshot.httpMethod ?? "Unknown", false)
            case 4: return ("Timestamp", formatter.string(from: requestSnapshot.timestamp), false)
            case 5: return ("TLS", requestSnapshot.tlsVersion ?? "Plaintext", false)
            case 6: return ("Duration", requestSnapshot.duration > 0 ? String(format: "%.3fs", requestSnapshot.duration) : "N/A", false)
            case 7: return ("Port", "\(requestSnapshot.port)", false)
            case 8: return ("Pinned", requestSnapshot.pinned ? "Yes — certificate pinning detected" : "No", false)
            default: return ("Blocked", requestSnapshot.blocked ? (requestSnapshot.blockedReason ?? "Yes") : "No", false)
            }
        case .request:
            switch indexPath.row {
            case 0: return ("Headers", nonEmpty(requestSnapshot.requestHeaders, fallback: "No request headers captured."), true)
            case 1: return ("Body", bodyText(from: requestSnapshot.requestBody), true)
            default: return ("Original Headers", nonEmpty(requestSnapshot.originalRequestHeaders, fallback: "No original request headers."), true)
            }
        case .response:
            switch indexPath.row {
            case 0: return ("Status", requestSnapshot.statusCode > 0 ? "HTTP \(requestSnapshot.statusCode) \(HTTPStatusHelper.description(for: Int(requestSnapshot.statusCode)))" : "Pending", false)
            case 1: return ("Headers", nonEmpty(requestSnapshot.responseHeaders, fallback: "No response headers captured."), true)
            default: return ("Body", bodyText(from: requestSnapshot.responseBody), true)
            }
        case .modifications:
            if requestSnapshot.requestModified && !requestSnapshot.responseModified {
                switch indexPath.row {
                case 0: return ("Request Modified", "Yes — headers or body were changed", false)
                case 1: return ("Original Headers", nonEmpty(requestSnapshot.originalRequestHeaders, fallback: "Not captured."), true)
                case 2: return ("Original Body", bodyText(from: requestSnapshot.originalRequestBody), true)
                default: return ("Modified Headers", nonEmpty(requestSnapshot.requestHeaders, fallback: "Not available."), true)
                }
            } else if !requestSnapshot.requestModified && requestSnapshot.responseModified {
                switch indexPath.row {
                case 0: return ("Response Modified", requestSnapshot.blockedReason == "script_stripped" ? "Yes — \(requestSnapshot.blockedReason ?? "scripts stripped")" : "Yes", false)
                case 1: return ("Original Headers", nonEmpty(requestSnapshot.originalResponseHeaders, fallback: "Not captured."), true)
                case 2: return ("Original Body", bodyText(from: requestSnapshot.originalResponseBody), true)
                default: return ("Modified Headers", nonEmpty(requestSnapshot.responseHeaders, fallback: "Not available."), true)
                }
            } else {
                switch indexPath.row {
                case 0: return ("Request Modified", "Yes", false)
                case 1: return ("Response Modified", requestSnapshot.blockedReason == "script_stripped" ? "Yes — scripts stripped" : "Yes", false)
                case 2: return ("Original Request Headers", nonEmpty(requestSnapshot.originalRequestHeaders, fallback: "Not captured."), true)
                default: return ("Original Response Headers", nonEmpty(requestSnapshot.originalResponseHeaders, fallback: "Not captured."), true)
                }
            }
        }
    }

    private func nonEmpty(_ value: String?, fallback: String) -> String {
        guard let value = value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return fallback
        }
        return value
    }

    private func appIdentifier(for snapshot: InspectedRequestSnapshot) -> String {
        guard let bundleID = snapshot.appBundleID, !bundleID.isEmpty else {
            return snapshot.appName.contains(".") ? snapshot.appName : "Unknown Bundle ID"
        }
        return bundleID
    }

    private func bodyText(from data: Data?) -> String {
        guard let data = data, !data.isEmpty else {
            return "No body captured."
        }
        let sizeText = byteFormatter.string(fromByteCount: Int64(data.count))
        if let string = decodedText(from: data) {
            return "\(sizeText)\n\n\(string)"
        }
        return "\(sizeText) of binary data"
    }

    private func decodedText(from data: Data) -> String? {
        if let string = String(data: data, encoding: .utf8), !string.isEmpty {
            return string
        }
        if let string = String(data: data, encoding: .ascii), !string.isEmpty {
            return string
        }
        return nil
    }
}

struct HTTPStatusHelper {
    static func description(for code: Int) -> String {
        switch code {
        case 100: return "Continue"
        case 101: return "Switching Protocols"
        case 200: return "OK"
        case 201: return "Created"
        case 202: return "Accepted"
        case 203: return "Non-Authoritative Information"
        case 204: return "No Content"
        case 205: return "Reset Content"
        case 206: return "Partial Content"
        case 300: return "Multiple Choices"
        case 301: return "Moved Permanently"
        case 302: return "Found"
        case 303: return "See Other"
        case 304: return "Not Modified"
        case 307: return "Temporary Redirect"
        case 308: return "Permanent Redirect"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 406: return "Not Acceptable"
        case 407: return "Proxy Authentication Required"
        case 408: return "Request Timeout"
        case 409: return "Conflict"
        case 410: return "Gone"
        case 411: return "Length Required"
        case 412: return "Precondition Failed"
        case 413: return "Payload Too Large"
        case 414: return "URI Too Long"
        case 415: return "Unsupported Media Type"
        case 416: return "Range Not Satisfiable"
        case 417: return "Expectation Failed"
        case 418: return "I'm a teapot"
        case 421: return "Misdirected Request"
        case 422: return "Unprocessable Entity"
        case 423: return "Locked"
        case 424: return "Failed Dependency"
        case 425: return "Too Early"
        case 426: return "Upgrade Required"
        case 428: return "Precondition Required"
        case 429: return "Too Many Requests"
        case 431: return "Request Header Fields Too Large"
        case 451: return "Unavailable For Legal Reasons"
        case 500: return "Internal Server Error"
        case 501: return "Not Implemented"
        case 502: return "Bad Gateway"
        case 503: return "Service Unavailable"
        case 504: return "Gateway Timeout"
        case 505: return "HTTP Version Not Supported"
        case 506: return "Variant Also Negotiates"
        case 507: return "Insufficient Storage"
        case 508: return "Loop Detected"
        case 510: return "Not Extended"
        case 511: return "Network Authentication Required"
        default: return "Unknown Status"
        }
    }
}
