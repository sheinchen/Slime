////
//  NestStageView.swift
//  Slime
//
//  Created by shiying on 2026/8/25.
//

import UIKit
import SnapKit

class NestStageView: UIView {
    
    /// 只管母鸡和占位。蛋归 `eggView`。
    /// 它还兼着一个活：撑着 captionLabel 的位置，鸡 190、蛋 124。
    private let imageView = UIImageView()
    private let eggView = EggView()
    private let captionLabel = UILabel()
    
    private var sizeConstraint: Constraint!
    
    private static let henSide: CGFloat = 190
    private static let eggSide: CGFloat = 124
    
    // MARK: - 按压
    
    private var press = HenPress()
    /// 只在按压期间跑。没人按的时候不该有个 link 空转着烧电。
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    
    /// 舞台上现在摆的是母鸡吗。是蛋/占位就按不动。
    private var isHen = false
    
    /// 脚底在这张图里的高度位置（0 = 图顶，1 = 图底）。
    /// hen_idle 底下有一截透明留白，脚大约在 83% 处。
    /// 压扁要绕**脚底**那条线，绕图片底边的话她会浮起来一点点。
    private let footRatio: CGFloat = 0.83
    
    /// 蓄到这里蛋才开始冒头。之前那段她只是在使劲，还没有东西出来。
    private let eggAppearAt: CGFloat = 0.12
    /// 刚冒头时多大（占最终 124 的比例）。
    private let eggMinScale: CGFloat = 0.05
    /// 蓄满时露出来多大。
    private let eggMaxScale: CGFloat = 0.44
    /// 蛋往她身体里缩进去多少 pt。
    /// 早期被她挡住一截，才像「从里面出来」而不是「凭空长在地上」。
    private let eggEmergeInset: CGFloat = 22
    
    private let pressHaptic = UIImpactFeedbackGenerator(style: .light)
    /// 蓄力途中敲触觉的几个点。**间距越来越密** ——
    /// 均匀分布节奏是恒定的，读起来像手机在震；越敲越密才是「快出来了」。
    private static let hapticSteps: [CGFloat] = [0.25, 0.45, 0.62, 0.76, 0.87, 0.95]
    private var nextHapticStep = 0
    
    
    
    // MARK: - 下蛋
    
    /// 正在演下蛋。演出期间 `layoutSubviews` 不许碰蛋的位置。
    private var isLaying = false
    /// 蛋落定没有。没落定之前不揭晓。
    private var eggHasLanded = false
    /// 总结比蛋先回来时先存这儿，等落定再揭晓。
    private var pendingReveal: SlimeEmotion?
    
    /// 今天能不能下蛋（有没有日记、是不是已经下过）。返回 false 就按不动。
    var canLay: (() -> Bool)?
    /// 蓄力过半。上层该在这时候把 AI 总结**提前**发出去。
    var onPressHalfway: (() -> Void)?
    /// 蓄满了，蛋开始往外挤。上层该在这时候去等总结结果。
    var onDidLay: (() -> Void)?
    
    // MARK: -
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        imageView.contentMode = .scaleAspectFit
        captionLabel.textAlignment = .center
        addSubview(imageView)
        addSubview(eggView)
        addSubview(captionLabel)
        
        imageView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview()
            sizeConstraint = make.height.equalTo(Self.henSide).constraint
            make.width.equalTo(imageView.snp.height)
        }
        captionLabel.snp.makeConstraints { make in
            make.top.equalTo(imageView.snp.bottom).offset(10)
            make.centerX.equalToSuperview()
            make.bottom.lessThanOrEqualToSuperview()
        }
        
        // 蛋不上约束，走 frame —— 下蛋时它要从她脚底飞到台中央，
        // 用约束做这种自由飞行每一步都要 layoutIfNeeded，很难写。
        eggView.isHidden = true
        
        // UIImageView 默认不吃触摸，不开这个手势收不到事件
        imageView.isUserInteractionEnabled = true
        
        // minimumPressDuration = 0：手指一落就进 .began，蓄力从第 0 毫秒开始算。
        // 用默认的 0.5 秒的话，前半秒完全没反馈，按下去像坏了。
        //
        // cancelsTouchesInView = false：别把触摸吞掉。
        // 这个舞台外面套着 RootPager 的横向 scrollView，
        // 吞掉之后按着母鸡就没法左右翻页了。
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(henPressed))
        hold.minimumPressDuration = 0
        hold.cancelsTouchesInView = false
        hold.delaysTouchesBegan = false
        imageView.addGestureRecognizer(hold)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /// 蛋落定后待的地方：跟原来「有蛋那格」一样，124 见方、居中、贴着舞台顶。
    private var eggRestCenter: CGPoint {
        CGPoint(x: bounds.midX, y: Self.eggSide / 2)
    }
    
    private var footY: CGFloat {
           let h = imageView.bounds.height
           return imageView.center.y - h / 2 + h * footRatio
       }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        // 蛋走 frame 布局，所以得自己摆。
        // **演出期间必须躲开** —— 否则会把飞到一半的蛋一把拽回台中央。
        guard !isLaying, press.progress <= 0.001 else { return }
        eggView.bounds = CGRect(origin: .zero,
                                size: CGSize(width: Self.eggSide, height: Self.eggSide))
        eggView.center = eggRestCenter
    }
    
    // MARK: - 摆台
    
    func configure(_ day: SquareViewModel.Day) {
        resetStage()
        
        if let egg = day.egg, !(day.isToday && day.needsHatch) {
            showEgg(egg.emotion)
            captionLabel.attributedText = Kai.attributed(egg.text, size: 15, color: Sky.ink(0.42), lineHeight: 15 * 1.6)
        } else if day.isToday {
            showHen()
            captionLabel.attributedText = Kai.attributed("今天还在继续", size: 14, color: Sky.ink(0.34))
        } else {
            //to:do 石化母鸡
            showPlaceholder()
            captionLabel.attributedText = Kai.attributed(day.hasEntries ? "还在孵" : "你没有理我 咕咕呜呜", size: 14, color: Sky.ink(0.28))
        }
    }
    
    private func showHen() {
        imageView.image = UIImage(named: "hen_idle")
        imageView.alpha = 1
        sizeConstraint.update(offset: Self.henSide)
        eggView.isHidden = true
        isHen = true
    }
    
    private func showEgg(_ emotion: SlimeEmotion) {
        imageView.image = nil
        imageView.alpha = 0          // 看不见，但还撑着 caption 的位置
        sizeConstraint.update(offset: Self.eggSide)
        eggView.isBlank = false
        eggView.emotion = emotion
        eggView.isHidden = false
        eggHasLanded = true
        isHen = false
        setNeedsLayout()
    }
    
    private func showPlaceholder() {
        imageView.image = nil
        imageView.alpha = 1
        sizeConstraint.update(offset: Self.eggSide)
        eggView.isHidden = true
        isHen = false
    }
    
    /// 换内容前把上一格留下的一切擦掉：按到一半的压扁、演到一半的下蛋。
    private func resetStage() {
        resetPress()
        imageView.layer.removeAllAnimations()
        eggView.layer.removeAllAnimations()
        imageView.transform = .identity
        eggView.transform = .identity
        eggView.alpha = 1
        isLaying = false
        eggHasLanded = false
        pendingReveal = nil
        setNeedsLayout()
    }
    
    private static func caption(_ emotion: SlimeEmotion) -> String {
           switch emotion {
           case .happy:   return "那天是开心的"
           case .calm:    return "那天很平静"
           case .sad:     return "那天有点难过"
           case .angry:   return "那天有点生气"
           case .anxious: return "那天有点悬着"
           case .tired:   return "那天很累"
           }
       }
    
    // MARK: - 按住她
    
    @objc private func henPressed(_ g: UILongPressGestureRecognizer) {
        switch g.state {
        case .began:
            guard isHen, canLay?() ?? false else { return }
            eggView.isBlank = true
            eggView.emotion = nil
            eggView.alpha = 1
            insertSubview(eggView, aboveSubview: imageView)
            pressHaptic.prepare()
            press.begin()
            startLoop()
            
        case .ended, .cancelled, .failed:
            // 横向翻页时 scrollView 会抢走手势，这里收到 .cancelled，
            // 蓄力自动回落 —— 不用为翻页写任何额外代码。
            press.end()
            
        default:
            break
        }
    }
    
    private func startLoop() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        lastTimestamp = 0
    }
    
    private func stopLoop() {
        displayLink?.invalidate()
        displayLink = nil
    }
    
    @objc private func step(_ link: CADisplayLink) {
        if lastTimestamp == 0 {
            lastTimestamp = link.timestamp
            return
        }
        // 切后台再回来会攒出一个巨大的 dt，钳住，否则一回来就直接蓄满
        let dt = min(link.timestamp - lastTimestamp, 1.0 / 20.0)
        lastTimestamp = link.timestamp
        
        let out = press.update(dt: dt)
        apply(out)
        updateHaptics(progress: out.progress)
        
        switch out.signal {
        case .prefetch:
            onPressHalfway?()
        case .lay:
            performLay()
            onDidLay?()
        case nil:
            break
        }
        
        // 回落到 0 且手指也松了，就把帧循环关掉。
        // 但下蛋演出期间别去动 imageView 的 transform —— 那会儿它归演出管。
        if out.progress <= 0.001, !press.isPressing {
            if !isLaying { imageView.transform = .identity }
            stopLoop()
        }
    }
    
    private func apply(_ out: HenPress.Output) {
        let h = imageView.bounds.height
        let pivotY = h * footRatio
        
        // transform 的缩放是**绕中心**的，直接压会让她整个往下陷进地里。
        // 想绕脚底压，正规做法是改 anchorPoint，但那会跟 SnapKit 的约束打架
        // （anchorPoint 一改 frame 就跳）。
        // 所以改成「照常绕中心压 + 补一个平移把脚底那条线拽回原位」，效果等价。
        //
        // 推导：中心下方距离 d 的点，缩放后位移 d*(sy-1)。
        // 脚底的 d = pivotY - h/2，补上相反数就抵掉了。
        let dy = (pivotY - h / 2) * (1 - out.scaleY)
        
        // 抖动走平移分量，压扁走缩放分量 —— 同一个 transform 里两者不打架。
        // 注意顺序：scaledBy 是先缩放后平移，所以 shake/dy 就是屏幕上的 pt。
        imageView.transform = CGAffineTransform(translationX: out.shake, y: dy)
            .scaledBy(x: out.scaleX, y: out.scaleY)
        
        // 蛋在蓄力期间由 progress 驱动；一旦进了下蛋演出就交给动画，这里撒手。
        guard !isLaying else { return }
        updateEgg(progress: out.progress, shake: out.shake)
    }
    
    /// 蛋跟着蓄力一起从她屁股底下长出来。
    private func updateEgg(progress: CGFloat, shake: CGFloat) {
        guard progress > 0.001 else {
            eggView.isHidden = true
            return
        }
        
        // 前 eggAppearAt 那段她只是在使劲，蛋还没出来。
        // 之后把剩下的区间重新拉回 0…1，蛋在这段里长大。
        let t = max(0, (progress - eggAppearAt) / (1 - eggAppearAt))
        let scale = eggMinScale + (eggMaxScale - eggMinScale) * t
        let side = Self.eggSide * scale
        
        eggView.isHidden = false
        // bounds 始终是最终尺寸，缩放全交给 transform ——
        // bounds 一路变的话 scaleAspectFit 每帧都要重算贴图位置，图会抖。
        eggView.bounds = CGRect(origin: .zero,
                                size: CGSize(width: Self.eggSide, height: Self.eggSide))
        eggView.transform = CGAffineTransform(scaleX: scale, y: scale)
        
        // 让蛋的**上缘**贴着脚底那条线往下长，中心跟着尺寸走。
        // 中心固定的话它是四面一起胀，看着像凭空出现，不像被顶出来。
        eggView.center = CGPoint(x: imageView.center.x + shake * 0.6,
                                 y: footY + side / 2 - eggEmergeInset)
    }
    
    private func updateHaptics(progress: CGFloat) {
        guard progress > 0.001 else {
            nextHapticStep = 0
            return
        }
        while nextHapticStep < Self.hapticSteps.count,
              progress >= Self.hapticSteps[nextHapticStep] {
            pressHaptic.impactOccurred(intensity: 0.35 + 0.65 * progress)
            nextHapticStep += 1
        }
    }
    
    private func resetPress() {
        press.reset()
        stopLoop()
        nextHapticStep = 0
        imageView.transform = .identity
    }
    
    // MARK: - 下蛋
    
    /// 蓄满之后的整段演出：蛋从她身下挤出来 → 她退场 → 蛋滑到台中央长大。
    /// 蓄满之后的演出。蛋这会儿已经长到 eggMaxScale 卡在她身下了，
    /// 所以这里只剩两件事：让它脱身，然后滑到台中央长到正常大小。
    private func performLay() {
        guard !isLaying else { return }
        isLaying = true
        isHen = false          // 下过了，这一格不能再按
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        
        // 脱身：往下滑一小截，把 eggEmergeInset 那截也吐出来。
        // 很短，只是给「啵」这一下一个落点。
        let side = Self.eggSide * eggMaxScale
        UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut]) {
            self.eggView.center = CGPoint(x: self.imageView.center.x,
                                          y: self.footY + side / 2 + 10)
        } completion: { _ in
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            self.settleEgg()
        }
    }
    
    /// 段二：她退场，蛋滑到台中央长到正常大小。
    private func settleEgg() {
        // caption 本来吊在 190 高的母鸡下面，蛋只有 124。
        // 约束改动跟着一起 animate（靠 layoutIfNeeded），文案平滑往上收，不会跳。
        sizeConstraint.update(offset: Self.eggSide)
        
        UIView.animate(withDuration: 0.52, delay: 0.08,
                       usingSpringWithDamping: 0.82, initialSpringVelocity: 0) {
            self.imageView.alpha = 0
            self.eggView.transform = .identity
            self.eggView.center = self.eggRestCenter
            self.layoutIfNeeded()
        } completion: { _ in
            self.isLaying = false
            self.eggHasLanded = true
            if let emotion = self.pendingReveal {
                self.pendingReveal = nil
                self.eggView.reveal(to: emotion)
            }
        }
    }
    
    /// 空白蛋揭晓成情绪蛋。
    ///
    /// 总结可能比蛋先回来 —— 那就先存着，等落定再演。
    /// 不存的话揭晓的 pop 动画会跟落定动画抢同一个 transform，蛋会乱跳。
    func revealEgg(to emotion: SlimeEmotion) {
        guard eggHasLanded else {
            pendingReveal = emotion
            return
        }
        eggView.reveal(to: emotion)
    }
    
    func setCaption(_ text: String) {
        captionLabel.attributedText = Kai.attributed(text, size: 15, color: Sky.ink(0.42), lineHeight: 15 * 1.6)
    }
}
