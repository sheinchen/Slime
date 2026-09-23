//
//  StubAIService.swift
//  Slime
//
//  只在 Debug 构建里存在的 AI 测试替身。
//

#if DEBUG
import Foundation

/// 把 AI 换成**确定性**的假实现，让手动测试可复现。
///
/// 为什么需要它：真调 DeepSeek 时，同一套播种数据跑两次，关怀可能一次说话一次不说。
/// 卡片没出来的时候，你分不清是闸门挡了、落库错了、卡片没露面，还是模型今天抖了 ——
/// **一个每次都在变的被测系统，验不出任何东西。**
///
/// 它不替代 eval：eval 考的就是模型本身的统计表现，那必须真调、必须多次采样。
/// 这里考的是**管道**：闸门放行了吗、决策落库了吗、卡片露面了吗、检索进 prompt 了吗。
/// 两者分工跟测试金字塔一致 —— 确定的部分锁死，不确定的部分测分布。
///
/// **能分协议打桩，是分层白拿的红利。** AI 那几个能力一开始就拆成了窄协议
/// （`CareDeciding` / `DayEggSummarizing` / `AIService` / `RecallIntentExtracting` /
/// `RecallReranking`），每个消费者只认自己那一个，所以组合根可以逐个替换：
/// 测关怀时打桩关怀和孵蛋，检索那两路照常真调。
///
/// ⚠️ **别整套打桩去测检索质量**。`extractRecallIntent` 这一路的桩只会朴素切词，
///    关键词召回会明显掉下来。要看检索准不准，只开 `-StubCare -StubEgg`。
final class StubAIService: AIService,
                           DayEggSummarizing,
                           CareDeciding,
                           RecallIntentExtracting,
                           RecallReranking {

    /// 关怀决策的固定答案。**桩不做推断** —— 一旦它自己看情绪判断该不该说，
    /// 就又有了一个会变的东西，那正是要消灭的。
    enum CareVerdict {
        case say    // 每次都说 —— 验「闸门放行 → 落库 → 卡片滑出」整条路
        case quiet  // 每次都不说 —— 验 AI 的一票否决权有没有被正确落地
    }

    private let careVerdict: CareVerdict
    private let latency: UInt64

    /// - Parameter careVerdict: 传 nil 就看启动参数 `-StubQuiet`，默认 `.say`。
    /// - Parameter latencyMs: 假装的网络耗时。**不要调成 0** ——
    ///   孵蛋动画、发送按钮的 loading 态都靠这段等待才看得见，
    ///   瞬间返回反而会让 UI 的中间状态测不到。
    init(careVerdict: CareVerdict? = nil, latencyMs: UInt64 = 300) {
        self.careVerdict = careVerdict
            ?? (CommandLine.arguments.contains("-StubQuiet") ? .quiet : .say)
        self.latency = latencyMs * 1_000_000
    }

    private func pretendNetwork() async {
        try? await Task.sleep(nanoseconds: latency)
    }

    // MARK: - AIService

    func analyze(content: String) async throws -> AIAnalysis {
        await pretendNetwork()
        return AIAnalysis(emotion: Self.guessEmotion(content), reply: "咕咕~ 我听见啦。（桩）")
    }

    func chat(messages: [AIChatMessage]) async throws -> String {
        await pretendNetwork()
        return Self.reply(to: messages)
    }

    func chatstream(messages: [AIChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await pretendNetwork()
                // 一个字一个字吐，打字机效果和真流式一样能验
                for character in Self.reply(to: messages) {
                    try? await Task.sleep(nanoseconds: 30_000_000)
                    continuation.yield(String(character))
                }
                continuation.finish()
            }
        }
    }

    // MARK: - DayEggSummarizing

    func summarizeDay(_ entries: [SlimeItem]) async throws -> DayEggSummary {
        await pretendNetwork()
        guard !entries.isEmpty else { throw AIError.emptyContent }

        // 把每篇开头几个字串起来。这样删掉一篇再重孵，总结会跟着变 ——
        // 「那件事还在不在蛋里」一眼就能看出来。
        // 真 AI 也该有这个性质，只是它每次措辞都不同，验不了。
        let text = entries.map { String($0.content.prefix(6)) }.joined(separator: "、")
        return DayEggSummary(text: String(text.prefix(24)), emotion: Self.dominant(entries))
    }

    // MARK: - CareDeciding

    func decideCare(window: MoodWindow, recentlySaid: [PastCare]) async throws -> CareDecision {
        await pretendNetwork()

        guard careVerdict == .say else {
            return CareDecision(shouldShow: false,
                                message: "",
                                pattern: "打桩：固定不说",
                                confidence: 0.99,
                                referencedDates: [],
                                safety: .normal,
                                raw: #"{"stub":true,"shouldShow":false}"#)
        }

        // 只引用窗口里真实存在的日期。真实现那边会过滤模型编出来的幻觉日期，
        // 但桩不该靠那层兜底 —— 兜底是用来接住模型的，不是用来接住我们自己的替身的。
        let count = window.eggs.count
        return CareDecision(
            shouldShow: true,
            // 带上看了几天：卡片上一眼就能读出窗口有多大，不用去翻控制台
            message: "咕咕…我一直在这儿呢。（桩·看了 \(count) 天）",
            pattern: "打桩：固定要说",
            confidence: 0.99,
            referencedDates: window.eggs.suffix(3).map(\.date),
            safety: .normal,
            raw: #"{"stub":true,"shouldShow":true,"eggsInWindow":\#(count),"stillShowing":\#(recentlySaid.contains { $0.stillShowing })}"#)
    }

    // MARK: - RecallIntentExtracting

    func extractRecallIntent(message: String,
                             recentTurns: [AIChatMessage]) async throws -> RecallIntent {
        await pretendNetwork()
        // 固定放行。桩不替产品判断该不该翻旧账 —— 那是语义，正是真 AI 的活。
        return RecallIntent(shouldRecall: true,
                            keywords: Self.crudeKeywords(message),
                            emotion: Self.guessEmotion(message),
                            raw: #"{"stub":true,"shouldRecall":true}"#)
    }

    // MARK: - RecallReranking

    func rerank(message: String,
                recentTurns: [AIChatMessage],
                candidates: [RecallHit]) async throws -> RecallSelection {
        await pretendNetwork()
        // 直接取融合后的前 3 条 —— **这正是真实现被明令禁止的降级行为**。
        // 线上重排失败必须 fail closed（宁可不提），否则一出故障就变成「为了回忆而回忆」。
        // 桩可以这么干，是因为它的任务是把候选送到下游、验证注入链路通不通，
        // 不是替产品判断该不该提。
        return RecallSelection(selectedDocumentIDs: candidates.prefix(3).map(\.document.id),
                               reason: "打桩：取融合前 3")
    }

    // MARK: - 确定性的小规则
    //
    // 下面几个都是「同样输入必定同样输出」的纯函数。
    // 桩里允许出现 emotion，跟闸门那条红线不冲突 ——
    // 红线管的是**产品逻辑**不许用数数代替语义判断，这里是替身在模仿模型的输出。

    /// 关键词撞情绪。顺序有讲究：`tired` 要排在 `happy` 前面，
    /// 不然「今天好累」会先撞上 happy 那一组。
    private static let emotionHints: [(SlimeEmotion, [String])] = [
        (.tired,   ["累", "困", "疲", "没劲", "撑不住", "熬"]),
        (.angry,   ["气", "烦", "火大", "凭什么", "忍"]),
        (.anxious, ["焦虑", "担心", "怕", "紧张", "来不及", "deadline", "睡不着"]),
        (.sad,     ["难过", "哭", "失落", "空落", "委屈", "想哭"]),
        (.happy,   ["开心", "高兴", "好玩", "笑", "过了", "终于", "太好了"]),
    ]

    static func guessEmotion(_ text: String) -> SlimeEmotion {
        for (emotion, hints) in emotionHints where hints.contains(where: { text.contains($0) }) {
            return emotion
        }
        return .calm
    }

    /// 当天出现最多的情绪；平票时取最后一篇的 —— 一天怎么收尾更能代表这天。
    private static func dominant(_ entries: [SlimeItem]) -> SlimeEmotion {
        var counts: [SlimeEmotion: Int] = [:]
        for entry in entries { counts[entry.emotion, default: 0] += 1 }
        guard let top = counts.values.max() else { return .calm }
        if let last = entries.last, counts[last.emotion] == top { return last.emotion }
        return counts.first { $0.value == top }?.key ?? .calm
    }

    private static let separators = CharacterSet(charactersIn: "，。！？、；：,.!?;: \n\r“”\"'…—（）()")

    /// 朴素切词：按标点切段，太长的段落只取两头。
    ///
    /// **它比真 AI 差得明显**，而且差在要害上：关键词那一路是 `text.contains(词)` 的子串匹配，
    /// 真实现会把「组长」扩成「组长/领导/上司」，桩不会 —— 所以写「领导」的那些日记全漏。
    /// 这是刻意留着的短板，提醒你测检索质量时别开这一路的桩。
    static func crudeKeywords(_ message: String) -> [String] {
        var result: [String] = []
        for piece in message.components(separatedBy: separators)
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .filter({ $0.count >= 2 }) {
            if piece.count <= 6 {
                result.append(piece)
            } else {
                result.append(String(piece.prefix(4)))
                result.append(String(piece.suffix(4)))
            }
        }
        return Array(result.prefix(6))
    }

    /// 注入检索结果时 `ChatViewModel.memoryContext` 用的段落标题。
    /// 桩靠它认出「旧事到底有没有进到 prompt 里」。
    private static let memoryMarker = "【你想起来的事"

    private static func reply(to messages: [AIChatMessage]) -> String {
        let system = messages.first { $0.role == "system" }?.content ?? ""
        guard let marker = system.range(of: memoryMarker) else {
            return "咕咕~ 我在听呢。（桩）"
        }
        // 控制台那段 🔎 打印看的是「检索层交出了什么」，这里看的是「它真的进 prompt 了」——
        // 两者中间还隔着一次 systemContext() 拼装，那一步也可能出错。
        let injected = system[marker.lowerBound...]
            .split(separator: "\n")
            .filter { $0.hasPrefix("- ") }
            .prefix(3)
            .joined(separator: " / ")
        return "咕咕~（桩）我想起来了：\(injected)"
    }
}
#endif
