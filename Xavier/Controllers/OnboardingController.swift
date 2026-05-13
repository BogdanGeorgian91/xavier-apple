//
//  OnboardingController.swift
//  Xavier
//
//

import Foundation
import UIKit
import NetworkExtension
import UserNotifications

class OBNetworkPermissionsController:UIViewController {
    @IBOutlet weak var enabledNetSwitch: UISwitch?
    @IBOutlet weak var enabledPushSwitch: UISwitch?

    private let netStatusLabel = UILabel()
    private let pushStatusLabel = UILabel()
    private let netActionButton = UIButton(type: .system)
    private let pushActionButton = UIButton(type: .system)
    private let continueButton = UIButton(type: .system)
    private var notificationsDenied = false

    private var isNetEnabled = false {
        didSet {
            updateTaskViews()
        }
    }

    private var isPushEnabled = false {
        didSet {
            updateTaskViews()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureViewHierarchy()
        refreshStatuses()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshStatuses()
    }

    @IBAction func enableNetFilterToggled() {
        enableNetworkFilter()
    }

    @IBAction func enablePushToggled() {
        requestNotifications()
    }

    @objc private func enableNetworkFilterTapped() {
        enableNetworkFilter()
    }

    @objc private func enableNotificationsTapped() {
        requestNotifications()
    }

    @objc private func continueTapped() {
        if let tabController = view.window?.rootViewController as? MainTabBarController {
            tabController.selectedIndex = 0
        }
        UserDefaults.standard.set(true, forKey: Constants.onboardingKey)
        navigationController?.dismiss(animated: true, completion: nil)
    }

    private func configureViewHierarchy() {
        view.backgroundColor = AppColors.surface.color

        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false

        let eyebrowLabel = UILabel()
        eyebrowLabel.font = UIFont(name: "FiraSans-Medium", size: 14) ?? UIFont.systemFont(ofSize: 14, weight: .medium)
        eyebrowLabel.textColor = AppColors.highlight.color
        eyebrowLabel.text = "Setup"

        let titleLabel = UILabel()
        titleLabel.font = UIFont(name: "FiraSans-Bold", size: 32) ?? UIFont.boldSystemFont(ofSize: 32)
        titleLabel.textColor = AppColors.textPrimary.color
        titleLabel.numberOfLines = 0
        titleLabel.text = "See which apps connect to which hosts, then decide what to allow."

        let subtitleLabel = UILabel()
        subtitleLabel.font = UIFont(name: "FiraSans-Regular", size: 17) ?? UIFont.systemFont(ofSize: 17)
        subtitleLabel.textColor = AppColors.textSecondary.color
        subtitleLabel.numberOfLines = 0
        subtitleLabel.text = "Xavier processes activity on your device. Complete these two steps to start reviewing live network activity."

        let netCard = makeTaskCard(title: "Enable Network Filter",
                                   detail: "Lets Xavier inspect network traffic from other apps so you can review connections and create rules.",
                                   statusLabel: netStatusLabel,
                                   actionButton: netActionButton,
                                   action: #selector(enableNetworkFilterTapped))

        let pushCard = makeTaskCard(title: "Allow Notifications",
                                    detail: "Lets Xavier notify you when another app makes a connection while Xavier is in the background.",
                                    statusLabel: pushStatusLabel,
                                    actionButton: pushActionButton,
                                    action: #selector(enableNotificationsTapped))

        continueButton.setTitle("Open Activity", for: .normal)
        continueButton.titleLabel?.font = UIFont(name: "FiraSans-Bold", size: 17) ?? UIFont.boldSystemFont(ofSize: 17)
        continueButton.setTitleColor(.black, for: .normal)
        continueButton.backgroundColor = AppColors.textPrimary.color
        continueButton.layer.cornerRadius = 16
        continueButton.contentEdgeInsets = UIEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        continueButton.addTarget(self, action: #selector(continueTapped), for: .touchUpInside)

        stack.addArrangedSubview(eyebrowLabel)
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(subtitleLabel)
        stack.addArrangedSubview(netCard)
        stack.addArrangedSubview(pushCard)
        stack.addArrangedSubview(continueButton)

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 32),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24),
            continueButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 54)
        ])

        updateTaskViews()
    }

    private func makeTaskCard(title: String,
                              detail: String,
                              statusLabel: UILabel,
                              actionButton: UIButton,
                              action: Selector) -> UIView {
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = AppColors.surfaceElevated.color
        card.layer.cornerRadius = 20
        card.layer.borderWidth = 1
        card.layer.borderColor = AppColors.separator.color.cgColor

        let titleLabel = UILabel()
        titleLabel.font = UIFont(name: "FiraSans-Bold", size: 20) ?? UIFont.boldSystemFont(ofSize: 20)
        titleLabel.textColor = AppColors.textPrimary.color
        titleLabel.numberOfLines = 0
        titleLabel.text = title

        statusLabel.font = UIFont(name: "FiraSans-Medium", size: 14) ?? UIFont.systemFont(ofSize: 14, weight: .medium)
        statusLabel.numberOfLines = 1

        let detailLabel = UILabel()
        detailLabel.font = UIFont(name: "FiraSans-Regular", size: 15) ?? UIFont.systemFont(ofSize: 15)
        detailLabel.textColor = AppColors.textSecondary.color
        detailLabel.numberOfLines = 0
        detailLabel.text = detail

        actionButton.setTitleColor(AppColors.textPrimary.color, for: .normal)
        actionButton.titleLabel?.font = UIFont(name: "FiraSans-Bold", size: 15) ?? UIFont.boldSystemFont(ofSize: 15)
        actionButton.layer.cornerRadius = 12
        actionButton.layer.borderWidth = 1
        actionButton.layer.borderColor = AppColors.separator.color.cgColor
        actionButton.backgroundColor = AppColors.chrome.color
        actionButton.contentEdgeInsets = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        actionButton.addTarget(self, action: action, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [titleLabel, statusLabel, detailLabel, actionButton])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18)
        ])

        return card
    }

    private func refreshStatuses() {
        NEFilterManager.shared().loadFromPreferences { error in
            let isNetEnabled = error == nil && NEFilterManager.shared().isEnabled

            UNUserNotificationCenter.current().getNotificationSettings { settings in
                let isPushEnabled = settings.authorizationStatus == .authorized
                let notificationsDenied = settings.authorizationStatus == .denied

                DispatchQueue.main.async {
                    self.isNetEnabled = isNetEnabled
                    self.isPushEnabled = isPushEnabled
                    self.notificationsDenied = notificationsDenied
                    self.enabledNetSwitch?.isOn = isNetEnabled
                    self.enabledPushSwitch?.isOn = isPushEnabled
                }
            }
        }
    }

    private func updateTaskViews() {
        update(statusLabel: netStatusLabel,
               actionButton: netActionButton,
               isEnabled: isNetEnabled,
               actionTitle: "Enable Network Filter")

        update(statusLabel: pushStatusLabel,
               actionButton: pushActionButton,
               isEnabled: isPushEnabled,
               actionTitle: notificationsDenied ? "Open Settings" : "Allow Notifications")

        continueButton.isEnabled = true
        continueButton.alpha = 1
        continueButton.setTitle(isNetEnabled ? "Open Activity" : "Continue for now", for: .normal)
    }

    private func update(statusLabel: UILabel,
                        actionButton: UIButton,
                        isEnabled: Bool,
                        actionTitle: String) {
        statusLabel.text = isEnabled ? "Ready" : "Action needed"
        statusLabel.textColor = isEnabled ? AppColors.highlight.color : AppColors.textSecondary.color
        actionButton.setTitle(isEnabled ? "Enabled" : actionTitle, for: .normal)
        actionButton.isEnabled = !isEnabled
        actionButton.alpha = isEnabled ? 0.6 : 1
    }

    private func enableNetworkFilter() {
        if NEFilterManager.shared().providerConfiguration == nil {
            let newConfiguration = NEFilterProviderConfiguration()
            newConfiguration.username = "Xavier"
            newConfiguration.organization = "Xavier App"
            newConfiguration.filterBrowsers = true
            newConfiguration.filterSockets = true
            NEFilterManager.shared().providerConfiguration = newConfiguration
        }

        NEFilterManager.shared().isEnabled = true
        NEFilterManager.shared().saveToPreferences { error in
            if error != nil {
                DispatchQueue.main.async {
                    self.showWarning(title: "Couldn’t enable the network filter",
                                     body: "Xavier needs the network filter enabled before it can show activity from other apps. Please try again.")
                }
                return
            }

            DispatchQueue.main.async {
                self.isNetEnabled = true
                self.enabledNetSwitch?.isOn = true
            }
        }
    }

    private func requestNotifications() {
        if notificationsDenied {
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsURL, options: [:], completionHandler: nil)
            }
            return
        }

        (UIApplication.shared.delegate as? AppDelegate)?.registerForNotifications { granted, error in
            if error != nil {
                self.showWarning(title: "Couldn’t enable notifications",
                                 body: "Xavier uses notifications to alert you about activity while you are in another app. Please try again.")
                return
            }

            guard granted else {
                self.notificationsDenied = true
                self.updateTaskViews()
                self.showWarning(title: "Notifications are still off",
                                 body: "Allow notifications to see live activity alerts while you are using another app.")
                return
            }

            DispatchQueue.main.async {
                self.isPushEnabled = true
                self.enabledPushSwitch?.isOn = true
            }
        }
    }
}

class OBTutorialController:UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        UserDefaults.standard.set(true, forKey: Constants.onboardingKey)
    }

    @IBAction func startTapped() {
        navigationController?.dismiss(animated: true, completion: nil)
    }
}
