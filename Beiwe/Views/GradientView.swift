import Foundation
import UIKit

@IBDesignable open class GradientView: UIView {
    @IBInspectable open var topColor: UIColor? {
        didSet {
            self.configureView()
        }
    }

    @IBInspectable open var bottomColor: UIColor? {
        didSet {
            configureView()
        }
    }

    override open class var layerClass: AnyClass {
        return CAGradientLayer.self
    }

    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.configureView()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.configureView()
    }

    override open func tintColorDidChange() {
        super.tintColorDidChange()
        self.configureView()
    }

    static func makeGradient(_ view: UIView, topColor: UIColor? = nil, bottomColor: UIColor? = nil) {
        let layer = view.layer as! CAGradientLayer
        let locations = [0.0, 1.0]
        layer.locations = locations as [NSNumber]
        let color1 = topColor ?? AppColors.gradientTop
        let color2 = bottomColor ?? AppColors.gradientBottom
        let colors: Array<AnyObject> = [color1.cgColor, color2.cgColor]
        layer.colors = colors
    }

    func configureView() {
        GradientView.makeGradient(self, topColor: self.topColor, bottomColor: self.bottomColor)
    }
}
