//
//  SlimeItem.swift
//  Slime
//
//  Created by shiying on 2026/7/6.
//

import Foundation

/// 一篇日记的值类型。**`PostRepository` 对外只给这个**，`Post` 托管对象出不了仓库。
nonisolated struct SlimeItem: Hashable {
    let id: UUID
    let content: String
    let createdAt: Date
    /// nil = AI 还没读过这篇。不是 calm，不是任何一种情绪 —— 下游见到 nil 就少用一条参考，别猜。
    let emotion: SlimeEmotion?
    let reply: String?
    /// 这篇算哪一天（那天的零点）。仓库算好了给出来，**下游直接用，别自己再算** ——
    /// 「算哪天」的规则只在 `CoreDataPostRepository` 里。
    /// （以前这里是可选的 `dayKey`，每个用的地方都得自己写一遍 `?? startOfDay(createdAt)`。）
    let day: Date
}
