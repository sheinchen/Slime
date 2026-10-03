//
//  ChatModels.swift
//  Slime
//
//  Created by shiying on 2026/8/1.
//

import Foundation

/// 谁说的
enum ChatRole: String {
    case user
    case slime
}

/// 一句话。只活在这一次对话里（ChatViewModel.messages），不存库
nonisolated struct ChatMessageItem: Hashable {
    let id: UUID
    let role: ChatRole
    let content: String
    let createdAt: Date
}
