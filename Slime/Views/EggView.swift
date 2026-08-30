//
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
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        contentMode = .scaleAspectFit
        isUserInteractionEnabled = false
    }
    
    convenience init(emotion: SlimeEmotion? = nil) {
        self.init(frame: .zero)
        self.emotion = emotion
        isUserInteractionEnabled = false
        updateImage()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func updateImage() {
        image = emotion.flatMap {
            UIImage(named: $0.eggAsset)
        }
    }
    
}
