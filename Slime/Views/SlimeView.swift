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
    
    private let breathingKey = "breathing"
    
    var emotion: SlimeEmotion = .happy {
        didSet {setNeedsLayout()}
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
        
        bodyLayer.fillColor = UIColor(red: 0.56, green: 0.82, blue: 0.55, alpha: 1).cgColor
        
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
}
