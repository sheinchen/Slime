//
//  SlimeView.swift
//  Slime
//
//  Created by shiying on 2026/7/8.
//

import Foundation
import UIKit

final class SlimeView: UIView {
    
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
}
