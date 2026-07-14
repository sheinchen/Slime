//
//  SlimeEmotion.swift
//  Slime
//
//  Created by shiying on 2026/7/8.
//

import Foundation

enum SlimeEmotion: String {
    case happy
    case calm
    case sad
    case angry
    
    static func random() -> SlimeEmotion {
        [.happy, .calm, .sad, .angry].randomElement()!
    }
}

enum SlimeSpecialState {
    case none
    case rainbow
}
