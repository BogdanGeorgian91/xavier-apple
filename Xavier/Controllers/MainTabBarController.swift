//
//  MainTabBarController.swift
//  Xavier
//
//  Created by OpenCode on 4/5/26.
//

import UIKit
import XavierShared

final class MainTabBarController: UITabBarController {
    private var didPresentOnboarding = false

    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = AppColors.surface.color

        configureAppearance()

        viewControllers = [makeActivityController(),
                           makeInspectorController(),
                           makeRulesController()]
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if didPresentOnboarding || UserDefaults.standard.bool(forKey: Constants.onboardingKey) {
            return
        }

        let onboardingController = UINavigationController(rootViewController: OBNetworkPermissionsController())
        onboardingController.setNavigationBarHidden(true, animated: false)
        onboardingController.modalPresentationStyle = .fullScreen
        didPresentOnboarding = true
        present(onboardingController, animated: true, completion: nil)
    }

    private func makeActivityController() -> UIViewController {
        let controller = DashboardViewController(scope: .all)
        let navigationController = UINavigationController(rootViewController: controller)
        configureNavigationController(navigationController)
        navigationController.tabBarItem = UITabBarItem(title: "Activity", image: tabImage(systemName: "waveform.path.ecg", fallbackAssetName: "nav-logo"), tag: 0)
        return navigationController
    }

    private func makeRulesController() -> UIViewController {
        let controller = Storyboard.Main.instantiateViewController(withIdentifier: "RulesNavigationController")
        if let navigationController = controller as? UINavigationController {
            configureNavigationController(navigationController)
        }
        controller.tabBarItem = UITabBarItem(title: "Rules", image: tabImage(systemName: "line.3.horizontal.decrease.circle", fallbackAssetName: "logo"), tag: 2)
        return controller
    }

    private func makeInspectorController() -> UIViewController {
        let controller = InspectorViewController()
        let navigationController = UINavigationController(rootViewController: controller)
        configureNavigationController(navigationController)
        navigationController.tabBarItem = UITabBarItem(title: "Inspector", image: tabImage(systemName: "magnifyingglass", fallbackAssetName: "nav-logo"), tag: 1)
        return navigationController
    }

    private func tabImage(systemName: String, fallbackAssetName: String) -> UIImage? {
        return UIImage(systemName: systemName)
    }

    private func configureNavigationController(_ navigationController: UINavigationController) {
        navigationController.navigationBar.barStyle = .default
        navigationController.navigationBar.tintColor = AppColors.textPrimary.color
        navigationController.navigationBar.barTintColor = AppColors.surface.color
        navigationController.navigationBar.backgroundColor = AppColors.surface.color
        navigationController.navigationBar.prefersLargeTitles = false
        navigationController.navigationBar.isTranslucent = false

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = AppColors.surface.color
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [.foregroundColor: AppColors.textPrimary.color]
        appearance.largeTitleTextAttributes = [.foregroundColor: AppColors.textPrimary.color]
        navigationController.navigationBar.standardAppearance = appearance
        navigationController.navigationBar.scrollEdgeAppearance = appearance
        navigationController.navigationBar.compactAppearance = appearance
    }

    private func configureAppearance() {
        tabBar.tintColor = AppColors.highlight.color
        tabBar.unselectedItemTintColor = AppColors.textSecondary.color
        tabBar.barTintColor = .clear
        tabBar.backgroundColor = .clear
        tabBar.backgroundImage = UIImage()
        tabBar.shadowImage = UIImage()
        tabBar.isTranslucent = true

        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear
        appearance.shadowColor = .clear
        appearance.stackedLayoutAppearance.selected.iconColor = AppColors.highlight.color
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: AppColors.highlight.color]
        appearance.stackedLayoutAppearance.normal.iconColor = AppColors.textPrimary.color.withAlphaComponent(0.4)
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: AppColors.textPrimary.color.withAlphaComponent(0.4)]
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
    }
}
