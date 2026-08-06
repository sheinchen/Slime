//
//  CareViewModel.swift
//  Slime
//
//  Created by shiying on 2026/7/31.
//

import Foundation

@MainActor
final class CareViewModel {
    
    private let messages: CareMessageStore
    private let cooldowns: CooldownStore
    
    init(messages: CareMessageStore = CoreDataCareMessageStore(),
         cooldowns: CooldownStore = CoreDataCooldownStore()) {
        self.messages = messages
        self.cooldowns = cooldowns
    }
    
    //当前该active的关心
    func activeCare(now: Date = Date()) -> PendingCare? {
        messages.active(now: now)
    }
    
    //状态变shown
    func markShown(_ care: PendingCare) {
        messages.updateStatus(id: care.id, to: .shown)
    }
    
    //状态变read
    func markRead(_ care: PendingCare) {
        messages.updateStatus(id: care.id, to: .read)
        cooldowns.markEngaged(ruleId: care.ruleId)
    }
    
    func markAccepted(_ care: PendingCare) {
        messages.updateStatus(id: care.id, to: .accepted)
    }
}
