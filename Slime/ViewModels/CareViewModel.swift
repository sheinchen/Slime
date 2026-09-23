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
    
    init(messages: CareMessageStore? = nil) {
        self.messages = messages ?? CoreDataCareMessageStore()
    }
    
    func activeCare() -> PendingCare? {
            messages.active()
        }

    /// 这条话**真的被看到了**。
    ///
    /// 调用点在 `HomeViewController`：卡片滑出后活满 `firstSeenThreshold` 秒才调。
    /// 被用户的操作打断的那次不算 —— 下次进首页它仍然享受完整的「首次」待遇。
    ///
    /// 这个方法只写「露面的生命」，**不碰 status**：
    /// 什么时候真正退场仍然是关怀引擎说了算（AI 判替换 / 满 3 天兜底）。
    func markSeen(_ id: UUID, at date: Date = Date()) {
        messages.markFirstSeen(id: id, at: date)
    }
}
