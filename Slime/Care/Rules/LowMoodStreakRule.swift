//
//  LowMoodStreakRule.swift
//  Slime
//
//  Created by shiying on 2026/7/30.
//

import Foundation

struct LowMoodStreakRule: CareRule {
    
    let id = "lowMoodStreak"
    let triggerEvents: Set<CareEvent> = [.postSaved]
    let cooldown: TimeInterval? = 7 * 24 * 60 * 60
    
    private static let negative: Set<SlimeEmotion> = [.sad,.anxious,.tired]
    private static let windowSize = 3
    
    func evaluate(_ context: RuleContext) -> CareReason? {
        let recent = context.posts.fetchAll().prefix(Self.windowSize) //fetchAll已经按时间排序
        guard recent.count == Self.windowSize else { return nil}
        let allNegative = recent.allSatisfy { post in
            guard let emotion = SlimeEmotion(rawValue: post.emotion) else { return false }
            return Self.negative.contains(emotion)
        }
        return allNegative ? .lowMoodStreak(count: Self.windowSize) : nil
    }
}
