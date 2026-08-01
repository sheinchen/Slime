//
//  CareRule.swift
//  Slime
//
//  Created by shiying on 2026/7/29.
//

import Foundation

struct RuleContext {
    let posts: PostRepository
    let cooldowns: CooldownStore
    let now: Date
}

//一条主动关心
protocol CareRule {
    var id: String { get }
    var triggerEvents: Set<CareEvent> { get }
    var cooldown: TimeInterval? { get }
    func evaluate(_ context: RuleContext) -> CareReason?
}

protocol CareOpeningProvider {
    func opening(for reason: CareReason) async throws -> String
}
