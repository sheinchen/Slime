////
//  EggView.swift
//  Slime
//
//  Created by shiying on 2026/8/24.
//

import Foundation
import UIKit

extension SlimeEmotion {
    var eggAsset: String {
        switch self {
        case .happy:   return "egg_happy"
        case .calm:    return "egg_calm"
        case .sad:     return "egg_sad"
        case .angry:   return "egg_angry"
        case .anxious: return "egg_anxious"
        case .tired:   return "egg_tired"
        }
    }
}

final class EggView: UIImageView {
    
    var emotion: SlimeEmotion? {
        didSet {
            guard emotion != oldValue else { return }
            updateImage()
        }
    }
    
    /// 刚下出来、还没揭晓的空白蛋。
    ///
    /// 单独立一个开关、而不是让 `emotion == nil` 直接画空白蛋 ——
    /// 因为周条上「那天没写日记」也是 nil，那种情况要什么都不画。
    /// 两种 nil 语义不同，混在一起周条上每个空日子都会冒出一颗白蛋。
    var isBlank = false {
        didSet {
            guard isBlank != oldValue else { return }
            updateImage()
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        contentMode = .scaleAspectFit
        isUserInteractionEnabled = false
        updateImage()
    }
    
    convenience init(emotion: SlimeEmotion? = nil) {
        self.init(frame: .zero)
        self.emotion = emotion
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func updateImage() {
        if let emotion {
            image = UIImage(named: emotion.eggAsset)
        } else {
            image = isBlank ? UIImage(named: "egg_blank") : nil
        }
    }
    
    // MARK: - 揭晓
    
    /// 空白蛋变成情绪蛋。
    ///
    /// 不直接换 `image` —— 那是硬切，一帧之间换了张图，读起来像加载失败。
    /// 这里把新图当一层盖在上面淡入，淡完再换掉底图、把盖的那层撤走，
    /// 同时整颗蛋 pop 一下。跟 `SlimeView.reveal` 是一个思路。
    func reveal(to emotion: SlimeEmotion, completion: (() -> Void)? = nil) {
        guard self.emotion != emotion else {
            completion?()
            return
        }
        guard let next = UIImage(named: emotion.eggAsset) else {
            self.emotion = emotion
            completion?()
            return
        }
        
        let overlay = UIImageView(image: next)
        overlay.contentMode = contentMode
        overlay.frame = bounds
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.alpha = 0
        addSubview(overlay)
        
        let pop = CAKeyframeAnimation(keyPath: "transform.scale")
        pop.values = [1, 1.15, 0.96, 1]
        pop.keyTimes = [0, 0.34, 0.7, 1]
        pop.duration = 0.52
        pop.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(pop, forKey: "reveal")
        
        UIView.animate(withDuration: 0.36) {
            overlay.alpha = 1
        } completion: { _ in
            self.isBlank = false
            self.emotion = emotion
            overlay.removeFromSuperview()
            completion?()
        }
    }
}
