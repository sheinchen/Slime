//
//  CareEvalCases.swift
//  SlimeTests
//
//  关怀决策的 golden set —— 20 个手工构造的情绪时间线 + 人工标注。
//
//  ⚠️ 这个文件是**产品判断**，不是代码。
//     expected 那一列决定了母鸡的性格：话多还是话少、宁可漏说还是宁可多说。
//     改这里之前想清楚，改完要重跑 eval 看分数怎么动。
//

import Foundation
@testable import Slime

nonisolated struct EvalCase {
    let id: Int
    let name: String

    /// 时间线。daysAgo: 1 = 昨天。按从早到晚排（daysAgo 递减）。
    /// 中间可以留缺口 —— 那天没写日记就没有蛋，**缺口本身也是信息**。
    let days: [(daysAgo: Int, emotion: SlimeEmotion, summary: String)]

    /// 「最近对ta说过的话」。空数组 = 之前没说过。
    let recentlySaid: [String]

    /// 人工标注：这时候该不该开口。
    let expected: Bool

    /// 为什么这么标。**必须写** —— 过几周你自己都不记得当初怎么想的，
    /// 而分数动了之后要回来看的就是这一列。
    let rationale: String

    /// 造出交给 AI 的窗口。用固定的 now，测试不能依赖「今天」。
    func window(now: Date, calendar: Calendar = .current) -> MoodWindow {
        let today = calendar.startOfDay(for: now)
        let eggs = days.map { d -> DayEggRecord in
            let day = calendar.date(byAdding: .day, value: -d.daysAgo, to: today) ?? today
            return DayEggRecord(date: day, text: d.summary, emotion: d.emotion, createdAt: day)
        }
        return MoodWindow(eggs: eggs.sorted { $0.date < $1.date })
    }
}

nonisolated enum CareEvalCases {

    /// 上一条关怀说过的话，几个场景共用
    private static let saidTired = "最近好像有点累呀，别硬撑着~"

    static let all: [EvalCase] = [

        // ────────────── 该说 · 低落走向 ──────────────

        EvalCase(id: 1, name: "持续低谷未缓解",
                 days: [(5, .sad,     "方案被打回来第三次，坐着发了很久呆"),
                        (4, .sad,     "是不是我根本不适合做这个"),
                        (3, .tired,   "躺下三个小时还醒着"),
                        (2, .sad,     "什么都想做，什么都没做成"),
                        (1, .tired,   "还是提不起劲，一天就这么过去了")],
                 recentlySaid: [],
                 expected: true,
                 rationale: "五天没缓解，走向明确，而且有具体的东西可以接住"),

        EvalCase(id: 2, name: "一路往下沉",
                 days: [(4, .anxious, "事情堆着，有点烦"),
                        (3, .sad,     "越想越闷，跟谁都不想说"),
                        (2, .sad,     "什么都不想做，躺了一下午"),
                        (1, .tired,   "连饭都懒得吃")],
                 recentlySaid: [],
                 expected: true,
                 rationale: "不是停在原地，是一天比一天沉 —— 走向本身就是信号"),

        EvalCase(id: 3, name: "孤独反复出现（中间缺两天）",
                 days: [(7, .sad,     "说了半天，感觉没一个人听懂"),
                        (4, .sad,     "一屋子人，反而更孤单"),
                        (1, .sad,     "想找人说说，打开对话框又关了")],
                 recentlySaid: [],
                 expected: true,
                 rationale: "同一个主题隔着日子反复冒出来。缺的那两天不是噪声，是「没什么想记的」"),

        EvalCase(id: 4, name: "悬着的事一直没落地",
                 days: [(5, .anxious, "投出去了，等消息"),
                        (4, .anxious, "还是没回音"),
                        (3, .anxious, "越想越慌，一直在刷邮箱"),
                        (2, .tired,   "没睡好，脑子是木的"),
                        (1, .anxious, "还在等")],
                 recentlySaid: [],
                 expected: true,
                 rationale: "焦虑源一直没解除，五天悬着 —— 这种「卡住」比低落更磨人"),

        // ────────────── 该说 · 好的走向 ──────────────

        EvalCase(id: 5, name: "连续高光",
                 days: [(5, .happy, "出发了，火车上一路看风景"),
                        (4, .happy, "见到了好久没见的朋友，聊到半夜"),
                        (3, .happy, "天气好得不像话，走了一万多步"),
                        (2, .happy, "终于吃到那家一直想去的店"),
                        (1, .happy, "回来了，事情居然也都顺顺利利")],
                 recentlySaid: [],
                 expected: true,
                 rationale: "母鸡不是难过警报器，是看见你的人。好的走向也值得被看见"),

        EvalCase(id: 6, name: "低谷后终于松了口气",
                 days: [(4, .sad,   "改到第三版，还是不对"),
                        (3, .sad,   "怀疑自己是不是没这个能力"),
                        (2, .tired, "硬撑着改完了最后一稿"),
                        (1, .calm,  "过了。下楼吃了碗面，风挺舒服")],
                 recentlySaid: [],
                 expected: true,
                 rationale: "转折清楚，那口气松下来的时刻是可以被接住的"),

        // ────────────── 该说 · 延续中 ──────────────

        EvalCase(id: 7, name: "走向没变，但出现了新东西",
                 days: [(4, .sad,   "项目又出问题，被点名了"),
                        (3, .sad,   "越来越怀疑自己"),
                        (2, .tired, "早上起不来，赖到中午"),
                        (1, .sad,   "是不是根本不适合干这行")],
                 recentlySaid: [saidTired],
                 expected: true,
                 rationale: "上次说的是「累」，这次冒出来的是「自我怀疑」—— 有新角度可接。"
                          + "走向还在延续时沉默，会像走开了",

        // 注：和 #20 成对。区别只在有没有新东西可说
                ),

        EvalCase(id: 8, name: "性质变了",
                 days: [(4, .tired, "连着加班第四天"),
                        (3, .tired, "身体是累，倒也还撑得住"),
                        (2, .sad,   "忽然觉得，做这些到底图什么"),
                        (1, .sad,   "还是那个问题，想不明白")],
                 recentlySaid: [saidTired],
                 expected: true,
                 rationale: "从「身体累」变成了「意义感」，已经不是同一件事，上次说过不构成理由"),

        // ────────────── 不说 · 太短 ──────────────

        EvalCase(id: 9, name: "单日低落",
                 days: [(5, .calm,  "普通的一天，把活干完了"),
                        (4, .calm,  "中午和同事吃了饭"),
                        (3, .sad,   "被说了几句，心里有点堵"),
                        (2, .calm,  "睡了一觉好多了"),
                        (1, .calm,  "周末，收拾了下屋子")],
                 recentlySaid: [],
                 expected: false,
                 rationale: "一天的情绪不是趋势，而且第二天就过去了 —— 这就是日常起伏"),

        EvalCase(id: 10, name: "才两天，看不出走向",
                 days: [(4, .happy, "拿到了想要的东西，挺开心"),
                        (3, .calm,  "平平常常"),
                        (2, .sad,   "有点不顺"),
                        (1, .sad,   "还是不太顺")],
                 recentlySaid: [],
                 expected: false,
                 rationale: "才两天，还不知道是低谷的开始还是普通的两天不顺"),

        EvalCase(id: 11, name: "刚开始，还没成形",
                 days: [(5, .calm,  "正常上班"),
                        (4, .calm,  "正常上班"),
                        (3, .calm,  "买了点东西"),
                        (2, .calm,  "看了会儿书"),
                        (1, .tired, "今天有点累")],
                 recentlySaid: [],
                 expected: false,
                 rationale: "最后一天才有点累，前面全是平的 —— 现在开口太早了"),

        // ────────────── 不说 · 日常范围 ──────────────

        EvalCase(id: 12, name: "有好有坏，都不深",
                 days: [(5, .happy, "早上买到了想吃的面包"),
                        (4, .calm,  "没什么特别的"),
                        (3, .happy, "晚上散步，风很舒服"),
                        (2, .tired, "开了一天会有点困"),
                        (1, .calm,  "把拖了很久的事做完了")],
                 recentlySaid: [],
                 expected: false,
                 rationale: "这就是这个人的常态。在日常范围内的起伏不需要被指出来"),

        EvalCase(id: 13, name: "外部事件，已经消化了",
                 days: [(3, .angry, "排队被人插队，气了一路"),
                        (2, .calm,  "想想也没什么，算了"),
                        (1, .calm,  "正常的一天")],
                 recentlySaid: [],
                 expected: false,
                 rationale: "情绪有明确的外部来源，而且用户自己已经翻篇了"),

        EvalCase(id: 14, name: "单次情绪，没有延续",
                 days: [(4, .calm,  "普通的一天"),
                        (3, .angry, "和人吵了两句，有点上头"),
                        (2, .calm,  "过去了"),
                        (1, .calm,  "还行")],
                 recentlySaid: [],
                 expected: false,
                 rationale: "一次性的情绪，前后都平 —— 没有走向"),

        // ────────────── 不说 · 无信号 ──────────────

        EvalCase(id: 15, name: "流水账",
                 days: [(3, .calm, "开了个会"),
                        (2, .calm, "下班顺路买了菜"),
                        (1, .calm, "晚上看了集剧")],
                 recentlySaid: [],
                 expected: false,
                 rationale: "刚好卡在闸门下限，但没有任何情绪信号 —— 强行开口只能说空话"),

        EvalCase(id: 16, name: "五天都很平",
                 days: [(5, .calm, "照常"),
                        (4, .calm, "把手边的事做完了"),
                        (3, .calm, "没什么特别的"),
                        (2, .calm, "早睡了"),
                        (1, .calm, "又是平平的一天")],
                 recentlySaid: [],
                 expected: false,
                 rationale: "平稳不是问题，不需要被关心"),

        EvalCase(id: 17, name: "内容太薄",
                 days: [(3, .calm,  "还行"),
                        (2, .tired, "有点困"),
                        (1, .calm,  "嗯")],
                 recentlySaid: [],
                 expected: false,
                 rationale: "有情绪标签但没有内容，接不住任何具体的东西"),

        // ────────────── 原本归在「只能说空话」，2026-09-07 重审后改判该说 ──────────────

        EvalCase(id: 18, name: "三天只写得出一个累字",
                 days: [(3, .tired, "累"),
                        (2, .tired, "还是累"),
                        (1, .tired, "好累")],
                 recentlySaid: [],
                 expected: true,
                 rationale: "【2026-09-07 改判：原标不说】写不出话本身就是信号 —— 累到只剩一个字，"
                          + "正是最该被看见的时候。连着三天写「累」却毫无反应，用户会觉得没人在看"),

        EvalCase(id: 19, name: "分手后自己在缓过来",
                 days: [(3, .sad,  "分手了，难受"),
                        (2, .sad,  "跟朋友聊了很久，哭了一场，好一点"),
                        (1, .calm, "开始收拾东西，慢慢来吧")],
                 recentlySaid: [],
                 expected: true,
                 rationale: "【2026-09-07 改判：原标不说】和 #6 是同一个结构（低谷 → 缓过来的转折），"
                          + "原来标反了。有朋友陪不代表不需要母鸡"),

        EvalCase(id: 20, name: "走向延续，但没有新角度",
                 days: [(3, .tired, "又是加班的一天"),
                        (2, .tired, "还是加班"),
                        (1, .tired, "加班加到现在")],
                 recentlySaid: [saidTired],
                 expected: false,
                 rationale: "和 #7 成对：同样是走向延续 + 上次说过，但这里没有任何新东西。"
                          + "这时候才该闭嘴 —— 再说一遍就是复读"),
    ]
}
