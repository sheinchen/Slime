//
//  DayEggSummarizer.swift
//  Slime
//

import Foundation

/// 把一天的几篇日记收成一颗蛋：一句话 + 这一天整体的情绪。
///
/// **不加总时限**（09-24 定，跟写日记相反），用默认的空闲超时：孵蛋不锁人，等的时候可以随便切走；
/// DeepSeek 拥堵时请求其实还活着在排队，等下去有机会孵出来，加时限只会「按一次失败一次」。
final class DayEggSummarizer: DayEggSummarizing {

    private let client: AIClient

    init(client: AIClient) {
        self.client = client
    }

    func summarizeDay(_ entries: [SlimeItem]) async throws -> DayEggSummary {
        guard !entries.isEmpty else { throw AIError.emptyContent }
        let (parsed, _) = try await client.requestJSON(
            DayEggDTO.self,
            messages: [.init(role: "system", content: Self.prompt),
                       .init(role: "user", content: Self.transcript(entries))],
            temperature: 0.8)
        return DayEggSummary(text: parsed.text, emotion: SlimeEmotion(rawValue: parsed.emotion) ?? .calm)
    }

    /// 把一天的几篇日记排成给模型看的样子:时间 + 情绪 + 原文。
    /// 没被 AI 读过的那篇不带情绪标签 —— 宁可少一条参考，也不编一个。
    /// 蛋的情绪本来就是这次总结读完原文自己判的，标签只是参考。
    private static func transcript(_ entries: [SlimeItem]) -> String {
        entries.map { entry in
            let tag = entry.emotion.map { "[\($0.rawValue)] " } ?? ""
            return "\(timeFormatter.string(from: entry.createdAt)) \(tag)\(entry.content)"
        }.joined(separator: "\n")
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    // MARK: - prompt 与返回结构

    private static let prompt = HenPersona.text + """
        你的任务:读用户这一整天写的几篇碎碎念,把这一天收成一句话,并判断这一天整体的情绪。

        text 的要求:
        1. 一句话,不超过 25 个字。这是这一天的封面,不是流水账。
        2. 提炼这一天的"气质",不要罗列发生了什么,更不要逐条复述。但是总结要有帖子的影子
        3. 如果一天里情绪有起伏,写出那个走向(比如从忙乱到安静),不要只说最后一条。
        4. 用旁观的语气,温柔平和,像给这一天写的一句注脚。不要出现"你",不要对用户说话。
        5. 不说教、不给建议、不评价这一天好不好。

        emotion 是这一天的整体情绪,只能从这六个里选一个:happy / calm / sad / angry / anxious / tired。
        不是取最后一条,也不是取最强烈的那条,是这一天合起来的样子。

        示例:
        输入:
        08:30 [happy] 早上买到了想要的面包
        15:40 [tired] 会开了三个小时头很晕
        21:10 [calm] 晚上散步风很舒服
        输出:{"emotion":"calm","text":"咕咕，今天吃了好吃的又忙碌了一天，好想你，咕咕..我也想和你一起散步咕咕"}

        安全底线(优先级高于一切):如果这一天的内容里有严重低落、绝望或自我伤害的倾向,
        text 要真诚温和,不要把它轻盈化处理,emotion 如实标注。

        严格要求:只返回一个 JSON 对象,包含 emotion 和 text 两个字段,
        不要任何多余文字,不要用 markdown 代码块包裹。
        """

    private struct DayEggDTO: Decodable {
        let emotion: String
        let text: String
    }
}
