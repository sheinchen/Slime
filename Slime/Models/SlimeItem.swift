//
//  SlimeItem.swift
//  Slime
//
//  Created by shiying on 2026/7/6.
//

import Foundation

nonisolated struct SlimeItem: Hashable {
    let id: UUID
    let content: String
    let createdAt: Date
    /// nil = AI 还没读过这篇。不是 calm，不是任何一种情绪 —— 下游见到 nil 就少用一条参考，别猜。
    let emotion: SlimeEmotion?
    let reply: String?
    let dayKey: Date?
}
