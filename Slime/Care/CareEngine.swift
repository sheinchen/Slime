//
//  CareEngine.swift
//  Slime
//
//  Created by shiying on 2026/7/29.
//

import Foundation

@MainActor
final class CareEngine {

    private let rules: [CareRule] //关心仲裁优先
    private let posts: PostRepository
    private let cooldowns: CooldownStore
    private let messages: CareMessageStore
    private let openingProvider: CareOpeningProvider
    
    init(rules: [CareRule], posts: PostRepository, cooldowns: CooldownStore, messages: CareMessageStore, openingProvider: CareOpeningProvider) {
        self.rules = rules
        self.posts = posts
        self.cooldowns = cooldowns
        self.messages = messages
        self.openingProvider = openingProvider
    }
    
    func handle(_ event: CareEvent, now: Date = Date()) async {
        //先清理
        messages.sweepExpired(now: now).forEach {
            cooldowns.markIgnored(ruleId: $0)
        }
        
        let context = RuleContext(posts: posts, cooldowns: cooldowns, now: now)
        
        for rule in rules {
            //1.过滤不相关事件
            guard rule.triggerEvents.contains(event) else { continue }
            
            //2.时间性冷却：还在冷却期就跳过
            if let cooldown = rule.cooldown,
               let last = cooldowns.lastTrigger(ruleId: rule.id),
               now.timeIntervalSince(last.lastTriggeredAt) < cooldown {
                continue
            }
            
            //3.规则自己查数据
            guard let reason = rule.evaluate(context) else { continue }
            
            //4.reason到关心
            guard let text = try? await openingProvider.opening(for: reason) else { return }
            
            //5.执行
            messages.save(ruleId: rule.id, text: text, now: now).forEach {
                cooldowns.markIgnored(ruleId: $0)
            }
            cooldowns.recordTrigger(ruleId: rule.id, at: now)
            return
        }
        
    }
}

