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
    private let origin: ChatOrigin
    private let chatRepo: ChatRepository
    private let posts: PostRepository
    private let aiService: AIService
    
    private var session: ChatSessionInfo?
    private(set) var messages: [ChatMessageItem] = []
    
    //上下文先带N轮
    private static let maxHistoryTurns = 10
    
    //正在流的部分回复
    private(set) var streamingText: String?
    
    init(origin: ChatOrigin, chatRepo: ChatRepository, posts: PostRepository, aiService: AIService) {
        self.origin = origin
        self.chatRepo = chatRepo
        self.posts = posts
        self.aiService = aiService
        
        switch origin {
        case .direct:
            messages = [ChatMessageItem(id: UUID(), role: .slime, content: HenGreeting.random(), createdAt: Date())]
        case .care(let care):
            messages = [ChatMessageItem(id: UUID(), role: .slime, content: care.text, createdAt: Date())]
        case .resume(let existing):
            session = existing
            messages = chatRepo.messages(sessionId: existing.id)
        }
       
    }
    
    @discardableResult
    private func ensureSession() -> ChatSessionInfo {
        if let session { return session }
        let created = chatRepo.createSession(careMessageId: newSessionCareId, now: Date())
        session = created
        for m in messages {
            chatRepo.append(sessionId: created.id, role: m.role, content: m.content, at: m.createdAt)
        }
        return created
    }
    
    //判断新会话是不是主动关心会话
    private var newSessionCareId: UUID? {
        if case .care(let care) = origin { return care.id }
        return nil
    }
    
    //MARK: - 对外动作
    func send(_ text: String, onDelta: @MainActor @escaping () -> Void) async throws -> ChatMessageItem {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AIError.emptyContent}
        
        let isFirstUserMessage = !messages.contains { $0.role == .user }
        
        let s = ensureSession()
        
        let userMessage = chatRepo.append(sessionId: s.id, role: .user, content: trimmed, at: Date())
        messages.append(userMessage)
        
        if isFirstUserMessage {
            chatRepo.updateTitle(sessionId: s.id, title: String(trimmed.prefix(14)))
        }

        
        return try await streamReply(sessionId: s.id, onDelta: onDelta)
    }
    
    func retry(onDelta: @MainActor @escaping () -> Void) async throws -> ChatMessageItem {
        guard let session else { throw AIError.emptyContent }
        return try await streamReply(sessionId: session.id, onDelta: onDelta)
    }
    
    //MARK: - 流式上下文组装
    private func streamReply(sessionId: UUID, onDelta: @MainActor @escaping () -> Void) async throws -> ChatMessageItem {
        streamingText = ""
        onDelta() // 先立一个空气泡
        
        var accumulated = ""
        do {
            // 循环体在主线程，所以更新状态和回调UI安全
            for try await piece in aiService.chatstream(messages: buildContext()) {
                accumulated += piece
                streamingText = accumulated
                onDelta()
            }
        } catch {
            streamingText = nil
            if !accumulated.isEmpty {
                let partial = chatRepo.append(sessionId: sessionId, role: .slime, content: accumulated, at: Date())
                messages.append(partial)
            }
            throw error
        }
        
        streamingText = nil
        let full = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !full.isEmpty else { throw AIError.emptyContent }
        
        let slimeMessage = chatRepo.append(sessionId: sessionId, role: .slime, content: full, at: Date())
        messages.append(slimeMessage)
        return slimeMessage
    }
    
    
    
    
    /// 按固定顺序组装:①人设+行为约束 ②触发语境 ③最近 N 轮历史(含刚发的用户消息)
    private func buildContext() -> [AIChatMessage] {
        var result: [AIChatMessage] = []
        
        result.append(AIChatMessage(
            role: "system",
            content: systemContext()))
        
        let recent = messages.suffix(Self.maxHistoryTurns * 2)
        for m in recent {
            result.append(AIChatMessage(
                role: m.role == .user ? "user" : "assistant",
                content: m.content))
        }
        return result
    }
    
    private func systemContext() -> String {
        switch origin {
        case .direct:
            return DeepSeekAIService.chatSystemPrompt
        case .care(let care):
            return DeepSeekAIService.chatSystemPrompt + "\n\n" + triggerContext(care)
        case .resume:
            return DeepSeekAIService.chatSystemPrompt
            
        }
    }
    
    /// 触发语境:这次关心的开场白 + 触发时用户的那几篇帖子(内容+情绪)。
    /// 帖子按"创建时间 ≤ 关心创建时间"查最近 3 篇 —— 正是触发那一刻规则看到的窗口。
    private func triggerContext(_ care: PendingCare) -> String {
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
