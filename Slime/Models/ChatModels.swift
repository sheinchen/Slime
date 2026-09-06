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
enum ChatOrigin {
    case direct
    case care(PendingCare)
    case resume(ChatSessionInfo)
}
