import UIKit

final class BlocklistViewController: UITableViewController {
    private var entries = [BlocklistEntry]()

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Domain Blocklist"
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addEntry))
        tableView.backgroundColor = AppColors.surface.color
        tableView.separatorColor = AppColors.separator.color
        tableView.tableFooterView = UIView(frame: .zero)
        reloadEntries()
    }

    private func reloadEntries() {
        entries = ScriptBlocklistManager.shared.fetchAllEntries().sorted { $0.domainPattern < $1.domainPattern }
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return max(entries.count, 1)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "BlocklistCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "BlocklistCell")
        cell.backgroundColor = AppColors.surfaceElevated.color
        cell.selectionStyle = .none

        var content = cell.defaultContentConfiguration()
        content.textProperties.font = UIFont(name: "FiraSans-Bold", size: 16) ?? .boldSystemFont(ofSize: 16)
        content.textProperties.color = AppColors.textPrimary.color
        content.secondaryTextProperties.font = UIFont(name: "FiraSans-Regular", size: 13) ?? .systemFont(ofSize: 13)
        content.secondaryTextProperties.color = AppColors.textSecondary.color

        guard !entries.isEmpty else {
            content.text = "No blocklist entries"
            content.secondaryText = "Add domains to block or enable the preset trackers."
            cell.contentConfiguration = content
            return cell
        }

        let entry = entries[indexPath.row]
        content.text = entry.domainPattern
        content.secondaryText = entry.isPreset ? "Preset tracker domain" : "Custom domain"
        cell.contentConfiguration = content

        let toggle = UISwitch()
        toggle.isOn = entry.enabled
        toggle.onTintColor = AppColors.highlight.color
        toggle.tag = indexPath.row
        toggle.addTarget(self, action: #selector(toggleChanged(_:)), for: .valueChanged)
        cell.accessoryView = toggle
        return cell
    }

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        guard !entries.isEmpty else { return false }
        return !entries[indexPath.row].isPreset
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete, !entries.isEmpty else { return }
        ScriptBlocklistManager.shared.removeEntry(identifier: entries[indexPath.row].identifier)
        reloadEntries()
    }

    @objc private func toggleChanged(_ sender: UISwitch) {
        let entry = entries[sender.tag]
        ScriptBlocklistManager.shared.updateEntry(identifier: entry.identifier, enabled: sender.isOn)
        reloadEntries()
    }

    @objc private func addEntry() {
        let alert = UIAlertController(title: "Add Domain", message: "Enter a domain pattern such as *.doubleclick.net", preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "example.com"
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Add", style: .default, handler: { _ in
            guard let text = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
            let now = Date()
            ScriptBlocklistManager.shared.addEntry(BlocklistEntry(identifier: UUID().uuidString,
                                                                  domainPattern: text.lowercased(),
                                                                  enabled: true,
                                                                  isPreset: false,
                                                                  isStripEnabled: false,
                                                                  createdAt: now,
                                                                  updatedAt: now))
            self.reloadEntries()
        }))
        present(alert, animated: true, completion: nil)
    }
}
