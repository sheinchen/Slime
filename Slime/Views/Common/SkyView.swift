import UIKit

/// 整页的底：一层几乎看不出来的竖向渐变，加两团散开的光。
/// 设计稿里「清透感全部交给背景」，所以这一层要淡到不像一张图。
final class SkyView: UIView {

    private let wash = CAGradientLayer()
    private let greenGlow = CAGradientLayer()
    private let goldGlow = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)

        wash.colors = [Sky.top.cgColor, Sky.mid.cgColor, Sky.bottom.cgColor]
        wash.locations = [0, 0.46, 1]
        // 178deg：基本竖直，往右偏一点点
        wash.startPoint = CGPoint(x: 0.48, y: 0)
        wash.endPoint = CGPoint(x: 0.52, y: 1)
        layer.addSublayer(wash)

        configure(greenGlow, color: Sky.glowGreen)
        configure(goldGlow, color: Sky.glowGold)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 径向渐变到 68% 就完全透明，边缘自然就是糊的，不用真的上模糊。
    private func configure(_ glow: CAGradientLayer, color: UIColor) {
        glow.type = .radial
        glow.colors = [
            color.cgColor,
            color.withAlphaComponent(0).cgColor,
            color.withAlphaComponent(0).cgColor,
        ]
        glow.locations = [0, 0.68, 1]
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1, y: 1)
        layer.addSublayer(glow)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        wash.frame = bounds
        // 位置按设计稿的 390×844 等比放到实际屏幕上
        let k = bounds.width / 390
        greenGlow.frame = CGRect(x: -70 * k, y: 120 * k, width: 300 * k, height: 300 * k)
        goldGlow.frame = CGRect(x: bounds.width - 190 * k, y: 430 * k, width: 280 * k, height: 280 * k)

        CATransaction.commit()
    }
}
