//
//  MoodRecoverRule.swift
//  Slime
//
//  Created by shiying on 2026/7/30.
//

import Foundation

//配对型冷却
struct MoodRecoverRule: CareRule {
    
    let id = "moodRecovered"
    let triggerEvents: Set<CareEvent> = [.postSaved]
    let cooldown: TimeInterval? = nil
    
    //情绪回升匹配
    private static let pairedRuleId = "lowMoodStreak"
    private static let positive: Set<SlimeEmotion> = [.happy,.calm]
    
    func evaluate(_ context: RuleContext) -> CareReason? {
        guard let low = context.cooldowns.lastTrigger(ruleId: Self.pairedRuleId) else { return nil}
        if let mine = context.cooldowns.lastTrigger(ruleId: id),
           mine.lastTriggeredAt > low.lastTriggeredAt {
            return nil
        }
        
        guard let latest  = context.posts.fetchAll().first,
              latest.createdAt > low.lastTriggeredAt,
              let emotion = SlimeEmotion(rawValue: latest.emotion),
              Self.positive.contains(emotion) else { return nil }
        
        return .moodRecovered
    }
}
