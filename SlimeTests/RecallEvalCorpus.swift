//
//  RecallEvalCorpus.swift
//  SlimeTests
//
//  检索的 golden set —— 一个虚构用户半年的日记 + 4 条查询的人工标注。
//
//  ⚠️ 和 CareEvalCases 一样，这个文件是**产品判断**，不是代码。
//     relevantDaysAgo 那一列定义了「什么叫相关」。标注一旦不自洽，
//     分数就会跟着摇摆，而你会以为是算法坏了 —— 关怀那边已经踩过三次。
//     改这里之前，先把同类 case 并排比一遍。
//
//  和关怀 eval 的一个重要区别：**这套 eval 不调 API**。
//  被测的是纯算术，跑一轮是毫秒级，可以随便迭代参数。
//

import Foundation
@testable import Slime

nonisolated struct RecallEvalCase {
    let id: Int
    let name: String

    /// 已经提炼过的检索词。真实链路里由 AI 从用户那句话里抽，
    /// 这里手工给 —— 这样测的是检索本身，不掺 AI 的方差。
    let keywords: [String]

    /// 用户此刻的情绪。
    let emotion: SlimeEmotion?

    /// 标注为相关的日记是几天前写的。
    let relevantDaysAgo: Set<Int>

    /// 这条 case 是用来考什么的。**必须写** ——
    /// 分数动了之后，要回来看的就是这一列。
    let rationale: String

    var query: RecallQuery {
        RecallQuery(keywords: keywords, emotion: emotion)
    }
}

nonisolated enum RecallEvalCorpus {

    /// 虚构语料。daysAgo: 1 = 昨天。
    ///
    /// 造这批数据时刻意埋了三种东西，缺一样 eval 就测不出差异：
    ///  ① 换词 —— 组长 / 领导 / 上司 是同一个人；累 / 抽干 / 没劲 是同一种感觉
    ///  ② 干扰 —— 「妈妈寄的橘子」和「很像橘子的野猫」都会被关键词命中，但都不是那只猫
    ///  ③ 久远 —— 真正相关的事有的在半年前。近因一旦参与排名，它们永远上不来
    static let entries: [(daysAgo: Int, emotion: SlimeEmotion, text: String)] = [

        // ── 工作线：同一个人，三种叫法，外加一条一个实体词都没有的 ──
        (175, .angry,   "组长当着所有人说我那版方案没想清楚，脸都烧了"),
        (170, .anxious, "开题答辩定在下个月，到现在什么都没准备"),
        (165, .tired,   "查了一整天文献，脑子像被抽干一样"),
        (160, .anxious, "明天要跟组长过一遍进度，昨晚翻来覆去没睡好"),
        (155, .calm,    "楼下新开了家面包店，买了个可颂"),
        (150, .happy,   "橘子今天会自己跳上窗台了，蹲那儿看了半小时"),
        (140, .angry,   "室友又没洗碗，第三次了，忍着没说出口"),
        (135, .happy,   "周末去看了个展，人不多，很舒服"),
        (130, .happy,   "答辩过了，走出来那一刻腿都是软的"),
        (120, .tired,   "领导让我把季度总结推翻重写，写到十点多"),
        (115, .calm,    "把阳台整个收拾了一遍"),
        (110, .tired,   "什么都不想干，在床上躺了一下午"),
        (100, .anxious, "跟室友说了洗碗的事，气氛僵了一晚上"),

        // ── 强干扰：字面有「橘子」，说的是水果 ──
        (95,  .happy,   "妈妈寄了一箱橘子过来，很甜"),

        (90,  .sad,     "橘子这两天不太吃东西，带去医院抽了血"),
        (88,  .anxious, "医生说橘子肾指标偏高，以后要控制饮食"),
        (75,  .tired,   "连续加班第五天，走路都在飘"),
        (70,  .calm,    "换了新床单，被子晒得暖暖的"),
        (60,  .calm,    "室友主动买了洗洁精回来，好像算和好了"),
        (50,  .happy,   "跟朋友吃了顿火锅，聊到很晚"),
        (45,  .tired,   "睡了快十个小时，还是一点劲都没有"),
        (40,  .angry,   "上司在群里@我说交付太慢，可需求一直在改啊"),
        (30,  .calm,    "橘子最近乖了很多，晚上会趴在我脚边睡"),
        (25,  .calm,    "下雨，在家看完一部电影"),

        // ── 中等干扰：字面有「橘子」，说的是别的猫 ──
        (20,  .happy,   "路上碰到一只很像橘子的野猫，蹲下喂了会儿"),

        (15,  .happy,   "买了双想很久的鞋"),
        (12,  .sad,     "开会的时候被说了几句，回来一整天提不起劲"),
        (8,   .tired,   "又是浑身没力气的一天"),
        (5,   .calm,    "今天挺普通的，没什么特别的事"),
    ]

    static let cases: [RecallEvalCase] = [

        RecallEvalCase(
            id: 1,
            name: "今天又被组长说了",
            keywords: ["组长", "批评"],
            emotion: .angry,
            relevantDaysAgo: [175, 160, 120, 40, 12],
            rationale: """
                考换词。175 和 160 字面有「组长」，关键词那一路能拿到；
                120 写的是「领导」、40 写的是「上司」、12 连实体词都没有，
                只剩「被说了」这个语境。所以关键词的 recall 上限是 2/5 ——
                这条 case 就是用来标出那条天花板的，向量接上之后它该往上走。
                """),

        RecallEvalCase(
            id: 2,
            name: "橘子今天又不吃饭了，好担心",
            keywords: ["橘子", "吃"],
            emotion: .anxious,
            relevantDaysAgo: [150, 90, 88, 30],
            rationale: """
                考精度。标注标准是「讲的是橘子这只猫」，所以生病那两天算，
                日常那两天也算。95「妈妈寄的橘子」是水果、20「很像橘子的野猫」是别的猫，
                两条都会被关键词命中，但都不算 —— 关键词那一路在这里会赔上精度。
                另外 keywords 里的「吃」还会误伤 50 那顿火锅。
                """),

        RecallEvalCase(
            id: 3,
            name: "感觉整个人被榨干了",
            keywords: ["累", "没劲"],
            emotion: .tired,
            relevantDaysAgo: [165, 110, 75, 45, 8],
            rationale: """
                考纯语义。这五条讲的是同一种被掏空的感觉，但用词全不一样：
                「抽干」「不想干」「走路都在飘」「没劲」「没力气」，
                关键词只碰得到 45 那一条。情绪同调反而能全捞上来 ——
                这条 case 是用来证明情绪那一路不是凑数的。
                （120 也是 tired 但讲的是工作，它会作为噪声进来，正常。）
                """),

        RecallEvalCase(
            id: 4,
            name: "跟室友的关系好像好一点了",
            keywords: ["室友"],
            emotion: .calm,
            relevantDaysAgo: [140, 100, 60],
            rationale: """
                对照组。三条都字面含「室友」，关键词那一路该全中，
                所以这条的分数应该始终接近满分。
                **它一掉分，说明坏的是融合或者排序，不是检索本身。**
                """),
    ]

    /// 造纯函数吃的输入。用固定的 now，测试不能依赖「今天」。
    static func documents(now: Date) -> [RecallDocument] {
        entries.map {
            RecallDocument(id: id(daysAgo: $0.daysAgo),
                           date: date(daysAgo: $0.daysAgo, from: now),
                           text: $0.text,
                           emotion: $0.emotion)
        }
    }

    /// 从 daysAgo 造一个确定的 id。**测试里不能用随机 UUID** ——
    /// 那样每次跑出来的向量字典键都不一样，排查时对不上号。
    static func id(daysAgo: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", daysAgo))!
    }

    /// 把标注的 daysAgo 换算成 date，好跟检索结果比对。
    static func relevantDates(_ c: RecallEvalCase, now: Date) -> Set<Date> {
        Set(c.relevantDaysAgo.map { date(daysAgo: $0, from: now) })
    }

    /// 报告里要把 date 显示回「几天前」，不然一堆时间戳没法读。
    static func daysAgo(_ date: Date, from now: Date) -> Int {
        Int((now.timeIntervalSince1970 - date.timeIntervalSince1970) / 86_400)
    }

    private static func date(daysAgo: Int, from now: Date) -> Date {
        now.addingTimeInterval(TimeInterval(-daysAgo * 86_400))
    }
}
