//
//  Resources.swift
//  Xavier
//
//

import Foundation
import UIKit
import XavierShared

enum AppColors {
    case highlight
    case deny
    case background
    case allow
    case surface
    case surfaceElevated
    case textPrimary
    case textSecondary
    case separator
    case chrome
    
    var color:UIColor {
        return UIColor { traitCollection in
            let isDark = traitCollection.userInterfaceStyle == .dark
            switch self {
            case .highlight: return UIColor(hex: 0x2FD4B5)
            case .deny: return isDark ? UIColor(hex: 0xEF5350) : UIColor(hex: 0xA85563)
            case .background: return isDark ? UIColor(hex: 0xF4F7F6) : UIColor(hex: 0x17211E)
            case .allow: return isDark ? UIColor(hex: 0x29B6F6) : UIColor(hex: 0x0096E5)
            case .surface: return isDark ? UIColor(hex: 0x17211E) : UIColor(hex: 0xF4F7F6)
            case .surfaceElevated: return isDark ? UIColor(hex: 0x24342F) : UIColor(hex: 0xFFFFFF)
            case .textPrimary: return isDark ? UIColor(hex: 0xF4F7F6) : UIColor(hex: 0x17211E)
            case .textSecondary: return isDark ? UIColor(hex: 0xA0B0AA) : UIColor(hex: 0x5A6964)
            case .separator: return isDark ? UIColor(hex: 0x30423C) : UIColor(hex: 0xDCE5E2)
            case .chrome: return isDark ? UIColor(hex: 0x1E2B27) : UIColor(hex: 0xEEF3F1)
            }
        }
    }
}

struct Storyboard {
    static let Main = UIStoryboard(name: "Main", bundle: Bundle.main)
    static let Notify = UIStoryboard(name: "Notify", bundle: Bundle.main)
}
extension UIColor {
    
    convenience init(hex: Int) {
        let components = (
            R: CGFloat((hex >> 16) & 0xff) / 255,
            G: CGFloat((hex >> 08) & 0xff) / 255,
            B: CGFloat((hex >> 00) & 0xff) / 255
        )
        
        self.init(red: components.R, green: components.G, blue: components.B, alpha: 1)
    }
}

extension UINavigationItem {
    func setNavLogo() {
        let logo = UIImageView(image: UIImage(named: "nav-logo"))
        logo.frame = CGRect(origin: CGPoint(x: 0, y: 0), size:CGSize(width: 26, height: 32))
        
        let title = UIView()
        title.addSubview(logo)
        self.titleView = title
        logo.center = title.center
    }
}

class CustomView:UIView {
    
    @IBInspectable var cornerRadius: CGFloat = 0 {
        didSet {
            layer.cornerRadius = cornerRadius
            layer.masksToBounds = cornerRadius > 0
        }
    }
    
    
    @IBInspectable var borderWidth: CGFloat = 0.0 {
        didSet {
            layer.borderWidth = borderWidth
        }
    }
    
    @IBInspectable var borderColor:UIColor = UIColor.clear {
        didSet {
            layer.borderColor = borderColor.cgColor
        }
    }
    
    
    override init(frame: CGRect) {
        super.init(frame: frame)
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
}


class OutlinedButton:UIButton {
    
    @IBInspectable var cornerRadius: CGFloat = 0 {
        didSet {
            layer.cornerRadius = cornerRadius
            layer.masksToBounds = cornerRadius > 0
        }
    }
    
    @IBInspectable var highlightedColor:UIColor = UIColor.white
    
    @IBInspectable var borderWidth: CGFloat = 1.0 {
        didSet {
            layer.borderWidth = borderWidth
        }
    }
    
    @IBInspectable var borderColor: UIColor = UIColor.clear {
        didSet {
            layer.borderColor = borderColor.cgColor
        }
    }
    
    
    override init(frame: CGRect) {
        super.init(frame: frame)
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    override var isHighlighted: Bool {
        didSet {
            backgroundColor = isHighlighted ? highlightedColor.withAlphaComponent(0.12) : .clear
        }
    }
    
}

@IBDesignable
class GradientView: UIView {
    
    @IBInspectable var firstColor: UIColor = UIColor.clear {
        didSet {
            updateView()
        }
    }
    
    @IBInspectable var secondColor: UIColor = UIColor.clear {
        didSet {
            updateView()
        }
    }
    
    @IBInspectable var isHorizontal: Bool = true {
        didSet {
            updateView()
        }
    }
    
    override class var layerClass: AnyClass {
        get {
            return CAGradientLayer.self
        }
    }
    
    func updateView() {
        let layer = self.layer as! CAGradientLayer
        layer.colors = [firstColor, secondColor].map {$0.cgColor}
        if (isHorizontal) {
            layer.startPoint = CGPoint(x: 0, y: 0.5)
            layer.endPoint = CGPoint (x: 1, y: 0.5)
        } else {
            layer.startPoint = CGPoint(x: 0.5, y: 0)
            layer.endPoint = CGPoint (x: 0.5, y: 1)
        }
    }
    
}
