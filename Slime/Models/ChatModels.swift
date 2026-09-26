//
//  ChatModels.swift
//  Slime
//
//  Created by shiying on 2026/8/1.
//

import Foundation

//便于存库
enum ChatRole: String {
    case user
    case slime
}

//一条聊天记录
nonisolated struct ChatMessageItem: Hashable {
    let id: UUID
    let role: ChatRole
    let content: String
    let createdAt: Date
}

//一个会话基本信息
struct ChatSessionInfo {
    let id: UUID
    let careMessageId: UUID?
    let createdAt: Date
    let title: String?
    let updatedAt: Date
}

//聊天入口
//
// 以前还有一个 `.care(PendingCare)`：从关怀卡片点进来、带着那句话开场。
// v1 遗留 —— 关怀卡片纯只读是明确的产品选择，全项目没有一处构造过它。
// 它还会拿当时的日记给聊天当背景，跟「关怀只看蛋」相悖。09-25 删。
enum ChatOrigin {
    case direct
    case resume(ChatSessionInfo)
}
