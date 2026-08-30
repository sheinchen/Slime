//
//  NestStageView.swift
//  Slime
//
//  Created by shiying on 2026/8/25.
//

import UIKit
import SnapKit

class NestStageView: UIView {
    
    private let imageView = UIImageView()
    private let captionLabel = UILabel()
    
    private var sizeConstraint: Constraint!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        imageView.contentMode = .scaleAspectFit
        captionLabel.textAlignment = .center
        addSubview(imageView)
        addSubview(captionLabel)
        
        imageView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview()
            sizeConstraint = make.height.equalTo(190).constraint
            make.width.equalTo(imageView.snp.height)
        }
        captionLabel.snp.makeConstraints { make in
            make.top.equalTo(imageView.snp.bottom).offset(10)
            make.centerX.equalToSuperview()
            make.bottom.lessThanOrEqualToSuperview()
            
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configure(_ day: SquareViewModel.Day) {
        if let egg = day.egg {
            imageView.image = UIImage(named: egg.emotion.eggAsset)
            imageView.alpha = 1
            sizeConstraint.update(offset: 124)
            captionLabel.attributedText = Kai.attributed(egg.text, size: 15, color: Sky.ink(0.42), lineHeight: 15 * 1.6)
        } else if day.isToday {
            imageView.image = UIImage(named: "hen_idle")
            imageView.alpha = 1
            sizeConstraint.update(offset: 190)
            captionLabel.attributedText = Kai.attributed("今天还在继续", size: 14, color: Sky.ink(0.34))
        } else {
            //to:do 石化母鸡
            imageView.image = nil
            sizeConstraint.update(offset: 124)
            captionLabel.attributedText = Kai.attributed(day.hasEntries ? "还在孵" : "你没有理我 咕咕呜呜", size: 14, color: Sky.ink(0.28))
        }
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
}
