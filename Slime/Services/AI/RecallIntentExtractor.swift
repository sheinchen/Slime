//
//  RecallIntentExtractor.swift
//  Slime
//

import Foundation

/// 聊天检索的第一步：把用户那句话提炼成检索意图 —— 要不要翻旧日记、用哪些词翻。
/// 它在检索里有第一次否决权（`shouldRecall: false`）。
final class RecallIntentExtractor: RecallIntentExtracting {

    private let client: AIClient

    init(client: AIClient) {
        self.client = client
    }

    func extractRecallIntent(message: String,
                             recentTurns: [AIChatMessage]) async throws -> RecallIntent {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .skip }

        // 带最近四轮。够消解「那件事」这类指代，也够它看出
        // 自己前几轮是不是已经翻过一次旧账了 —— 那个判断没有别的依据，
        // 就靠这几条历史。再多的话模型会去提炼整段对话的主题，而不是这一句。
        var messages: [AIChatMessage] = [.init(role: "system", content: Self.prompt)]
        messages += recentTurns.suffix(8)
        messages.append(.init(role: "user", content: trimmed))

        let (parsed, raw) = try await client.requestJSON(
            RecallIntentDTO.self,
            messages: messages,
            temperature: 0.2)   // 提炼要的是稳定，不是创意

        // 去空、去重、掐上限。模型偶尔把同一个词给两遍，
        // 而重复的词在关键词那一路会被算成两次命中，凭空拔高那篇日记的排名。
        var seen = Set<String>()
        let keywords = (parsed.keywords ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .prefix(8)

        return RecallIntent(shouldRecall: parsed.shouldRecall && !keywords.isEmpty,
                            keywords: Array(keywords),
                            emotion: parsed.emotion.flatMap { SlimeEmotion(rawValue: $0) },
                            raw: raw)
    }

    // MARK: - prompt 与返回结构

    ///
    /// ⚠️ 这段是**产品判断**，不是代码。
    /// keywords 给得宽，捞回来的噪声就多;给得窄，换个说法就漏。
    /// 改之前先跑 `RecallIntentEvalTests` 看 recall 往哪边动。
    ///
    /// 注意它**不带 persona** —— 这是内部工具调用，不是母鸡在说话。
    /// 掺进人设只会让它开始咕咕，然后把 JSON 写歪。
    private static let prompt = """
        你在为一个中文日记 App 做检索前的意图提炼。用户刚对母鸡说了一句话，
        你要判断值不值得去翻他过去写的日记，如果值得，用哪些词去翻。

        只输出 JSON：
        {"shouldRecall": true, "keywords": ["..."], "emotion": "tired"}

        shouldRecall 怎么判
        - 他在讲一件具体的事、一个具体的人、或者一种具体的感受 → true
        - 纯寒暄（「在吗」「哈喽」）、对上一句的简单回应（「嗯」「是的」「好呀」）、
          在问母鸡自己的事 → false
        - 看一眼上面的对话:如果你最近几轮已经提起过 ta 以前的事,这次就克制,给 false。
          除非 ta 自己在追问过去(「上次那个」「你还记得吗」「就是那件事」),
          或者 ta 现在说的明显是另一件不相干的事。连着翻旧账,像在表演记忆力。
        - 拿不准时倾向 true。捞回来用不用,是下一步的事。

        keywords 怎么给
        - 抽出这句话里的人、物、事，以及描述感受的词。
        - **每个词都要扩成同义说法**，这条最重要：
          组长 → 组长 领导 上司；累 → 累 疲惫 没劲；吵架 → 吵架 争执 闹掰
        - 日记是**逐字匹配**的，所以只给短词，两三个字最好。
          不要给「被组长批评」这种短语，它一个字都匹配不上。
        - 3 到 8 个词，宁少勿滥 —— 词越多，捞回来的噪声越多。
        - 不要给「今天」「最近」「事情」「感觉」这类到处都是的词。

        emotion 是用户**此刻**的情绪，不是他正在回忆的往事的情绪。
        只能从这六个里选一个：happy calm sad angry anxious tired
        """

    private struct RecallIntentDTO: Decodable {
        let shouldRecall: Bool
        let keywords: [String]?
        let emotion: String?
    }
}
