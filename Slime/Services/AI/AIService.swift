//
//  AIService.swift
//  Slime
//
//  Created by shiying on 2026/7/15.
//
//  AI 能力的**接口**（协议）和几样共用的小类型。实现全在同目录下，一个能力一个文件，
//  各自带着自己的 prompt 和返回结构，发请求一律走 `AIClient`：
//
//    AIService              → HenChatService         写完日记回一句 + 聊天
//    DayEggSummarizing      → DayEggSummarizer       一天收成一颗蛋
//    CareDeciding           → CareDecider            主动关怀：说不说、说什么
//    RecallIntentExtracting → RecallIntentExtractor  聊天检索前提炼检索词
//    RecallReranking        → MemoryReranker         检索候选精排（协议在 Recall/RecallReranker.swift）
//
//  每个消费者只认自己那一个窄协议，所以组合根能逐个换成桩（StubAIService），见 SceneDelegate。
//  以前这五样全在一个 700 多行的 DeepSeekAIService 里，09-25 拆开。
//

import Foundation

//MARK: - AI消息
struct AIChatMessage {
    let role:String
    let content: String
}
//MARK: - 错误类型
enum AIError: Error {
    case badStatus
    case emptyContent
}

protocol AIService {
    func analyze(content: String) async throws -> AIAnalysis
    //多轮聊天，组装上下文，返回回复
    func chat(messages: [AIChatMessage]) async throws -> String
    //流式聊天
    func chatstream(messages: [AIChatMessage]) -> AsyncThrowingStream<String, Error>
    
    
}

//总结一天
protocol DayEggSummarizing {
    func summarizeDay(_ entries: [SlimeItem]) async throws -> DayEggSummary
}

protocol CareDeciding {
    /// - Parameters:
    ///   - window: 近 14 天情绪时间线（一天一颗蛋，已按日期升序）
    ///   - recentlySaid: 最近说过的关怀，交给 AI 自己避免重复
    func decideCare(window: MoodWindow, recentlySaid: [PastCare]) async throws -> CareDecision
}

/// 聊天时把用户那句话提炼成检索意图:要不要翻旧日记、用什么词翻。
protocol RecallIntentExtracting {
    /// - Parameters:
    ///   - message: 用户刚发的那句话
    ///   - recentTurns: 最近几轮对话，只用来消解指代（「那件事」指的是哪件）
    func extractRecallIntent(message: String,
                             recentTurns: [AIChatMessage]) async throws -> RecallIntent
}
