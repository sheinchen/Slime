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
        // 情绪读不出来就算这次没孵成，不兜 calm：蛋是关怀唯一看的趋势，兜成 calm 等于在那天写了句「挺平静」；
        // 而且蛋一存，EggDebt 就判不欠，这颗错蛋永远不会重孵。抛错 → 不存 → 还欠着 → 下次回前台 / 下次按母鸡再孵
        guard let emotion = SlimeEmotion(aiOutput: parsed.emotion) else { throw AIError.invalidContent }
        return DayEggSummary(text: parsed.text, emotion: emotion)
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
        1. 一句话。这是这一天的封面,不是流水账。
        2. 提炼这一天的"气质",不要罗列发生了什么,更不要逐条复述。但是总结要有帖子的影子
        3. 如果一天里情绪有起伏,写出那个走向(比如从忙乱到安静),不要只说最后一条。
        4. 用旁观的语气,温柔平和,像给这一天写的一句注脚。
        5. 不说教、不给建议、不评价这一天好不好。

        emotion 是这一天的整体情绪,只能从这六个里选一个:happy / calm / sad / angry / anxious / tired。
        不是取最后一条,也不是取最强烈的那条,是这一天合起来的样子。

        示例:
        输入:
        08:30 [happy] 早上买到了想要的面包
        15:40 [tired] 会开了三个小时头很晕
        21:10 [calm] 晚上散步风很舒服
        输出:{"emotion":"calm","text":"咕咕，今天吃了好吃的又忙碌了一天，咕咕..Muji也想和你一起散步咕咕"}
        
        示例 
        输入:
        09:20 [happy] 出门时天气特别好
        13:00 [calm] 午饭后晒了一会儿太阳
        19:30 [happy] 和朋友吃饭聊了很多，笑得停不下来
        输出:{"emotion":"happy","text":"咕咕，好天气！晒太阳！好朋友！Muji也喜欢！"}
        
        示例
        输入:
        08:10 [tired] 昨晚没睡好，睁眼就不想动
        12:30 [happy] 午饭意外地很好吃
        18:50 [tired] 下班时感觉整个人都被掏空了
        22:40 [calm] 洗完澡躺下终于轻松了一点
        输出:{"emotion":"tired","text":"累累的一天，虽然吃到好吃的饭，总归还是很辛苦的一天，洗了澡好好放松一下吧
        :)"}
        
        示例
        输入:
        09:00 [anxious] 一直担心下午的汇报会出错
        15:20 [anxious] 汇报时还是有点结巴
        16:10 [calm] 结束以后发现没有想象中糟糕
        23:00 [calm] 躺在床上听歌，心跳终于慢下来了
        输出:{"emotion":"anxious","text":"咕咕，这一天被悬着的心牵着走了很久，Muji一直相信你可以做到，你看，你完成它啦！Muji也想和你一起听歌"}
        
        示例
        输入:
        10:40 [angry] 合作的人临时改需求，还说之前已经讲过
        14:00 [angry] 越想越觉得委屈
        20:30 [calm] 一个人收拾房间，心情慢慢平复了
        输出:{"emotion":"angry","text":"今天因为工作上的事情受委屈啦T_T，整理好的房间是你可以好好照顾好自己的一隅之地"}
        
        示例
        输入:
        11:20 [sad] 路过以前常去的店，发现已经关门了
        16:00 [calm] 在咖啡馆坐着看了一下午书
        22:10 [sad] 忽然想起一些很久没有联系的人
        输出:{"emotion":"sad","text":"咕咕发现有些事物它只会陪伴我们一段时间，但回想起来也都是构成现在的自己的一部分:)"}
        
        示例
        输入:
        09:30 [tired] 什么都不想做，也不想起床
        17:50 [sad] 觉得自己没有任何用处
        23:40 [sad] 好像消失了也不会有人在意
        输出:{"emotion":"sad","text":"今天好难过，记得要爱自己，伤心也没关系，拍拍自己肩膀，感受自己的心，Muji一直会陪在你身旁"}
        

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
