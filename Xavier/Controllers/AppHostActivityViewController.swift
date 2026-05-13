import UIKit

final class AppHostActivityViewController: UITableViewController {
    private let appIdentifier: AppName
    private let host: String
    private let timestampFormatter = DateFormatter()
    private let byteFormatter = ByteCountFormatter()
    private var events = [UnifiedNetworkEvent]()

    init(appIdentifier: AppName, host: String) {
        self.appIdentifier = appIdentifier
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
        
        byteFormatter.countStyle = .file
        byteFormatter.allowsNonnumericFormatting = false
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadData()
    }

    private func reloadData() {
        do {
            events = try NetworkEventManager.shared.fetchUnifiedEvents(for: appIdentifier, host: host)
            updateHeader()
            tableView.reloadData()
        } catch {
            events = []
            updateHeader()
            tableView.reloadData()
            showWarning(title: "Unable to Load Activity", body: "Xavier couldn't load saved requests. \(error)")
        }
    }
    
    private func updateHeader() {
        guard let firstEventWithLocalInfo = events.first(where: { $0.localIP != nil || $0.localPort != nil }) else {
            tableView.tableHeaderView = nil
            return
        }

        let titleLabel = UILabel()
        titleLabel.font = UIFont(name: "FiraSans-Medium", size: 15) ?? UIFont.systemFont(ofSize: 15, weight: .medium)
        titleLabel.textColor = AppColors.textPrimary.color
        titleLabel.text = "Local connection"

        let subtitle = UILabel()
        subtitle.font = UIFont(name: "FiraSans-Regular", size: 14) ?? UIFont.systemFont(ofSize: 14)
        subtitle.textColor = AppColors.textSecondary.color
        
        var parts = [String]()
        if let ip = firstEventWithLocalInfo.localIP {
            parts.append("IP: \(ip)")
        }
        if let port = firstEventWithLocalInfo.localPort, port > 0 {
            parts.append("Port: \(port)")
        }
        subtitle.text = parts.joined(separator: " • ")

        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitle])
        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false

        let card = UIView()
        card.backgroundColor = AppColors.surfaceElevated.color
        card.layer.cornerRadius = 12
        card.addSubview(stack)
        card.translatesAutoresizingMaskIntoConstraints = false

        let container = UIView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 1))
        container.backgroundColor = .clear
        container.addSubview(card)

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            card.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            card.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            card.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),

            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12)
        ])

        let targetSize = CGSize(width: tableView.bounds.width, height: UIView.layoutFittingCompressedSize.height)
        let size = container.systemLayoutSizeFitting(targetSize,
                                                     withHorizontalFittingPriority: .required,
                                                     verticalFittingPriority: .fittingSizeLevel)
        container.frame.size.height = ceil(size.height)
        tableView.tableHeaderView = container
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return "Connections"
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return max(events.count, 1)
    }

    override func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        guard let header = view as? UITableViewHeaderFooterView else { return }
        header.textLabel?.textColor = AppColors.textSecondary.color
        header.textLabel?.font = UIFont.systemFont(ofSize: 14, weight: .regular)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "AppHostActivityCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "AppHostActivityCell")
        cell.backgroundColor = AppColors.surfaceElevated.color
        cell.tintColor = AppColors.highlight.color

        var content = cell.defaultContentConfiguration()
        content.textProperties.font = UIFont(name: "FiraSans-Bold", size: 16) ?? UIFont.boldSystemFont(ofSize: 16)
        content.textProperties.color = AppColors.textPrimary.color
        content.textProperties.numberOfLines = 0
        content.secondaryTextProperties.font = UIFont(name: "FiraSans-Regular", size: 14) ?? UIFont.systemFont(ofSize: 14)
        content.secondaryTextProperties.color = AppColors.textSecondary.color
        content.secondaryTextProperties.numberOfLines = 0

        guard !events.isEmpty else {
            content.text = "No connections recorded"
            content.secondaryText = "Make some network requests in the app, then return here."
            cell.accessoryType = .none
            cell.contentConfiguration = content
            
            let selectedView = UIView()
            selectedView.backgroundColor = AppColors.highlight.color.withAlphaComponent(0.12)
            cell.selectedBackgroundView = selectedView
            return cell
        }

        let event = events[indexPath.row]
        
        let status = (event.statusCode ?? 0) > 0 ? " • HTTP \(event.statusCode!)" : ""
        let method = event.methodText
        content.text = "\(method) \(event.urlText)"
        
        var meta = [String]()
        meta.append(timestampFormatter.string(from: event.timestamp))
        let inBytes = event.bytesInbound > 0 ? byteFormatter.string(fromByteCount: event.bytesInbound) : "0 KB"
        let outBytes = event.bytesOutbound > 0 ? byteFormatter.string(fromByteCount: event.bytesOutbound) : "0 KB"
        meta.append("\(inBytes) ↓  \(outBytes) ↑")
        
        content.secondaryText = "\(meta.joined(separator: " • "))\(status)\n\(event.parentURL.map { "Parent: \($0)" } ?? "Flow ID: \(event.identifier ?? "Unknown")")"
        
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
        navigationController?.pushViewController(RequestDetailViewController(unifiedEvent: events[indexPath.row]), animated: true)
    }
}
