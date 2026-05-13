//
//  AboutController.swift
//  Xavier
//
//

import Foundation
import UIKit

class AboutController:UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        navigationItem.largeTitleDisplayMode = .always
        navigationItem.rightBarButtonItem = nil
        configureViewHierarchy()
    }
    
    @objc func shareTapped() {
        let link = Constants.appURL
        let text = Constants.promoText
        
        var items:[Any] = []
        items.append(text)
        
        if let urlItem = URL(string: link) {
            items.append(urlItem)
        }
        
        let share = UIActivityViewController(activityItems: items,
                                             applicationActivities: nil)

        if let popover = share.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        }
         
        
        share.completionWithItemsHandler = { (_, _, _, _) in
            self.dismiss(animated: true, completion: nil)
        }
        
        self.present(share, animated: true, completion: nil)

    }
    
    func openURL(url string:String) {
        if let url = URL(string: string) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }
    
    @IBAction func faqTapped() {
        openURL(url: Constants.WebsiteEndpoints.faq.url)
    }
    
    @IBAction func privacyTapped() {
        openURL(url: Constants.WebsiteEndpoints.privacy.url)
    }
    
    @IBAction func developerTapped() {
        openURL(url: Constants.WebsiteEndpoints.developer.url)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    private func configureViewHierarchy() {
        view.subviews.forEach { $0.removeFromSuperview() }
        view.removeConstraints(view.constraints)
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
        eyebrowLabel.text = "Privacy"

        let titleLabel = UILabel()
        titleLabel.font = UIFont(name: "FiraSans-Bold", size: 30) ?? UIFont.boldSystemFont(ofSize: 30)
        titleLabel.textColor = AppColors.textPrimary.color
        titleLabel.numberOfLines = 0
        titleLabel.text = "Xavier keeps network visibility on your device."

        let introLabel = UILabel()
        introLabel.font = UIFont(name: "FiraSans-Regular", size: 17) ?? UIFont.systemFont(ofSize: 17)
        introLabel.textColor = AppColors.textSecondary.color
        introLabel.numberOfLines = 0
        introLabel.text = "Use this space to review privacy details, get support, and share the app without the original project’s splashy poster treatment."

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let privacyCard = makeFeatureCard(title: "Privacy",
                                          detail: "Xavier stores network activity on your device so you can inspect apps and create rules without sending that traffic anywhere else.",
                                          buttonTitle: "Read Privacy Details",
                                          action: #selector(handlePrivacyTap))

        let supportCard = makeSupportCard()

        let shareCard = makeFeatureCard(title: "Share Xavier",
                                        detail: "Send the project link to someone who wants to inspect app traffic or debug network behavior on a supervised device.",
                                        buttonTitle: "Share Project",
                                        action: #selector(handleShareTap))

        let versionChip = makeInfoCard(title: "Version", detail: version, supportingText: Constants.promoText)

        stack.addArrangedSubview(eyebrowLabel)
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(introLabel)
        stack.addArrangedSubview(privacyCard)
        stack.addArrangedSubview(supportCard)
        stack.addArrangedSubview(shareCard)
        stack.addArrangedSubview(versionChip)

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

            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24)
        ])
    }

    private func makeInfoCard(title: String, detail: String, supportingText: String? = nil) -> UIView {
        let card = UIView()
        card.backgroundColor = AppColors.surfaceElevated.color
        card.layer.cornerRadius = 18
        card.layer.borderWidth = 1
        card.layer.borderColor = AppColors.separator.color.cgColor

        let titleLabel = UILabel()
        titleLabel.font = UIFont(name: "FiraSans-Medium", size: 14) ?? UIFont.systemFont(ofSize: 14, weight: .medium)
        titleLabel.textColor = AppColors.textSecondary.color
        titleLabel.text = title

        let detailLabel = UILabel()
        detailLabel.font = UIFont(name: "FiraSans-Bold", size: 22) ?? UIFont.boldSystemFont(ofSize: 22)
        detailLabel.textColor = AppColors.textPrimary.color
        detailLabel.text = detail

        let stack: UIStackView

        if let supportingText = supportingText {
            let supportingLabel = UILabel()
            supportingLabel.font = UIFont(name: "FiraSans-Regular", size: 15) ?? UIFont.systemFont(ofSize: 15)
            supportingLabel.textColor = AppColors.textSecondary.color
            supportingLabel.numberOfLines = 0
            supportingLabel.text = supportingText
            stack = UIStackView(arrangedSubviews: [titleLabel, detailLabel, supportingLabel])
        } else {
            stack = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
        }

        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20)
        ])

        return card
    }

    private func makeFeatureCard(title: String,
                                 detail: String,
                                 buttonTitle: String,
                                 action: Selector) -> UIView {
        let card = UIView()
        card.backgroundColor = AppColors.surfaceElevated.color
        card.layer.cornerRadius = 18
        card.layer.borderWidth = 1
        card.layer.borderColor = AppColors.separator.color.cgColor

        let titleLabel = UILabel()
        titleLabel.font = UIFont(name: "FiraSans-Medium", size: 14) ?? UIFont.systemFont(ofSize: 14, weight: .medium)
        titleLabel.textColor = AppColors.textSecondary.color
        titleLabel.text = title.uppercased()

        let detailLabel = UILabel()
        detailLabel.font = UIFont(name: "FiraSans-Regular", size: 15) ?? UIFont.systemFont(ofSize: 15)
        detailLabel.textColor = AppColors.textSecondary.color
        detailLabel.numberOfLines = 0
        detailLabel.text = detail

        let actionButton = makeLinkButton(title: buttonTitle, action: action)

        let stack = UIStackView(arrangedSubviews: [titleLabel, detailLabel, actionButton])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20)
        ])

        return card
    }

    private func makeSupportCard() -> UIView {
        let card = UIView()
        card.backgroundColor = AppColors.surfaceElevated.color
        card.layer.cornerRadius = 18
        card.layer.borderWidth = 1
        card.layer.borderColor = AppColors.separator.color.cgColor

        let titleLabel = UILabel()
        titleLabel.font = UIFont(name: "FiraSans-Medium", size: 14) ?? UIFont.systemFont(ofSize: 14, weight: .medium)
        titleLabel.textColor = AppColors.textSecondary.color
        titleLabel.text = "Support"

        let detailLabel = UILabel()
        detailLabel.font = UIFont(name: "FiraSans-Regular", size: 15) ?? UIFont.systemFont(ofSize: 15)
        detailLabel.textColor = AppColors.textSecondary.color
        detailLabel.numberOfLines = 0
        detailLabel.text = "Review the FAQ or open the developer site if you need installation help, troubleshooting, or background context for supervised-device filtering."

        let faqButton = makeLinkButton(title: "Open FAQ", action: #selector(handleFAQTap))
        let developerButton = makeLinkButton(title: "Open Developer Site", action: #selector(handleDeveloperTap))

        let stack = UIStackView(arrangedSubviews: [titleLabel, detailLabel, faqButton, developerButton])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20)
        ])

        return card
    }

    private func makeLinkButton(title: String, action: Selector) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.baseBackgroundColor = AppColors.chrome.color
        config.baseForegroundColor = AppColors.textPrimary.color
        config.cornerStyle = .medium
        config.background.cornerRadius = 12
        config.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
        
        // Ensure the text aligns to the left as originally requested
        config.titleAlignment = .leading
        
        let button = UIButton(configuration: config)
        button.contentHorizontalAlignment = .left
        
        let customFont = UIFont(name: "FiraSans-Bold", size: 17) ?? UIFont.boldSystemFont(ofSize: 17)
        button.configurationUpdateHandler = { button in
            var updatedConfig = button.configuration
            updatedConfig?.attributedTitle = AttributedString(title, attributes: AttributeContainer([
                .font: customFont
            ]))
            button.configuration = updatedConfig
        }
        
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    @objc private func handleFAQTap() {
        faqTapped()
    }

    @objc private func handlePrivacyTap() {
        privacyTapped()
    }

    @objc private func handleDeveloperTap() {
        developerTapped()
    }

    @objc private func handleShareTap() {
        shareTapped()
    }
}
