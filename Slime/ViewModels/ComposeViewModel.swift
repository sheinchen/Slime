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

    /// 依赖必填，不给默认值（09-25 去掉的）。
    /// 以前 `aiService` 默认直连真 AI —— 随手 `ComposeViewModel()` 就绕过了组合根的打桩开关，
    /// 开着 `-StubAI` 也照样打真 API、花真钱。
    init(repository: PostRepository, aiService: AIService) {
        self.repository = repository
        self.aiService = aiService
    }



    /// 记一篇，分两步：**先存后分析** —— 日记在问 AI 之前就落库了，AI 只是给它补上情绪和母鸡的回复。
    ///
    /// 为什么先存：日记是用户的，回复是母鸡的。以前两件事绑在一起（切片 6「失败不存帖」），
    /// AI 不在 —— 没网、超时、DeepSeek 拥堵、余额不足 —— 日记就写不进去；
    /// 等待中 App 被杀，字也跟着没了。那条规则当初是对的：一篇日记就是一只按情绪画的史莱姆，
    /// 没情绪画不出来。改成一天一颗蛋之后，卡片只画时间和正文，前提已经不在了。
    ///
    /// 为什么拆成两个方法（10-02）：存是会失败的（手机存储满了），以前 `create` 失败只 print，
    /// 页面照样让母鸡上台说「收好了」—— 字其实只在内存里，App 一被杀就没了。
    /// 拆开之后页面先 `save`，存不上就停在输入页、字留在框里；存上了才让母鸡上台、再 `reply`。
    ///
    /// ① 先存。**同步、会抛错**：没有 `async` 就是契约本身 —— 这一步不许等网络，点下「收好」那一刻日记就该在库里了
    /// - Returns: 存下的那篇（内容已经去掉首尾空白），交给 `reply(to:)`
    func save(content: String) throws -> SlimeItem {
        try repository.create(content: content.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// ② 再问 AI。只是给已经存好的那篇补情绪和回复，问不上不影响日记本身
    ///
    /// - Returns: 母鸡这次说的话。AI 读上了是它的回复；没读上是一句本地的「收好了」，
    ///   这篇照样存好了，只是先不带情绪。**不抛错** —— 日记能不能写，不取决于 AI 在不在。
    func reply(to entry: SlimeItem) async -> String {
        do {
            let analysis = try await aiService.analyze(content: entry.content)
            // 按 id 补：仓库会重新查（隔着一次网络等待，那篇可能已经被删了）
            repository.saveAnalysis(id: entry.id, emotion: analysis.emotion, reply: analysis.reply)
            return analysis.reply
        } catch {
            // 不伪造：情绪留空（不兜成 calm），回复也不存 ——
            // 本地那句只是「收到了」，不是她读完的回应，存进 reply 就成了冒充。
            print("这篇 AI 没读上，日记已先存下: \(error)")
            return HenUnread.random()
        }
    }
}

