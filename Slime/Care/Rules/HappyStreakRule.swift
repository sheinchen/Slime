//
//  HappyStreakRule.swift
//  Slime
//
//  Created by shiying on 2026/7/30.
//

import Foundation

struct HappyStreakRule: CareRule {
    
    let id = "happyStreak"
    let triggerEvents: Set<CareEvent> = [.postSaved]
    let cooldown: TimeInterval? = 7 * 24 * 60 * 60
    
    private static let windowSize = 3
    
    func evaluate(_ context: RuleContext) -> CareReason? {
        let recent = context.posts.fetchAll().prefix(Self.windowSize)
        guard recent.count == Self.windowSize else { return nil }
        
        let allHappy = recent.allSatisfy {
            SlimeEmotion(rawValue: $0.emotion) == .happy
        }
        return allHappy ? .happyStreak(count: Self.windowSize) : nil
    }
}
