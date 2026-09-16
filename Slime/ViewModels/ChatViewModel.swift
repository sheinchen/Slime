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

    /// 可选：向量模型加载失败时它是 nil，聊天照常，只是母鸡不会提起旧事。
    private let recall: RecallService?

    private var session: ChatSessionInfo?
    private(set) var messages: [ChatMessageItem] = []

    /// 这一轮检索到的旧事。每次 send 重算，只喂给紧接着的那一次回复。
    /// retry 时故意不重算 —— 重试的是同一句话，该看到同样的上下文。
    private var recalled: [RecallHit] = []

    //上下文先带N轮
    private static let maxHistoryTurns = 10

    /// 给提炼用的历史带几条。它比正式聊天的窗口短得多 ——
    /// 提炼只需要消解指代、外加看出自己刚才有没有翻过旧账。
    private static let turnsForRecall = 8
    
    //正在流的部分回复
    private(set) var streamingText: String?
    
    init(origin: ChatOrigin,
         chatRepo: ChatRepository,
         posts: PostRepository,
         aiService: AIService,
         recall: RecallService? = nil) {
        self.origin = origin
        self.chatRepo = chatRepo
        self.posts = posts
        self.aiService = aiService
        self.recall = recall
        
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

        // 检索放在开流之前:母鸡得先「想起来」,才能在这次回复里提。
        // 代价是首字慢一点(多一次提炼调用 + 一次本地编码)。
        await tryRecall(trimmed)

        return try await streamReply(sessionId: s.id, onDelta: onDelta)
    }
    
    func retry(onDelta: @MainActor @escaping () -> Void) async throws -> ChatMessageItem {
        guard let session else { throw AIError.emptyContent }
        return try await streamReply(sessionId: session.id, onDelta: onDelta)
    }
    
    //MARK: - 检索旧事

    /// 去翻一次旧日记。翻不到、被闸门挡下、或者 AI 判不值得,都只是 `recalled` 保持空,
    /// **不抛错** —— 提不起旧事不该让整次对话失败。
    private func tryRecall(_ message: String) async {
        recalled = []
        guard let recall else {
            #if DEBUG
            print("🔎 聊天检索:没有 RecallService(向量模型没加载起来)")
            #endif
            return
        }

        let gatePassed = RecallGate.shouldTry(message: message)
        if gatePassed {
            recalled = await recall.recall(message: message, recentTurns: recentTurnsForRecall())
        }

        #if DEBUG
        print("""

        ========== 🔎 聊天检索 ==========
        这句话: \(message)
        闸门: \(gatePassed ? "过" : "挡下(不足 \(RecallGate.minLength) 字)")
        捞到: \(recalled.isEmpty ? "没有(AI 判不值得,或候选里没有沾边的)" : "\(recalled.count) 条")
        \(recalled.map { "  · [\(ChineseDate.vague($0.document.date))] \($0.document.text.prefix(30))" }
                  .joined(separator: "\n"))
        ================================

        """)
        #endif
    }

    /// 给提炼用的对话历史。**不含 system** —— 提炼是内部工具调用,
    /// 把母鸡的人设混进去,它会开始咕咕,然后把 JSON 写歪。
    private func recentTurnsForRecall() -> [AIChatMessage] {
        messages.suffix(Self.turnsForRecall).map {
            AIChatMessage(role: $0.role == .user ? "user" : "assistant", content: $0.content)
        }
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
        var parts = [DeepSeekAIService.chatSystemPrompt]
        if case .care(let care) = origin { parts.append(triggerContext(care)) }
        if !recalled.isEmpty { parts.append(memoryContext(recalled)) }
        return parts.joined(separator: "\n\n")
    }

    /// 把检索到的旧日记摆给母鸡看。
    ///
    /// **铁律跟关怀那边一样:绝不暴露判断依据。**
    /// 不能让它说「你在三月十二号写过」,那像在查档案,不像朋友。
    /// 所以这里给的时间是模糊的 —— 日期根本没传进去,它想说也说不出口。
    ///
    /// 这是 AI 的**第二次否决权**:检索捞上来了,它仍然可以选择不提。
    private func memoryContext(_ hits: [RecallHit]) -> String {
        let lines = hits.map {
            "- \(ChineseDate.vague($0.document.date)):\($0.document.text.prefix(60))"
        }.joined(separator: "\n")

        return """
               [你想起来的事,只有你自己知道,绝不原样复述]
               \(lines)

               这些是 ta 以前写下的。**贴得上就优先用它来回应。**
               比起「那种感觉真的很磨人吧」这种谁都能说的话,
               一句「是不是又像上次那样」更能让 ta 觉得被记住了 ——
               你手上有具体的事,就别拿泛泛的共情糊弄过去。

               贴不上才当没看见,硬扯比不提更伤人。
               绝不要说出日期,也不要说「你写过」「我看到」「记录里」这类话,
               那像在查档案,不像朋友。
               """
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
