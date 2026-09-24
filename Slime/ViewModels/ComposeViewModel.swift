//
//  ComposeViewModel.swift
//  Slime
//
//  Created by shiying on 2026/7/6.
//

import Foundation

final class ComposeViewModel {



    //依赖协议，可以测试
    private let repository: PostRepository
    private let aiService: AIService

    init(repository: PostRepository = CoreDataPostRepository(),
         aiService: AIService = DeepSeekAIService(),
        ) {
        self.repository = repository
        self.aiService = aiService
    }



    /// 记一篇。**先存后分析** —— 日记在问 AI 之前就落库了，AI 只是给它补上情绪和母鸡的回复。
    ///
    /// 为什么先存：日记是用户的，回复是母鸡的。以前两件事绑在一起（切片 6「失败不存帖」），
    /// AI 不在 —— 没网、超时、DeepSeek 拥堵、余额不足 —— 日记就写不进去；
    /// 等待中 App 被杀，字也跟着没了。那条规则当初是对的：一篇日记就是一只按情绪画的史莱姆，
    /// 没情绪画不出来。改成一天一颗蛋之后，卡片只画时间和正文，前提已经不在了。
    ///
    /// - Returns: 母鸡这次说的话。AI 读上了是它的回复；没读上是一句本地的「收好了」，
    ///   这篇照样存好了，只是先不带情绪。**不抛错** —— 日记能不能写，不再取决于 AI 在不在。
    func generate(content: String) async -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // ① 先存。从这一刻起日记就在了。
        //    只留 id —— 下面要隔一次网络等待，别拿着托管对象跨过 await
        let id = repository.create(content: trimmed).id

        // ② 再问 AI。只是补情绪和回复，问不上不影响日记本身
        do {
            let analysis = try await aiService.analyze(content: trimmed)
            repository.saveAnalysis(id: id, emotion: analysis.emotion, reply: analysis.reply)
            return analysis.reply
        } catch {
            // 不伪造：情绪留空（不兜成 calm），回复也不存 ——
            // 本地那句只是「收到了」，不是她读完的回应，存进 reply 就成了冒充。
            print("这篇 AI 没读上，日记已先存下: \(error)")
            return HenUnread.random()
        }
    }
}

