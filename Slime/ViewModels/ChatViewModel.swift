//
//  ChatViewModel.swift
//  Slime
//
//  Created by shiying on 2026/8/2.
//

import Foundation

@MainActor
final class ChatViewModel {
    
    //MARK: - 依赖与状态
    private let care: PendingCare
    private let chatRepo: ChatRepository
    private let posts: PostRepository
    private let aiService: AIService
    
    private(set) var session: ChatSessionInfo
    private(set) var messages: [ChatMessageItem] = []
    
    //上下文先带N轮
    private static let maxHistoryTurns = 10
    
    init(care: PendingCare, chatRepo: ChatRepository, posts: PostRepository, aiService: AIService) {
        self.care = care
        self.chatRepo = chatRepo
        self.posts = posts
        self.aiService = aiService
        //同一条关心->同一个会话 历史消息直接恢复
        self.session = chatRepo.findOrCreatedSession(careMessageId: care.id, now: Date())
        self.messages = chatRepo.messages(sessionId: session.id)
        if messages.isEmpty {
            let opening = chatRepo.append(sessionId: session.id, role: .slime, content: care.text, at: Date())
            messages.append(opening)
        }
    }
    
    //MARK: - 对外动作
    /// 发送用户消息:先落库(立刻上屏、失败也不丢),再要回复。
    /// 返回史莱姆的回复;抛错时用户消息已保存,UI 显示重试即可。
    func send(_ text: String) async throws -> ChatMessageItem {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AIError.emptyContent}
        
        let userMessage = chatRepo.append(sessionId: session.id, role: .user, content: trimmed, at: Date())
        messages.append(userMessage)
        return try await requestReply()
    }
    
    func retry() async throws -> ChatMessageItem {
        try await requestReply()
    }
    
    //MARK: - 上下文组装
    private func requestReply() async throws -> ChatMessageItem {
        let reply = try await aiService.chat(messages: buildContext())
        let slimeMessage = chatRepo.append(sessionId: session.id, role: .slime, content: reply, at: Date())
        messages.append(slimeMessage)
        return slimeMessage
    }
    
    /// 按固定顺序组装:①人设+行为约束 ②触发语境 ③最近 N 轮历史(含刚发的用户消息)
    private func buildContext() -> [AIChatMessage] {
        var result: [AIChatMessage] = []
        
        result.append(AIChatMessage(
            role: "system",
            content: DeepSeekAIService.chatSystemPrompt + "\n\n" + triggerContext()))
        
        let recent = messages.suffix(Self.maxHistoryTurns * 2)
        for m in recent {
            result.append(AIChatMessage(
                role: m.role == .user ? "user" : "assistant",
                content: m.content))
        }
        return result
    }
    
    /// 触发语境:这次关心的开场白 + 触发时用户的那几篇帖子(内容+情绪)。
    /// 帖子按"创建时间 ≤ 关心创建时间"查最近 3 篇 —— 正是触发那一刻规则看到的窗口。
    private func triggerContext() -> String {
        let window = posts.fetchAll().filter {
            $0.createdAt <= care.createdAt
        }.prefix(3)
        
        let postLines = window.map { post in
            "- [\(post.emotion)] \(post.content.prefix(60))"
        }.joined(separator: "\n")
        
        return """
               [背景,只有你自己知道,绝不原样复述给用户]
               你之前主动对用户说了:「\(care.text)」,用户点开并接受了,于是有了这次对话。
               你当时想关心 ta,是因为 ta 最近写了这些(方括号是当时的情绪):
               \(postLines)
               对话要接得住这个语境:你知道 ta 最近的状态,自然地延续那句开场白,不要从"你好呀"重新开始,也不要机械重复开场白。
               """
    }
    
}
