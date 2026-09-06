//
//  HenStageView.swift
//  Slime
//

import UIKit

/// 聊天页的母鸡。她不是挂件，是**整页的背景** ——
/// 按屏宽铺满、底部沉到输入条下面被裁掉，气泡从她身上飘过去。
///
/// 三层同一个轮廓叠出来（素材是分开导的，所以能分层动）：
///
///     auraFar   浅黄外圈   最淡，只是让她周围有一圈光
///     auraNear  深黄内圈   贴着身体的那道边
///     body      本体       红冠、闭眼、腮红、翅膀
///
/// 开屏的「波浪散开」用的也是这个轮廓：临时复制几层出来往外扩散 + 淡出。
/// 用她自己的形状而不是同心圆，荡开的才像是她身上散出来的。
final class HenStageView: UIView {

    private let auraFar = UIImageView(image: UIImage(named: "hen_aura_far"))
    private let auraNear = UIImageView(image: UIImage(named: "hen_aura_near"))
    private let body = UIImageView(image: UIImage(named: "hen_chat"))

    // MARK: - 构图旋钮

    /// 母鸡占屏宽的倍数。>1 会往两边溢出，参考图里她是顶满的
    private let widthRatio: CGFloat = 1.04
    /// 往下沉多少（占她自身高度的比例）—— 沉下去的那截被输入条裁掉
    private let sinkRatio: CGFloat = 0.10

    /// 两层光晕的静态透明度
    private let farAlpha: CGFloat = 0.45
    private let nearAlpha: CGFloat = 0.9

    /// 两层光晕相对本体放大多少。
    ///
    /// **三层用同一个 frame 的话，本体会把它们盖得一点不剩** ——
    /// 你参考图里那圈深黄边，正是因为它比本体大一圈才露得出来。
    /// near 是贴着身体那道边，far 是再往外一圈更淡的光。
    private let nearScale: CGFloat = 1.10
    private let farScale: CGFloat = 1

    // MARK: -

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false   // 她只负责好看，不吃触摸

        for v in [auraFar, auraNear, body] {
            v.contentMode = .scaleAspectFit
            addSubview(v)
        }
        auraFar.alpha = farAlpha
        auraNear.alpha = nearAlpha
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let image = body.image, image.size.width > 0 else { return }

        let w = bounds.width * widthRatio
        let h = w * image.size.height / image.size.width
        // 底对齐到视图底，再往下推 sinkRatio，身体下缘就被裁掉一截
        let rect = CGRect(x: (bounds.width - w) / 2,
                          y: bounds.height - h + h * sinkRatio,
                          width: w, height: h)

        // 轮廓一样，靠大小拉开层次：本体最小，往外一层比一层大
        body.frame = rect
        auraNear.frame = rect.scaled(by: nearScale)
        auraFar.frame = rect.scaled(by: farScale)
    }

    // MARK: - 开屏的波浪

    /// 从她身上荡开三圈，跑完就停。**不循环** ——
    /// 常驻的扩散动画会一直抢注意力，而这是个「你来了」的招呼，说完就该安静。
    func playEntranceRipple() {
        emitWave(delay: 0)
        emitWave(delay: 0.42)
        emitWave(delay: 0.84)
    }

    private func emitWave(delay: TimeInterval) {
        guard let image = auraFar.image else { return }

        // 每一圈都是临时复制出来的，扩散完就销毁。
        // 这样静态的那两层完全不受影响 —— 不会出现「扩散完弹回原位」的那一下跳。
        let wave = UIImageView(image: image)
        wave.contentMode = .scaleAspectFit
        wave.frame = auraFar.frame
        wave.alpha = 0
        insertSubview(wave, at: 0)

        UIView.animateKeyframes(withDuration: 1.8, delay: delay, options: [.calculationModeCubic]) {
            // 先亮起来
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.18) {
                wave.alpha = 0.7
            }
            // 整段都在往外扩
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 1) {
                wave.transform = CGAffineTransform(scaleX: 1.32, y: 1.32)
            }
            // 扩到一半开始化掉
            UIView.addKeyframe(withRelativeStartTime: 0.28, relativeDuration: 0.72) {
                wave.alpha = 0
            }
        } completion: { _ in
            wave.removeFromSuperview()
        }
    }

    // MARK: - 待机与说话

    /// 待机时极慢的一次呼吸，幅度小到几乎看不出来，但少了她就像张贴纸。
    func startBreathing() {
        guard body.layer.animation(forKey: "breathe") == nil else { return }

        let breathe = CABasicAnimation(keyPath: "transform.scale")
        breathe.fromValue = 1.0
        breathe.toValue = 1.018
        breathe.duration = 2.8
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        body.layer.add(breathe, forKey: "breathe")

        // 光晕跟着涨落，慢半拍，看着像身上的光在动
        let glow = CABasicAnimation(keyPath: "opacity")
        glow.fromValue = farAlpha
        glow.toValue = farAlpha * 1.5
        glow.duration = 3.4
        glow.autoreverses = true
        glow.repeatCount = .infinity
        glow.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        auraFar.layer.add(glow, forKey: "glow")
    }

    func stopBreathing() {
        body.layer.removeAnimation(forKey: "breathe")
        auraFar.layer.removeAnimation(forKey: "glow")
    }

    /// 说话时轻微起伏。
    /// 用 translation.y，和呼吸的 scale 是 transform 的两个不同子属性，
    /// 可以同时跑而不打架 —— 换成两个都写 transform 就会互相盖掉。
    func startTalking() {
        guard body.layer.animation(forKey: "talk") == nil else { return }

        let bob = CABasicAnimation(keyPath: "transform.translation.y")
        bob.fromValue = 0
        bob.toValue = -7
        bob.duration = 0.38
        bob.autoreverses = true
        bob.repeatCount = .infinity
        bob.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        body.layer.add(bob, forKey: "talk")
    }

    func stopTalking() {
        body.layer.removeAnimation(forKey: "talk")
    }
}

private extension CGRect {
    /// 绕中心等比缩放。k > 1 是放大（insetBy 吃负值就是往外扩）。
    func scaled(by k: CGFloat) -> CGRect {
        insetBy(dx: width * (1 - k) / 2, dy: height * (1 - k) / 2)
    }
}
