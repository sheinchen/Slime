//
//  SlimeView.swift
//  Slime
//
//  Created by shiying on 2026/7/8.
//

import Foundation
import UIKit

enum SlimeAction {
    case tapBounce
}

final class SlimeView: UIView {
    
    //呼吸key
    private let breathingKey = "breathing"
    
    //未定型
    private static let undefinedColor = UIColor(white: 0.78, alpha: 1)
    
    
    var emotion: SlimeEmotion = .happy {
        didSet {
            bodyLayer.fillColor = Self.bodyColor(for: emotion).cgColor
            setNeedsLayout()
        }
    }
    
    //编辑文字彩虹态
    var specialState: SlimeSpecialState = .none
    
    //path描边动画
    private let bodyLayer = CAShapeLayer()
    private let leftEyeLayer = CAShapeLayer()
    private let rightEyeLayer = CAShapeLayer()
    private let mouthLayer = CAShapeLayer()
    
    //画法来源
    private let shape: SlimeShapeProviding = BlobSlimeShape()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayers()
    }
    
    required init?(coder: NSCoder) {
        fatalError("")
    }
    
    private func setupLayers() {
        backgroundColor = .clear
        
        bodyLayer.fillColor = Self.bodyColor(for: emotion).cgColor
        
        let eyeColor = UIColor(white: 0.15, alpha: 1).cgColor
        leftEyeLayer.fillColor = eyeColor
        rightEyeLayer.fillColor = eyeColor
        
        mouthLayer.fillColor = UIColor.clear.cgColor
        mouthLayer.strokeColor = UIColor(white: 0.15, alpha: 1).cgColor
        mouthLayer.lineCap = .round
        
        layer.addSublayer(bodyLayer)
        layer.addSublayer(leftEyeLayer)
        layer.addSublayer(rightEyeLayer)
        layer.addSublayer(mouthLayer)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // 留 6% 边距,给动画的挤压/回弹留溢出空间
        let drawRect = bounds.insetBy(dx: bounds.width * 0.06, dy: bounds.height * 0.06)
        
        // 关掉隐式动画:布局重算路径时不想要那 0.25s 的默认过渡
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        [bodyLayer, leftEyeLayer, rightEyeLayer, mouthLayer].forEach {
            $0.frame = bounds
        }
        
        bodyLayer.path = shape.bodyPath(in: drawRect, emotion: emotion).cgPath
        let eyes = shape.eyePaths(in: drawRect, emotion: emotion)
        leftEyeLayer.path = eyes.first?.cgPath
        rightEyeLayer.path = eyes.last?.cgPath
        mouthLayer.path = shape.mouthPath(in: drawRect, emotion: emotion).cgPath
        mouthLayer.lineWidth = max(1.5, bounds.width * 0.03)
        
        CATransaction.commit()
    }
    
    //MARK: 呼吸感
    func startBreathing() {
        guard layer.animation(forKey: breathingKey) == nil else { return }
        let anim  = CASpringAnimation(keyPath: "transform.scale")
        anim.fromValue = 1.0
        anim.toValue = 1.03
        anim.mass = 1.0
        anim.stiffness = 60
        anim.damping = 12
        anim.initialVelocity = 0
        anim.duration = anim.settlingDuration
        anim.autoreverses = true
        anim.repeatCount = .infinity
        anim.isRemovedOnCompletion = false
        
        anim.beginTime = CACurrentMediaTime() - Double.random(in: 0 ..< anim.settlingDuration)
        
        layer.add(anim, forKey: breathingKey)
    }
    
    func stopBreathing() {
        layer.removeAnimation(forKey: breathingKey)
    }
    
    // MARK: - 出现/离屏时自动启停
    override func didMoveToWindow() {
         super.didMoveToWindow()
        if window != nil {
            startBreathing()
        } else {
            stopBreathing()
        }
    }
    
    //MARK: 点击回弹
    func perform(_ action: SlimeAction) {
        switch action {
        case .tapBounce:
            playTapBounce()
        }
    }
    
    private func playTapBounce() {
        stopBreathing()
        //回弹动画
        let anim = CAKeyframeAnimation(keyPath: "transform")
        anim.values = [
            CATransform3DIdentity,
            CATransform3DMakeScale(1.12, 0.88, 1),
            CATransform3DMakeScale(0.94, 1.10, 1),
            CATransform3DMakeScale(1.03, 0.98, 1),
            CATransform3DIdentity,
        ].map { NSValue(caTransform3D: $0) }
        anim.keyTimes = [0,0.18,0.5,0.78,1.0]
        anim.duration = 0.42
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        
        //动画结束恢复呼吸
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            self?.startBreathing()
        }
        layer.add(anim, forKey: "tapBounce")
        CATransaction.commit()
    }
    
    //MARK: 情绪颜色映射
    static func bodyColor(for emotion: SlimeEmotion) -> UIColor {
        switch emotion {
        case .happy: return UIColor(red: 1.00, green: 0.84, blue: 0.35, alpha: 1) //黄
        case .calm:  return UIColor(red: 0.56, green: 0.82, blue: 0.55, alpha: 1)  // 绿
        case .sad:   return UIColor(red: 0.50, green: 0.70, blue: 0.95, alpha: 1)  // 蓝
        case .angry: return UIColor(red: 1.00, green: 0.60, blue: 0.35, alpha: 1)  // 橙
        }
    }
    
    //MARK: 孵化揭晓
    private func setUndefined(_ undefined: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bodyLayer.fillColor = (undefined ? Self.undefinedColor : Self.bodyColor(for: emotion)).cgColor
        let faceOpacity: Float = undefined ? 0 : 1
        leftEyeLayer.opacity = faceOpacity
        rightEyeLayer.opacity = faceOpacity
        mouthLayer.opacity = faceOpacity
        CATransaction.commit()
    }
    
    func hatch(completion: (() -> Void)? = nil) {
        stopBreathing()
        setUndefined(true)
        
        //阶段一：凝结 0.3弹簧放到到1.0
        let grow = CASpringAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.3
        grow.toValue = 1.0
        grow.mass = 1.0
        grow.stiffness = 90
        grow.damping = 13
        grow.initialVelocity = 0
        grow.duration  = grow.settlingDuration
        
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            self?.reveal(completion: completion) //凝结完揭晓
        }
        layer.add(grow, forKey: "hatchGrow")
        CATransaction.commit()
    }
    
    private func reveal(completion: (() -> Void)?) {
        setUndefined(false)
        
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            self?.startBreathing()
            completion?()
        }
        
        //揭晓变色
        let color = CABasicAnimation(keyPath: "fillColor")
        color.fromValue = Self.undefinedColor.cgColor
        color.toValue = Self.bodyColor(for: emotion).cgColor
        color.duration = 0.4
        bodyLayer.add(color, forKey: "revealColor")
        
        //五官淡入
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.4
        [leftEyeLayer, rightEyeLayer, mouthLayer].forEach {
            $0.add(fade, forKey: "faceFade")
        }
        
        //揭晓抖动
        let pop = CAKeyframeAnimation(keyPath: "transform")
        pop.values = [
            CATransform3DIdentity,
            CATransform3DMakeScale(1.12, 0.90, 1),
            CATransform3DMakeScale(0.96, 1.06, 1),
            CATransform3DIdentity,
        ].map { NSValue(caTransform3D: $0)}
        pop.keyTimes = [0, 0.35, 0.7, 1.0]
        pop.duration = 0.45
        layer.add(pop, forKey: "revealPop")
        
        CATransaction.commit()
        
    }
}
