//
//  PendingCare.swift
//  Slime
//
//  Created by shiying on 2026/7/23.
//

import Foundation

enum CareStatus: String {
    case pending // 已生成 没看到
    case shown // 用户看到气泡 未点击
    case read // 点开气泡
    case accepted // 进入聊天
    case ignored // 没有点击气泡
}

//给UI的值类型
struct PendingCare {
    let id: UUID
    let ruleId: String
    let text: String
    let createdAt: Date
}
