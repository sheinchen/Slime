//
//  HenChatService.swift
//  Slime
//

import Foundation

/// 母鸡直接对用户开口的两处：写完日记回一句（`analyze`）和聊天（`chat` / `chatstream`）。
/// 两处归启动参数 `-StubChat` 一个开关管，所以是同一个协议、同一个实现。
///
/// 聊天的 system prompt 不在这里 —— 聊天上下文是 `ChatViewModel` 拼的，这里只管发出去、流回来。见 `ChatPrompt`。
final class HenChatService: AIService {

    private let client: AIClient

    init(client: AIClient) {
        self.client = client
    }

    // MARK: - 写完日记回一句

    /// 写日记那一下的时限：**8 秒总时限**。正常 2~5 秒回。
    ///
    /// 用户正对着母鸡等，**等待中页面关不掉**（不给取消，见 `ComposeViewController.closeTapped`），
    /// 所以这个时限就是出口，必须是**总时限**、而且要短。空闲超时在 DeepSeek 拥堵时永远等不到。
    ///
    /// **到点不算失败**：日记在问 AI 之前就存好了（先存后分析），到点只是这篇先不带情绪、
    /// 母鸡说一句本地的「收好了」。所以敢设短 —— 误伤一次的代价只是少一句 AI 回复。
    ///
    /// 只给 analyze 用。关怀、补蛋、检索失败的代价各不一样，时限要分别想，别顺手套用。
    private static let analyzePatience = AIClient.Patience.total(8)

    func analyze(content: String) async throws -> AIAnalysis {
        let (parsed, _) = try await client.requestJSON(
            EmotionReplyDTO.self,
            messages: [.init(role: "system", content: Self.analyzePrompt),
                       .init(role: "user", content: content)],
            temperature: 0.7,
            patience: Self.analyzePatience)
        // 情绪读不出来就留 nil，不兜 calm，也不抛错 —— 回复那句是好的，不该为一个字段扔掉整句
        let emotion = SlimeEmotion(aiOutput: parsed.emotion)
        return AIAnalysis(emotion: emotion, reply: parsed.reply)
    }

    // MARK: - 聊天

    /// 多轮聊天，一次性返回。`messages` 由调用方拼好（含 system）。
    func chat(messages: [AIChatMessage]) async throws -> String {
        let raw = try await client.requestText(messages: messages, temperature: 1.0)
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AIError.emptyContent }
        return text
    }

    /// 流式聊天。`messages` 由调用方拼好（含 system）。
    func chatstream(messages: [AIChatMessage]) -> AsyncThrowingStream<String, Error> {
        client.streamText(messages: messages, temperature: 1.0)
    }

    // MARK: - prompt 与返回结构

    /// 写完日记那一句的 prompt。（以前叫 `systemPrompt`，跟聊天的分不清，改了个看得出用途的名字）
    private static let analyzePrompt = HenPersona.text + """
        你的任务:读用户这句碎碎念,判断情绪,并以内在自我的身份回一句暖心话。reply 只回一句,简短。
        情绪 emotion 只能从这六个里选一个:happy / calm / sad / angry / anxious / tired。

        示例:
        用户:今天上班好累啊什么都不想干 → {"emotion":"tired","reply":"累累的一天辛苦啦,来来来靠在Muji身上吧"}
        用户:我今天吃到了超好吃的蛋糕! → {"emotion":"happy","reply":"哇是甜甜的一天!Muji也好想尝一口呀~"}
        用户:考试没考好有点难过 → {"emotion":"sad","reply":"没关系没关系，下次再加油啦，Muji帮你保佑保佑"}
        用户:明天要交东西还没做完好慌 → {"emotion":"anxious","reply":"别急别急,一件一件慢慢来,Muji陪着你~"}
        用户:今天什么事都没有,挺平静的 → {"emotion":"calm","reply":"平平淡淡也很好呀,这样的一天Muji很喜欢~"}
        用户:排队被人插队气死我了 → {"emotion":"angry","reply":"气鼓鼓的!换是Muji也会生气的,摸摸你~"}

        安全底线(优先级高于软萌风格):如果用户表达出严重低落、绝望或自我伤害的倾向,不要用可爱语气,要真诚、温柔地回应,并温柔地建议 ta 找信任的人或专业帮助聊一聊。

        严格要求:只返回一个 JSON 对象,包含 emotion 和 reply 两个字段,不要任何多余文字,不要用 markdown 代码块包裹。
        """

    private struct EmotionReplyDTO: Decodable {
        let emotion: String
        let reply: String
    }
}
