//
//  UIViewController+Util.swift
//  Xavier
//
//

import Foundation
import UIKit

extension UIViewController {
    
    func showWarning(title:String, body:String, then:(()->Void)? = nil) {
        showAlert(title: title, message: body, then: then)
    }

    func showAlert(title: String, message: String, then: (() -> Void)? = nil) {
        DispatchQueue.main.async {
            let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                then?()
            })
            self.present(alertController, animated: true, completion: nil)
        }
    }

    func showError(title: String, error: Error, fallbackMessage: String, then: (() -> Void)? = nil) {
        // Strip raw error strings in production UI unless they are simple network descriptions.
        // For a privacy tool, raw errors look brittle.
        showAlert(title: title, message: fallbackMessage, then: then)
    }

    func showSuccess(message: String) {
        DispatchQueue.main.async {
            let banner = UIView()
            banner.backgroundColor = AppColors.surfaceElevated.color
            banner.layer.cornerRadius = 12
            banner.layer.shadowColor = UIColor.black.cgColor
            banner.layer.shadowOffset = CGSize(width: 0, height: 4)
            banner.layer.shadowOpacity = 0.1
            banner.layer.shadowRadius = 12
            banner.translatesAutoresizingMaskIntoConstraints = false

            let icon: UIImageView
            if #available(iOS 13.0, *) {
                icon = UIImageView(image: UIImage(systemName: "checkmark.circle.fill") ?? UIImage())
            } else {
                icon = UIImageView()
            }
            icon.tintColor = AppColors.highlight.color
            icon.setContentHuggingPriority(.required, for: .horizontal)

            let label = UILabel()
            label.text = message
            label.font = UIFont(name: "FiraSans-Medium", size: 15) ?? UIFont.systemFont(ofSize: 15, weight: .medium)
            label.textColor = AppColors.textPrimary.color
            label.numberOfLines = 0

            let stack = UIStackView(arrangedSubviews: [icon, label])
            stack.axis = .horizontal
            stack.spacing = 12
            stack.alignment = .center
            stack.translatesAutoresizingMaskIntoConstraints = false

            banner.addSubview(stack)
            self.view.addSubview(banner)

            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 16),
                stack.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -16),
                stack.topAnchor.constraint(equalTo: banner.topAnchor, constant: 14),
                stack.bottomAnchor.constraint(equalTo: banner.bottomAnchor, constant: -14),

                banner.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
                banner.leadingAnchor.constraint(greaterThanOrEqualTo: self.view.leadingAnchor, constant: 20),
                banner.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
            ])

            banner.alpha = 0
            banner.transform = CGAffineTransform(translationX: 0, y: 20)

            UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5, options: .curveEaseOut, animations: {
                banner.alpha = 1
                banner.transform = .identity
            }) { _ in
                UIView.animate(withDuration: 0.2, delay: 2.0, options: .curveEaseIn, animations: {
                    banner.alpha = 0
                    banner.transform = CGAffineTransform(translationX: 0, y: 10)
                }) { _ in
                    banner.removeFromSuperview()
                }
            }
        }
    }
    
    func showSettings(with title:String, message:String, dnd:String? = nil, then:(()->Void)? = nil) {
        
        let alertController = UIAlertController(title: title,
                                                message: message,
                                                preferredStyle: .alert)
        
        let settingsAction = UIAlertAction(title: "Settings", style: .default) { (alertAction) in
            
            if let appSettings = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(appSettings, options: [:], completionHandler: nil)
            }
            
            then?()
        }
        alertController.addAction(settingsAction)
        
        let cancelAction = UIAlertAction(title: "Cancel", style: UIAlertAction.Style.cancel) { (action) in
            then?()
        }
        alertController.addAction(cancelAction)
        
        if let dndKey = dnd {
            alertController.addAction(UIAlertAction(title: "Don't ask again", style: UIAlertAction.Style.destructive) { (action) in
                UserDefaults.standard.set(true, forKey: dndKey)
            })
            
        }
        
        DispatchQueue.main.async {
            self.present(alertController, animated: true, completion: nil)
        }
    }
    
    func askConfirmationIn(title:String, text:String, accept:String, cancel:String, handler: @escaping ((_ confirmed:Bool) -> Void)) {
        
        let alertController:UIAlertController = UIAlertController(title: title, message: text, preferredStyle: UIAlertController.Style.alert)
        
        
        alertController.addAction(UIAlertAction(title: accept, style: UIAlertAction.Style.default, handler: { (action:UIAlertAction) -> Void in
            
            handler(true)
            
        }))
        
        alertController.addAction(UIAlertAction(title: cancel, style: UIAlertAction.Style.cancel, handler: { (action:UIAlertAction) -> Void in
            
            handler(false)
            
        }))
        
        self.present(alertController, animated: true, completion: nil)
    }
    
}

