//
//  AppDetailViewController.swift
//  Xavier
//
//  Created by OpenCode on 4/5/26.
//

import UIKit
import XavierShared

final class AppDetailViewController: UITableViewController {
    private enum Section: Int {
        case summary = 0
        case recentActivity = 1
    }

    private let appIdentifier: AppName
    private let byteFormatter = ByteCountFormatter()
    private let timestampFormatter = DateFormatter()
    private var allEvents = [NetworkEventSnapshot]()
    private var events = [NetworkEventSnapshot]()
    private let directionSegmentedControl = UISegmentedControl(items: ["All", "Outbound", "Inbound"])
    private var currentStatusDescription = "Recording activity normally"
    private let blockAllSwitch = UISwitch()
    private let muteNotificationsSwitch = UISwitch()

    init(appIdentifier: AppName) {
        self.appIdentifier = appIdentifier
        super.init(style: .insetGrouped)
    }

    required init?(coder aDecoder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = appIdentifier.commonName.capitalized
        navigationItem.largeTitleDisplayMode = .never
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72
        tableView.backgroundColor = AppColors.surface.color
        tableView.separatorColor = AppColors.separator.color
        tableView.tableFooterView = UIView(frame: .zero)

        byteFormatter.countStyle = .file
        byteFormatter.allowsNonnumericFormatting = false
        timestampFormatter.dateStyle = .medium
        timestampFormatter.timeStyle = .short

        blockAllSwitch.onTintColor = AppColors.deny.color
        blockAllSwitch.addTarget(self, action: #selector(blockAllChanged(_:)), for: .valueChanged)

        muteNotificationsSwitch.onTintColor = AppColors.highlight.color
        muteNotificationsSwitch.addTarget(self, action: #selector(muteNotificationsChanged(_:)), for: .valueChanged)
        
        directionSegmentedControl.selectedSegmentIndex = 0
        directionSegmentedControl.addTarget(self, action: #selector(directionFilterChanged), for: .valueChanged)
        directionSegmentedControl.selectedSegmentTintColor = AppColors.highlight.color
        directionSegmentedControl.setTitleTextAttributes([NSAttributedString.Key.foregroundColor: AppColors.background.color], for: .selected)
        directionSegmentedControl.setTitleTextAttributes([NSAttributedString.Key.foregroundColor: AppColors.textPrimary.color], for: .normal)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(updateMetadata),
                                               name: NSNotification.Name("AppMetadataUpdated"),
                                               object: nil)

    }
    
    @objc private func updateMetadata() {
        self.title = appIdentifier.commonName.capitalized
        self.tableView.reloadData()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        reloadData()
    }

    private func reloadData() {
        do {
            allEvents = try NetworkEventManager.shared.fetchEvents(for: appIdentifier, limit: 100)
            applyFilter()
            muteNotificationsSwitch.isOn = !Constants.isNotificationMuted(for: appIdentifier)

            do {
                blockAllSwitch.isOn = try isBlockingAllTraffic()
                currentStatusDescription = try buildCurrentStatusText()
            } catch {
                blockAllSwitch.isOn = false
                currentStatusDescription = muteNotificationsSwitch.isOn ? "Recording activity normally" : "Notifications muted"
            }

            tableView.reloadData()
        } catch {
            allEvents = []
            events = []
            blockAllSwitch.isOn = false
            muteNotificationsSwitch.isOn = true
            currentStatusDescription = "Status unavailable right now"
            tableView.reloadData()
        }
    }
    
    @objc private func directionFilterChanged() {
        applyFilter()
        tableView.reloadSections(IndexSet(integer: Section.recentActivity.rawValue), with: .none)
    }
    
    private func applyFilter() {
        switch directionSegmentedControl.selectedSegmentIndex {
        case 1:
            events = allEvents.filter { $0.direction?.lowercased() == "outbound" }
        case 2:
            events = allEvents.filter { $0.direction?.lowercased() == "inbound" }
        default:
            events = allEvents
        }
    }
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .summary:
            return 8
        case .recentActivity:
            return max(events.count, 1)
        }
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        if section == Section.recentActivity.rawValue {
            let container = UIView()
            let label = UILabel()
            label.text = "Recent connections"
            label.font = UIFont.systemFont(ofSize: 13, weight: .regular)
            label.textColor = AppColors.textSecondary.color
            label.translatesAutoresizingMaskIntoConstraints = false
            
            directionSegmentedControl.translatesAutoresizingMaskIntoConstraints = false
            
            container.addSubview(label)
            container.addSubview(directionSegmentedControl)
            
            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
                label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
                label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
                
                directionSegmentedControl.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 8),
                directionSegmentedControl.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
                directionSegmentedControl.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
                directionSegmentedControl.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12)
            ])
            return container
        }
        return nil
    }
    
    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return UITableView.automaticDimension
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == Section.summary.rawValue { return "At a glance" }
        return nil
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .summary:
            return "Block all traffic overrides host-specific rules for this app. Live alerts are off by default; turn them on to receive notifications for this app. Use the Rules tab to choose between new-host-only or all-activity notifications.\n\nThe connection initiation direction (Inbound/Outbound) indicates whether the app or the server started the connection. Almost all iOS apps act as clients, meaning they initiate Outbound connections to a server. When the server replies with data, it comes back over that same Outbound connection."
        case .recentActivity:
            return events.isEmpty ? nil : "Showing the 100 most recent saved events for this app."
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section)! {
        case .summary:
            return summaryCell(for: indexPath.row)
        case .recentActivity:
            return activityCell(for: indexPath.row)
        }
    }

    private func summaryCell(for row: Int) -> UITableViewCell {
        let reuseIdentifier = row < 4 ? "SummarySubtitleCell" : "SummaryValueCell"
        let style: UITableViewCell.CellStyle = row < 4 ? .subtitle : .value1
        let cell = tableView.dequeueReusableCell(withIdentifier: reuseIdentifier) ?? UITableViewCell(style: style, reuseIdentifier: reuseIdentifier)

        cell.selectionStyle = .none
        cell.backgroundColor = AppColors.surfaceElevated.color
        cell.accessoryView = nil

        var content = row < 4 ? cell.defaultContentConfiguration() : UIListContentConfiguration.valueCell()

        let totalInbound = events.reduce(Int64(0)) { $0 + $1.bytesInbound }
        let totalOutbound = events.reduce(Int64(0)) { $0 + $1.bytesOutbound }

        switch row {
        case 0:
            content.text = "Bundle Identifier"
            content.secondaryText = appIdentifier
        case 1:
            content.text = "Current status"
            content.secondaryText = currentStatusDescription
        case 2:
            content.text = "App-wide block"
            content.secondaryText = blockAllSwitch.isOn ? "All traffic from this app will be denied." : "Traffic follows any matching host rules."
            cell.accessoryView = blockAllSwitch
        case 3:
            content.text = "Live alerts"
            if !muteNotificationsSwitch.isOn {
                content.secondaryText = "Alerts are muted. Activity is still recorded."
            } else if Constants.isAllActivityMode {
                content.secondaryText = "You'll be notified on each connection (throttled)."
            } else {
                content.secondaryText = "You'll be notified when this app reaches a new host."
            }
            cell.accessoryView = muteNotificationsSwitch
        case 4:
            content.text = "Saved events"
            content.secondaryText = "\(events.count) recent connections"
        case 5:
            content.text = "Data transfer"
            let inText = totalInbound > 0 ? byteFormatter.string(fromByteCount: totalInbound) : "0 KB"
            let outText = totalOutbound > 0 ? byteFormatter.string(fromByteCount: totalOutbound) : "0 KB"
            content.secondaryText = "\(inText) in • \(outText) out"
        case 6:
            content.text = "Last connection initiation"
            if let lastEvent = events.first {
                let isInbound = lastEvent.direction?.lowercased() == "inbound"
                content.secondaryText = isInbound ? "Inbound" : "Outbound"
            } else {
                content.secondaryText = "Unknown"
            }
        default:
            content.text = "Last seen"
            if let lastEvent = events.first {
                content.secondaryText = timestampFormatter.string(from: lastEvent.timestamp)
            } else {
                content.secondaryText = "Never"
            }
        }
        
        content.textProperties.color = AppColors.textPrimary.color
        content.textProperties.font = UIFont(name: "FiraSans-Medium", size: 15) ?? UIFont.systemFont(ofSize: 15, weight: .medium)
        content.secondaryTextProperties.color = AppColors.textSecondary.color
        content.secondaryTextProperties.font = UIFont(name: "FiraSans-Regular", size: 15) ?? UIFont.systemFont(ofSize: 15)
        content.secondaryTextProperties.numberOfLines = 0
        
        cell.contentConfiguration = content

        return cell
    }

    private func activityCell(for row: Int) -> UITableViewCell {
        guard !events.isEmpty else {
            let cell = tableView.dequeueReusableCell(withIdentifier: "EmptyActivityCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "EmptyActivityCell")
            cell.selectionStyle = .none
            cell.backgroundColor = AppColors.surfaceElevated.color
            
            var content = cell.defaultContentConfiguration()
            content.text = "No saved activity yet"
            content.secondaryText = "Generate some traffic in this app, then come back here to inspect the latest requests."
            content.textProperties.font = UIFont(name: "FiraSans-Medium", size: 15) ?? UIFont.systemFont(ofSize: 15, weight: .medium)
            content.textProperties.color = AppColors.textPrimary.color
            content.secondaryTextProperties.font = UIFont(name: "FiraSans-Regular", size: 13) ?? UIFont.systemFont(ofSize: 13)
            content.secondaryTextProperties.color = AppColors.textSecondary.color
            content.secondaryTextProperties.numberOfLines = 0
            cell.contentConfiguration = content
            return cell
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: "AppActivityCell") as? AppActivityCell ?? AppActivityCell(style: .default, reuseIdentifier: "AppActivityCell")
        let event = events[row]
        cell.configure(with: event, byteFormatter: byteFormatter, timestampFormatter: timestampFormatter)
        cell.accessoryType = .disclosureIndicator
        
        let selectedView = UIView()
        selectedView.backgroundColor = AppColors.highlight.color.withAlphaComponent(0.12)
        cell.selectedBackgroundView = selectedView
        
        return cell
    }

    private func buildCurrentStatusText() throws -> String {
        var statuses = [String]()

        if blockAllSwitch.isOn {
            statuses.append("Blocked for all traffic")
        } else if let latestHost = events.first?.host ?? events.first?.ipAddress,
                  let rule = try RuleManager().getRule(for: appIdentifier, hostname: latestHost) {
            switch rule.ruleType {
            case .app:
                break
            case .host, .hostFromApp:
                statuses.append(rule.isAllowed ? "Allowed rule active for latest host" : "Blocked rule active for latest host")
            }
        }

        if !muteNotificationsSwitch.isOn {
            statuses.append("Notifications muted")
        } else if Constants.isAllActivityMode {
            statuses.append("All activity alerts on")
        } else {
            statuses.append("New-host alerts on")
        }

        if statuses.isEmpty {
            return "Recording activity normally"
        }

        return statuses.joined(separator: " • ")
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == Section.recentActivity.rawValue {
            guard !events.isEmpty else { return }
            let event = events[indexPath.row]
            if let host = event.host ?? event.ipAddress {
                navigationController?.pushViewController(AppHostActivityViewController(appIdentifier: appIdentifier, host: host), animated: true)
            }
        }
    }

    @objc private func blockAllChanged(_ sender: UISwitch) {
        let title = sender.isOn ? "Block all traffic?" : "Allow traffic again?"
        let message = sender.isOn
            ? "Xavier will deny future traffic from \(appIdentifier.commonName.capitalized) until you turn this switch off."
            : "Xavier will remove the app-wide block for \(appIdentifier.commonName.capitalized). Host-specific rules will still apply."

        askConfirmationIn(title: title,
                          text: message,
                          accept: sender.isOn ? "Block All" : "Remove Block",
                          cancel: "Cancel") { confirmed in
            guard confirmed else {
                sender.setOn(!sender.isOn, animated: true)
                return
            }

            do {
                try self.setBlockAllTraffic(enabled: sender.isOn)
                self.reloadData()
            } catch {
                sender.setOn(!sender.isOn, animated: true)
                self.showWarning(title: "Unable to Update Rule", body: "Xavier couldn’t update the app-wide rule right now. \(error)")
            }
        }
    }

    @objc private func muteNotificationsChanged(_ sender: UISwitch) {
        Constants.setNotificationMuted(!sender.isOn, for: appIdentifier)
        if !sender.isOn {
            AppDelegate.removeNotifications(for: appIdentifier)
        }

        currentStatusDescription = (try? buildCurrentStatusText()) ?? "Status unavailable right now"
        DispatchQueue.main.async {
            self.tableView.reloadSections(IndexSet(integer: Section.summary.rawValue), with: .none)
        }
    }

    private func isBlockingAllTraffic() throws -> Bool {
        guard let unwrappedRule = try RuleManager().getRule(for: appIdentifier, hostname: nil) else {
            return false
        }

        guard case .app = unwrappedRule.ruleType else {
            return false
        }

        return !unwrappedRule.isAllowed
    }

    private func setBlockAllTraffic(enabled: Bool) throws {
        let manager = try RuleManager()
        let appRule = try manager.getRule(for: appIdentifier, hostname: nil)

        if let existingRule = appRule, case .app = existingRule.ruleType {
            try manager.delete(rule: existingRule)
        }

        if enabled {
            try manager.create(rule: Rule(ruleType: .app(appIdentifier), isAllowed: false))
        }
    }
}

class AppActivityCell: UITableViewCell {
    
    private let hostLabel = UILabel()
    private let metaLabel = UILabel()
    private let bytesLabel = UILabel()
    private let timeLabel = UILabel()
    private let directionIcon = UIImageView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    private func setupUI() {
        backgroundColor = AppColors.surfaceElevated.color
        selectionStyle = .none
        
        hostLabel.font = UIFont(name: "FiraSans-Medium", size: 16) ?? .systemFont(ofSize: 16, weight: .medium)
        hostLabel.textColor = AppColors.textPrimary.color
        hostLabel.numberOfLines = 0
        hostLabel.translatesAutoresizingMaskIntoConstraints = false
        
        metaLabel.font = UIFont(name: "FiraSans-Regular", size: 13) ?? .systemFont(ofSize: 13)
        metaLabel.textColor = AppColors.textSecondary.color
        metaLabel.numberOfLines = 0
        metaLabel.translatesAutoresizingMaskIntoConstraints = false
        
        bytesLabel.font = UIFont(name: "FiraSans-Medium", size: 14) ?? .systemFont(ofSize: 14, weight: .medium)
        bytesLabel.textColor = AppColors.textPrimary.color
        bytesLabel.textAlignment = .right
        bytesLabel.translatesAutoresizingMaskIntoConstraints = false
        
        timeLabel.font = UIFont(name: "FiraSans-Regular", size: 12) ?? .systemFont(ofSize: 12)
        timeLabel.textColor = AppColors.textSecondary.color.withAlphaComponent(0.7)
        timeLabel.textAlignment = .right
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        
        directionIcon.contentMode = .scaleAspectFit
        directionIcon.tintColor = AppColors.textSecondary.color
        directionIcon.translatesAutoresizingMaskIntoConstraints = false
        
        let vStackLeft = UIStackView(arrangedSubviews: [hostLabel, metaLabel])
        vStackLeft.axis = .vertical
        vStackLeft.spacing = 2
        vStackLeft.translatesAutoresizingMaskIntoConstraints = false
        
        let vStackRight = UIStackView(arrangedSubviews: [bytesLabel, timeLabel])
        vStackRight.axis = .vertical
        vStackRight.spacing = 2
        vStackRight.alignment = .trailing
        vStackRight.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(directionIcon)
        contentView.addSubview(vStackLeft)
        contentView.addSubview(vStackRight)
        
        NSLayoutConstraint.activate([
            directionIcon.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            directionIcon.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            directionIcon.widthAnchor.constraint(equalToConstant: 24),
            directionIcon.heightAnchor.constraint(equalToConstant: 24),
            
            vStackLeft.leadingAnchor.constraint(equalTo: directionIcon.trailingAnchor, constant: 12),
            vStackLeft.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            vStackLeft.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            
            vStackRight.leadingAnchor.constraint(equalTo: vStackLeft.trailingAnchor, constant: 8),
            vStackRight.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            vStackRight.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
        
        vStackRight.setContentCompressionResistancePriority(.required, for: .horizontal)
        bytesLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        
        vStackLeft.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        hostLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        metaLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }
    
    func configure(with event: NetworkEventSnapshot, byteFormatter: ByteCountFormatter, timestampFormatter: DateFormatter) {
        hostLabel.text = event.host ?? event.ipAddress ?? "Unknown host"
        
        let isInbound = event.direction?.lowercased() == "inbound"
        let directionStr = isInbound ? "Inbound" : "Outbound"
        
        var meta = [String]()
        meta.append(directionStr)
        if let proto = event.transportProtocol { meta.append(proto.uppercased()) }
        if let port = event.port, port > 0 { meta.append("Port \(port)") }
        if let ip = event.ipAddress, ip != event.host { meta.append(ip) }
        
        metaLabel.text = meta.isEmpty ? "Unknown details" : meta.joined(separator: " • ")
        
        let inBytes = event.bytesInbound > 0 ? byteFormatter.string(fromByteCount: event.bytesInbound) : "0 KB"
        let outBytes = event.bytesOutbound > 0 ? byteFormatter.string(fromByteCount: event.bytesOutbound) : "0 KB"
        bytesLabel.text = "\(inBytes) ↓  \(outBytes) ↑"
        
        timeLabel.text = timestampFormatter.string(from: event.timestamp)
        
        if isInbound {
            directionIcon.image = UIImage(systemName: "arrow.down.left.circle.fill")
            directionIcon.tintColor = .systemRed
            hostLabel.textColor = .systemRed
            metaLabel.textColor = .systemRed
            bytesLabel.textColor = .systemRed
            timeLabel.textColor = .systemRed
        } else {
            directionIcon.image = UIImage(systemName: "arrow.up.forward.circle.fill")
            directionIcon.tintColor = AppColors.textSecondary.color
            hostLabel.textColor = AppColors.textPrimary.color
            metaLabel.textColor = AppColors.textSecondary.color
            bytesLabel.textColor = AppColors.textPrimary.color
            timeLabel.textColor = AppColors.textSecondary.color.withAlphaComponent(0.7)
        }
    }
}
