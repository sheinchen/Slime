//
//  CareCardView.swift
//  Slime
//

import UIKit
import SnapKit

/// 首页上母鸡冒出来的一句关心 —— 一个淡白色的聊天气泡，尾巴指着她。
///
/// **纯只读**：没有按钮、不接受点击、不能回应 —— 这是明确的产品选择，不是待办。
///
/// 它也不知道自己为什么会出现：拿到的 `PendingCare` 里只有 id / text / createdAt，
/// **没有 referencedDates**。「绝不暴露判断依据」这条铁律在数据结构上就锁死了，
/// 这个 view 想漏也漏不出来。
final class CareCardView: UIView {

    private enum Metrics {
        static let cornerRadius: CGFloat = 22
        /// 尾巴根部多宽、往下伸多长
        static let tailWidth: CGFloat = 20
        static let tailHeight: CGFloat = 11
        /// 母鸡走出气泡的横向范围时，尾巴根停在边上，只把尖往她那边歪，最多歪这么多
        static let maxLean: CGFloat = 9
        /// 尾巴追母鸡的快慢。越大跟得越紧
        static let followRate: Double = 6
        static let padding = UIEdgeInsets(top: 14, left: 20, bottom: 15, right: 20)
    }

    // 把这个 view 自己的底层 layer 换成 CAShapeLayer：
    // 气泡身体和尾巴是**同一条 path**，填色、描边、影子一次画完，
    // 接缝处不会叠出一道深色，描边也不会在尾巴根上横着划一道。
    override class var layerClass: AnyClass { CAShapeLayer.self }
    private var shape: CAShapeLayer { layer as! CAShapeLayer }

    private let quote = UILabel()

    /// 尾巴想对准的横坐标（自身坐标系，已缓动、未夹紧）。
    /// nil = 这次露面还没对准过，第一次直接跳过去，别从别处滑过来。
    private var aimX: CGFloat?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        backgroundColor = .clear

        // 比天光再白一点点，和底色几乎贴着 —— 靠一圈极淡的描边和影子浮起来
        shape.fillColor = Sky.bubble.cgColor
        shape.strokeColor = Sky.ink(0.06).cgColor
        shape.lineWidth = 0.5

        shape.shadowColor = Sky.bubbleShadow.cgColor
        shape.shadowOpacity = 0.14
        shape.shadowRadius = 16
        shape.shadowOffset = CGSize(width: 0, height: 6)

        // 气泡本身不接受任何触摸 —— 点它等于点到了它下面的天空
        isUserInteractionEnabled = false

        quote.numberOfLines = 0
        addSubview(quote)

        let p = Metrics.padding
        quote.snp.makeConstraints {
            $0.top.equalToSuperview().inset(p.top)
            $0.leading.equalToSuperview().inset(p.left)
            $0.trailing.equalToSuperview().inset(p.right)
            // 底下留出尾巴的高度：view 的 bounds 包含尾巴，身体只占上面那截
            $0.bottom.equalToSuperview().inset(p.bottom + Metrics.tailHeight)
        }
    }

    // MARK: - 内容

    func setText(_ text: String) {
        quote.attributedText = AppFont.attributed(text, size: 16,
                                                  color: Sky.ink(0.82),
                                                  lineHeight: 16 * 1.55)
    }

    // MARK: - 尾巴

    /// 让尾巴对准母鸡。首页的帧循环每帧调一次。
    ///
    /// - Parameters:
    ///   - x: 母鸡身体中线的横坐标，**已经换算到这个气泡自己的坐标系**
    ///   - dt: 距上一帧多久。缓动按时间算、不按帧算，60Hz 和 120Hz 才跟得一样快
    func aimTail(atX x: CGFloat, dt: CFTimeInterval) {
        if let current = aimX {
            let k = CGFloat(1 - exp(-dt * Metrics.followRate))
            aimX = current + (x - current) * k
        } else {
            aimX = x
        }
        redrawBubble()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // 字变了、宽高跟着变，形状要重画
        redrawBubble()
    }

    /// 画一整条轮廓：从左上角顺时针绕一圈，走到底边时拐出去画尾巴再拐回来。
    private func redrawBubble() {
        let w = bounds.width
        let h = bounds.height - Metrics.tailHeight      // 身体的高度
        guard w > 0, h > 0 else { return }

        let r = min(Metrics.cornerRadius, h / 2, w / 2)
        let half = Metrics.tailWidth / 2

        // 尾巴根只能落在底边的直线段上，别戳进圆角里
        let target = aimX ?? w / 2
        let minX = r + half
        let maxX = max(minX, w - r - half)
        let baseX = min(max(target, minX), maxX)
        // 母鸡在范围外时，尖往她那边歪（离得越远歪得越多，有上限）
        let lean = min(max((target - baseX) * 0.3, -Metrics.maxLean), Metrics.maxLean)
        let tip = CGPoint(x: baseX + lean, y: h + Metrics.tailHeight)

        let path = UIBezierPath()
        path.move(to: CGPoint(x: r, y: 0))
        path.addLine(to: CGPoint(x: w - r, y: 0))
        path.addArc(withCenter: CGPoint(x: w - r, y: r), radius: r,
                    startAngle: -.pi / 2, endAngle: 0, clockwise: true)
        path.addLine(to: CGPoint(x: w, y: h - r))
        path.addArc(withCenter: CGPoint(x: w - r, y: h - r), radius: r,
                    startAngle: 0, endAngle: .pi / 2, clockwise: true)

        // 底边从右往左走，中途拐出尾巴。
        // 两头的控制点压在底边上 → 尾巴和身体是顺着长出来的，没有折角；
        // 靠近尖的控制点略微收拢 → 尖是圆钝的，不扎眼。
        path.addLine(to: CGPoint(x: baseX + half, y: h))
        path.addCurve(to: tip,
                      controlPoint1: CGPoint(x: baseX + half * 0.35, y: h),
                      controlPoint2: CGPoint(x: tip.x + 1.6, y: tip.y - 2.5))
        path.addCurve(to: CGPoint(x: baseX - half, y: h),
                      controlPoint1: CGPoint(x: tip.x - 1.6, y: tip.y - 2.5),
                      controlPoint2: CGPoint(x: baseX - half * 0.35, y: h))

        path.addLine(to: CGPoint(x: r, y: h))
        path.addArc(withCenter: CGPoint(x: r, y: h - r), radius: r,
                    startAngle: .pi / 2, endAngle: .pi, clockwise: true)
        path.addLine(to: CGPoint(x: 0, y: r))
        path.addArc(withCenter: CGPoint(x: r, y: r), radius: r,
                    startAngle: .pi, endAngle: .pi * 1.5, clockwise: true)
        path.close()

        shape.path = path.cgPath
        // 显式给影子形状，系统就不用每帧去猜轮廓（那要离屏渲染）
        shape.shadowPath = path.cgPath
    }

    // MARK: - 单次露面的进退场
    //
    // ⚠️ 这两个方法只管**这一次露面**，跟关怀本身的寿命无关。
    //    fadeOut 之后 CareMessage 还是 shown，下次进首页会再冒出来。
    //    什么时候真正退场，由关怀引擎说了算（AI 判替换 / 满 3 天兜底）。

    /// 冒出来。延迟一点点，让首页先安顿下来，别和岛的呼吸抢注意力。
    ///
    /// 从下面、由小到大冒上来（母鸡在下面），像是她刚开口 —— 而不是从天上掉下来。
    func slideIn() {
        aimX = nil
        isHidden = false
        alpha = 0
        transform = CGAffineTransform(translationX: 0, y: 8).scaledBy(x: 0.94, y: 0.94)
        UIView.animate(withDuration: 0.55, delay: 0.4,
                       usingSpringWithDamping: 0.78, initialSpringVelocity: 0,
                       options: [.allowUserInteraction]) {
            self.alpha = 1
            self.transform = .identity
        }
    }

    /// 淡出。用户一开始操作页面就走，不挡路。
    func fadeOut(completion: (() -> Void)? = nil) {
        // 还没冒完就被打断的话，把在途的动画掐掉，否则会跳一下
        layer.removeAllAnimations()
        UIView.animate(withDuration: 0.26, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.alpha = 0
            self.transform = CGAffineTransform(translationX: 0, y: -6).scaledBy(x: 0.97, y: 0.97)
        } completion: { _ in
            self.isHidden = true
            completion?()
        }
    }
}
