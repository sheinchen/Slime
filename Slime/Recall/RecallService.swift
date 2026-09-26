//
//  RecallService.swift
//  Slime
//

import Foundation

/// 聊天时的检索编排：提炼 → 取候选 → 编码 → 融合 → 重排。
///
/// 跨了仓库、网络和本地模型，所以放 Services/，跟 `DayEggService` 同一层。
/// 它**自己不做任何判断** —— 判断分别在 `RecallGate`（算术）、
/// `extractRecallIntent`（语义）、`RecallRule`（融合）、
/// `RecallReranking`（精排与否决）里，这层只负责把它们串起来。
@MainActor
final class RecallService {

    private let posts: PostRepository
    private let embedder: TextEmbedder
    private let ai: RecallIntentExtracting
    private let reranker: RecallReranking
    private let calendar: Calendar

    /// 候选窗口。时间只在这儿用一次，**它是候选范围，不是排序权重**。
    /// 一旦让时间参与打分，久远那件真正相关的事就永远排不上来，
    /// 整套检索会退化成「最近 N 天」。
    private static let windowDays = 365

    /// 召回层要「宽」，先给重排 10 条；重排要「严」，最后只能交出 0...3 条。
    private static let candidateLimit = 10
    private static let finalLimit = 3

    init(posts: PostRepository,
         embedder: TextEmbedder,
         ai: RecallIntentExtracting,
         reranker: RecallReranking,
         calendar: Calendar = .current) {
        self.posts = posts
        self.embedder = embedder
        self.ai = ai
        self.reranker = reranker
        self.calendar = calendar
    }

    /// 返回空数组 = 这次不提。
    ///
    /// - Parameter recentTurns: 最近几轮对话，**不含 system**。
    ///   提炼是工具调用，把母鸡的人设混进去它会开始咕咕，然后把 JSON 写歪。
    ///   同时这几轮也是 AI 判断「我刚才是不是已经翻过旧账」的唯一依据。
    func recall(message: String, recentTurns: [AIChatMessage]) async -> [RecallHit] {

        // ① AI 提炼检索词。它在这里有第一次否决权。
        guard let intent = try? await ai.extractRecallIntent(message: message,
                                                            recentTurns: recentTurns),
              intent.shouldRecall else { return [] }

        // ② 取候选：一年内的日记，连同已经补算好的向量
        let since = calendar.date(byAdding: .day, value: -Self.windowDays, to: Date()) ?? Date()
        let candidates = posts.recallCandidates(since: since)
        guard !candidates.isEmpty else { return [] }

        // ③ 编码这句话。放后台 —— 27 毫秒不长，但它正卡在用户按下发送那一刻。
        let embedder = self.embedder
        let queryVector = await Task.detached(priority: .userInitiated) {
            try? embedder.embedQuery(message)
        }.value

        var similarities: [UUID: Double] = [:]
        if let queryVector {
            for candidate in candidates {
                // 还没轮到补算的日记跳过。这不是错，它下次进前台就有向量了。
                guard let vector = candidate.vector else { continue }
                similarities[candidate.document.id] = dot(queryVector, vector)
            }
        }

        // ④ 宽召回：每路先截断，RRF 交出 10 条候选。
        let candidateHits = RecallRule.rank(documents: candidates.map(\.document),
                                            query: intent.query,
                                            similarities: similarities,
                                            limit: Self.candidateLimit,
                                            channelLimit: Self.candidateLimit)
        guard !candidateHits.isEmpty else { return [] }

        // ⑤ 严重排：可以一条都不选。任何网络/JSON 失败都 fail closed，
        // 不能退回 candidateHits.prefix(3)，否则故障时又会变成「为了回忆而回忆」。
        let outcome = await RecallRerankCoordinator.select(message: message,
                                                           recentTurns: recentTurns,
                                                           candidates: candidateHits,
                                                           using: reranker,
                                                           limit: Self.finalLimit)

        #if DEBUG
        if let error = outcome.errorDescription {
            print("[Recall] 重排失败，本轮不提旧事: \(error)")
        } else {
            print("[Recall] 重排: \(candidateHits.count) 条候选 → \(outcome.hits.count) 条; \(outcome.reason)")
        }
        #endif

        return outcome.hits
    }

    /// 向量在模型里已经做过 L2 归一化，点积就是余弦相似度。
    /// 几百条日记跑这个循环是毫秒级；等哪天上千条觉得卡了，
    /// 换 Accelerate 的 `vDSP_dotpr`，那是给这种活写的。
    private func dot(_ a: [Float], _ b: [Float]) -> Double {
        var sum: Float = 0
        for i in 0..<min(a.count, b.count) { sum += a[i] * b[i] }
        return Double(sum)
    }
}
