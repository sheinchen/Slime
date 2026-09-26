//
//  DebugSeeder+Life.swift
//  Slime
//
//  「一个人的半年」—— 同时喂关怀和聊天检索的主力语料。启动参数 -SeedLife 触发。
//

#if DEBUG
import CoreData

/// 为什么要新造一套，而不是复用已有的两套：
///
/// **关怀和聊天吃的是不同的数据面。** 关怀只读蛋（date/emotion/那 20 字总结），
/// 看的是最近 14 天的走向；聊天检索只读日记正文，候选窗口 365 天，
/// 价值恰恰在久远那几件事。于是：
///  · `seedHistory`（默认那套）情绪曲线清楚，但内容是模板句、只有 5 天 —— 检索无从下手
///  · `seedDiaries`（-SeedDiaries）内容具体，但跨度 20 天、情绪起伏混杂 —— 关怀看不出走向
///
/// 这套两头都管：**最近 14 天密且有明确走向**（喂关怀），
/// **往前半年稀疏但埋了检索用例**（喂 RAG）。
///
/// 三种埋法照搬 `RecallEvalCorpus`，缺一样检索就测不出差异：
///  ① **换词** —— 组长(175/160) / 领导(120) / 上司(40) 是同一个人；
///     抽干(165) / 不想干(110) / 走路都在飘(75) / 没劲(45) 是同一种感觉
///  ② **干扰** —— 95 天前「妈妈寄的橘子」是水果、20 天前「很像橘子的野猫」是别的猫，
///     两条都会被关键词命中，但都不是那只叫橘子的猫
///  ③ **久远** —— 橘子生病在 90/88 天前。**时间一旦参与排名，这两条就永远上不来**，
///     整套检索会退化成「最近 N 天」
///
/// 175 天前那条「组长当众说方案不通」和昨天那条**故意写得很像** ——
/// 聊「今天又被组长说了」时能不能翻出半年前同一件事，正是这套检索存在的理由。
///
/// **所有过去的天都带蛋**：`hatchAllPending` 只补 14 天内、不含今天，
/// 15 天以前不给蛋也不会自动补，但月历上那些格子会空着。
/// 蛋的 createdAt 一律比当天最后一篇晚 60 秒，否则 `EggDebt` 判「蛋过时了」，一开 App 就重孵一堆。
extension DebugSeeder {

    private struct LifeEntry {
        /// 那天几点写的。**今天的不用这个**，见 seed() 里的说明。
        let hour: Int
        let emotion: SlimeEmotion
        let text: String
    }

    private struct LifeDay {
        let daysAgo: Int
        /// nil = 还没孵。只有今天这样 —— 今天的蛋留给按母鸡。
        let egg: (emotion: SlimeEmotion, text: String)?
        let entries: [LifeEntry]
    }

    // MARK: - 主语料

    /// 蛋的总结压在 20 字内。鸟巢下面那行是单行，这个字号一行只放得下 22 字左右。
    private static let life: [LifeDay] = [

        // ══════ 今天：留白给按母鸡 ══════
        // 内容明显回暖 —— 孵出来之后蛋会是 happy/calm，
        // 跟下面连着六天的低落形成转折，那正是验「AI 要不要把旧关怀换掉」的场景。
        LifeDay(daysAgo: 0, egg: nil, entries: [
            // 唯一一篇超出卡片高度的。**别改短** —— 它是卡片内竖滚和底部渐隐的验证用例
            LifeEntry(hour: 0, emotion: .calm, text: """
                昨晚还是两点才睡着，翻来覆去把这阵子的事从头到尾想了一遍。

                项目从六月拖到现在，需求改了四版，每次都说这是最后一版，过两天又有新的。我知道不该跟这个较劲，可每次推倒重来的时候还是会想，前面那两个礼拜到底算什么。上周跟小林吃饭，她说她也一样，公司不一样，事情几乎一模一样，我们俩在火锅店里笑了半天，笑完谁也没说出个解法。

                今天早上倒是想通一件事：我好像一直在等某个节点，等这版交了、等这个季度过了，就能松一口气。可去年这个时候我也是这么想的，前年大概也是。也许根本没有那个节点，只有一天接着一天——这么一想反而轻松了，那就一天一天过吧。

                天亮了，楼下早餐店开门了，我去买个面包。
                """),
            LifeEntry(hour: 0, emotion: .happy, text: "早上买到了最后一个肉松面包，小小的好运"),
            LifeEntry(hour: 0, emotion: .happy, text: "方案过了！组长居然说这版想得挺清楚"),
            LifeEntry(hour: 0, emotion: .calm,  text: "晚上和橘子在沙发上待了会儿，它呼噜声特别响"),
        ]),

        // ══════ 最近 14 天：喂关怀 ══════
        // 走向是「平稳 → 下滑 → 连着低落」。11 和 8 两天故意留空，
        // 顺带验周条/月历的空档和鸟巢的「你没理我」状态。

        LifeDay(daysAgo: 1, egg: (.sad, "被组长点名，火锅缓了口气，又加班到十点"), entries: [
            LifeEntry(hour: 9,  emotion: .angry, text: "早会上组长当着大家的面说我方案没想清楚"),
            LifeEntry(hour: 12, emotion: .happy, text: "中午和小林去吃了那家新开的火锅，辣得很过瘾"),
            LifeEntry(hour: 21, emotion: .tired, text: "晚上加班到十点，回家洗完澡就不想动了"),
        ]),
        LifeDay(daysAgo: 2, egg: (.tired, "连着加班第四天，躺下就不想起来"), entries: [
            LifeEntry(hour: 21, emotion: .tired, text: "连着加班第四天，躺下就不想起来了"),
        ]),
        LifeDay(daysAgo: 3, egg: (.anxious, "三杯咖啡赶进度，心跳有点快"), entries: [
            LifeEntry(hour: 8,  emotion: .anxious, text: "后天要交的东西还差一大半"),
            LifeEntry(hour: 13, emotion: .anxious, text: "咖啡喝了三杯，心跳有点快"),
        ]),
        LifeDay(daysAgo: 4, egg: (.sad, "外婆住院很揪心，视频里她还笑着"), entries: [
            LifeEntry(hour: 11, emotion: .sad,  text: "妈妈打电话说外婆住院了，不严重，但心里一直揪着"),
            LifeEntry(hour: 22, emotion: .calm, text: "视频里外婆还笑着让我别担心，稍微放下一点"),
        ]),
        LifeDay(daysAgo: 5, egg: (.tired, "开一天会脑子发木，橘子黏了一晚上"), entries: [
            LifeEntry(hour: 18, emotion: .tired, text: "开了一整天会，脑子是木的"),
            LifeEntry(hour: 22, emotion: .calm,  text: "橘子今天特别黏人，在我腿上趴了一晚上"),
        ]),
        LifeDay(daysAgo: 6, egg: (.sad, "方案第四次被打回，没被听懂"), entries: [
            LifeEntry(hour: 14, emotion: .sad, text: "方案又被打回来了，这是第四版"),
            LifeEntry(hour: 21, emotion: .sad, text: "跟小林说了两句，还是觉得没被听懂"),
        ]),
        LifeDay(daysAgo: 7, egg: (.tired, "早起赶车，想法没人接，一碗面缓过来"), entries: [
            LifeEntry(hour: 9,  emotion: .tired, text: "连着第三天早起赶车，眼睛都睁不开"),
            LifeEntry(hour: 15, emotion: .sad,   text: "在会上提的想法没人接，有点失落"),
            LifeEntry(hour: 22, emotion: .calm,  text: "回家煮了碗面，看了两集老剧"),
        ]),
        // daysAgo 8：空
        LifeDay(daysAgo: 9, egg: (.anxious, "体检有项偏高，查完资料安心一点"), entries: [
            LifeEntry(hour: 10, emotion: .anxious, text: "体检报告有一项偏高，约了下周复查"),
            LifeEntry(hour: 21, emotion: .calm,    text: "查了查资料，好像大多数都是虚惊一场"),
        ]),
        LifeDay(daysAgo: 10, egg: (.calm, "收拾阳台，晒了一下午被子"), entries: [
            LifeEntry(hour: 16, emotion: .calm, text: "把阳台整个收拾了一遍，被子晒了一下午"),
        ]),
        // daysAgo 11：空
        LifeDay(daysAgo: 12, egg: (.happy, "稿子过审，奖励自己一副耳机"), entries: [
            LifeEntry(hour: 12, emotion: .happy, text: "收到之前投的稿子过审的邮件！"),
            LifeEntry(hour: 20, emotion: .happy, text: "给自己买了一直想要的那副耳机"),
        ]),
        LifeDay(daysAgo: 13, egg: (.calm, "下雨天窝在家拼完了拼图"), entries: [
            LifeEntry(hour: 15, emotion: .calm, text: "下了一天雨，窝在家里把那幅一千片的拼图拼完了"),
        ]),

        // ══════ 15 天以前：喂聊天检索 ══════
        // 关怀窗口够不到这里（14 天）。稀疏铺开，每条都是一件具体的事。

        LifeDay(daysAgo: 15, egg: (.happy, "买了双想很久的鞋"), entries: [
            LifeEntry(hour: 19, emotion: .happy, text: "买了双想很久的鞋"),
        ]),
        // 干扰②：字面有「橘子」，说的是别的猫
        LifeDay(daysAgo: 20, egg: (.happy, "碰到一只像橘子的野猫，喂了会儿"), entries: [
            LifeEntry(hour: 18, emotion: .happy, text: "路上碰到一只很像橘子的野猫，蹲下喂了会儿"),
        ]),
        LifeDay(daysAgo: 25, egg: (.calm, "下雨，在家看完一部电影"), entries: [
            LifeEntry(hour: 20, emotion: .calm, text: "下雨，在家看完一部电影"),
        ]),
        LifeDay(daysAgo: 30, egg: (.calm, "橘子乖了很多，晚上趴脚边睡"), entries: [
            LifeEntry(hour: 22, emotion: .calm, text: "橘子最近乖了很多，晚上会趴在我脚边睡"),
        ]),
        // 换词④：上司
        LifeDay(daysAgo: 40, egg: (.angry, "上司说交付慢，可需求一直在改"), entries: [
            LifeEntry(hour: 15, emotion: .angry, text: "上司在群里@我说交付太慢，可需求一直在改啊"),
        ]),
        // 语义④：没劲
        LifeDay(daysAgo: 45, egg: (.tired, "睡了十小时，还是一点劲都没有"), entries: [
            LifeEntry(hour: 13, emotion: .tired, text: "睡了快十个小时，还是一点劲都没有"),
        ]),
        LifeDay(daysAgo: 50, egg: (.happy, "和小林吃火锅，聊到很晚"), entries: [
            LifeEntry(hour: 21, emotion: .happy, text: "跟小林吃了顿火锅，聊到很晚"),
        ]),
        // 室友线③：和好
        LifeDay(daysAgo: 60, egg: (.calm, "室友买了洗洁精，算是和好了"), entries: [
            LifeEntry(hour: 20, emotion: .calm, text: "室友主动买了洗洁精回来，好像算和好了"),
        ]),
        LifeDay(daysAgo: 70, egg: (.calm, "换了新床单，被子晒得暖暖的"), entries: [
            LifeEntry(hour: 16, emotion: .calm, text: "换了新床单，被子晒得暖暖的"),
        ]),
        // 语义③：走路都在飘
        LifeDay(daysAgo: 75, egg: (.tired, "连续加班第五天，走路都在飘"), entries: [
            LifeEntry(hour: 22, emotion: .tired, text: "连续加班第五天，走路都在飘"),
        ]),
        // 久远②：橘子生病 —— 时间一进排名，这两条就永远上不来
        LifeDay(daysAgo: 88, egg: (.anxious, "橘子肾指标偏高，要控制饮食"), entries: [
            LifeEntry(hour: 11, emotion: .anxious, text: "医生说橘子肾指标偏高，以后要控制饮食"),
        ]),
        LifeDay(daysAgo: 90, egg: (.sad, "橘子不吃东西，去医院抽了血"), entries: [
            LifeEntry(hour: 10, emotion: .sad, text: "橘子这两天不太吃东西，带去医院抽了血"),
        ]),
        // 干扰①：字面有「橘子」，说的是水果
        LifeDay(daysAgo: 95, egg: (.happy, "妈妈寄来一箱橘子，很甜"), entries: [
            LifeEntry(hour: 19, emotion: .happy, text: "妈妈寄了一箱橘子过来，很甜"),
        ]),
        // 室友线②：起冲突
        LifeDay(daysAgo: 100, egg: (.anxious, "说了洗碗的事，气氛僵了一晚"), entries: [
            LifeEntry(hour: 21, emotion: .anxious, text: "跟室友说了洗碗的事，气氛僵了一晚上"),
        ]),
        // 语义②：什么都不想干
        LifeDay(daysAgo: 110, egg: (.tired, "什么都不想干，躺了一下午"), entries: [
            LifeEntry(hour: 15, emotion: .tired, text: "什么都不想干，在床上躺了一下午"),
        ]),
        LifeDay(daysAgo: 115, egg: (.calm, "换了张新书桌，摆了半天"), entries: [
            LifeEntry(hour: 17, emotion: .calm, text: "换了张新书桌，摆了半天才顺眼"),
        ]),
        // 换词③：领导
        LifeDay(daysAgo: 120, egg: (.tired, "领导让总结推翻重写，写到十点"), entries: [
            LifeEntry(hour: 22, emotion: .tired, text: "领导让我把季度总结推翻重写，写到十点多"),
        ]),
        LifeDay(daysAgo: 130, egg: (.happy, "述职过了，腿都是软的"), entries: [
            LifeEntry(hour: 16, emotion: .happy, text: "述职过了，走出来那一刻腿都是软的"),
        ]),
        LifeDay(daysAgo: 135, egg: (.happy, "看了个展，人不多很舒服"), entries: [
            LifeEntry(hour: 15, emotion: .happy, text: "周末去看了个展，人不多，很舒服"),
        ]),
        // 室友线①：起头
        LifeDay(daysAgo: 140, egg: (.angry, "室友又没洗碗，忍着没说"), entries: [
            LifeEntry(hour: 20, emotion: .angry, text: "室友又没洗碗，第三次了，忍着没说出口"),
        ]),
        // 久远①：橘子这只猫最早出场
        LifeDay(daysAgo: 150, egg: (.happy, "橘子会自己跳窗台了"), entries: [
            LifeEntry(hour: 17, emotion: .happy, text: "橘子今天会自己跳上窗台了，蹲那儿看了半小时"),
        ]),
        LifeDay(daysAgo: 155, egg: (.calm, "楼下新开面包店，买了个可颂"), entries: [
            LifeEntry(hour: 9, emotion: .calm, text: "楼下新开了家面包店，买了个可颂"),
        ]),
        // 换词②：组长
        LifeDay(daysAgo: 160, egg: (.anxious, "要跟组长过进度，没睡好"), entries: [
            LifeEntry(hour: 23, emotion: .anxious, text: "明天要跟组长过一遍进度，昨晚翻来覆去没睡好"),
        ]),
        // 语义①：脑子被抽干
        LifeDay(daysAgo: 165, egg: (.tired, "查了一整天资料，脑子被抽干"), entries: [
            LifeEntry(hour: 21, emotion: .tired, text: "查了一整天资料，脑子像被抽干一样"),
        ]),
        LifeDay(daysAgo: 170, egg: (.anxious, "述职在下周，什么都没准备"), entries: [
            LifeEntry(hour: 14, emotion: .anxious, text: "下周要过一次季度述职，到现在什么都没准备"),
        ]),
        // 换词①：组长。**故意跟昨天那条写得很像** ——
        // 聊「今天又被组长说了」能不能翻出半年前同一件事，正是这套检索存在的理由
        LifeDay(daysAgo: 175, egg: (.angry, "周会上被组长当众说方案不通"), entries: [
            LifeEntry(hour: 11, emotion: .angry, text: "组长在周会上说我这版方案逻辑不通，当着十几个人"),
        ]),
    ]

    // MARK: - 两套反向用例

    /// 14 天全是平稳起伏，没有任何走向。
    /// **闸门会放行**（天数够、有新蛋、没冷却），所以这套专门验 AI 的一票否决权 ——
    /// 它该判「这次不值得说」。卡片冒出来就是 prompt 出问题了。
    private static let flat: [LifeDay] = {
        let days: [(SlimeEmotion, String)] = [
            (.calm,  "把冰箱里过期的东西清了一遍"),
            (.happy, "楼下咖啡店的新品还不错"),
            (.calm,  "照常上班，中午在食堂吃的"),
            (.calm,  "晚上散了会儿步，风挺舒服"),
            (.happy, "同事带了老家的特产分给大家"),
            (.calm,  "整理了一下相册，删了两千张重复的"),
            (.calm,  "买了点日用品，顺手换了牙刷"),
            (.happy, "追的剧更新了两集"),
            (.calm,  "把拖了很久的水电费交了"),
            (.calm,  "今天挺普通的，没什么特别的事"),
            (.happy, "中午食堂的红烧肉居然不错"),
            (.calm,  "下班早，回家做了个番茄炒蛋"),
            (.calm,  "给绿萝换了个大点的盆"),
            (.happy, "睡了个懒觉，醒来快中午了"),
        ]
        return days.enumerated().map { index, day in
            LifeDay(daysAgo: index + 1,
                    egg: (day.0, day.1),
                    entries: [LifeEntry(hour: 20, emotion: day.0, text: day.1)])
        }
    }()

    /// 只有 2 天有蛋 —— 卡在 `CareGateRule.minDaysWithEgg`（3）下面一格。
    /// 验闸门②：应该**根本不调 AI**（`调AI:否`），这是本地闸门省钱那一面。
    private static let thin: [LifeDay] = [
        LifeDay(daysAgo: 1, egg: (.tired, "加班到很晚，没什么想说的"), entries: [
            LifeEntry(hour: 22, emotion: .tired, text: "加班到很晚，没什么想说的"),
        ]),
        LifeDay(daysAgo: 2, egg: (.calm, "普通的一天"), entries: [
            LifeEntry(hour: 20, emotion: .calm, text: "普通的一天，没什么特别的"),
        ]),
    ]

    // MARK: - 入口

    /// 半年生活。关怀和聊天检索都吃这套。
    static func seedLife(now: Date = Date(),
                         calendar: Calendar = .current,
                         context: NSManagedObjectContext = CoreDataStack.shared.viewContext) {
        seed(life, label: "半年生活", now: now, calendar: calendar, context: context)
    }

    /// 14 天平稳。验 AI 否决权。
    static func seedFlat(now: Date = Date(),
                         calendar: Calendar = .current,
                         context: NSManagedObjectContext = CoreDataStack.shared.viewContext) {
        seed(flat, label: "14 天平稳（验 AI 否决）", now: now, calendar: calendar, context: context)
    }

    /// 只有 2 天。验闸门「天数不足」。
    static func seedThin(now: Date = Date(),
                         calendar: Calendar = .current,
                         context: NSManagedObjectContext = CoreDataStack.shared.viewContext) {
        seed(thin, label: "只有 2 天（验闸门天数不足）", now: now, calendar: calendar, context: context)
    }

    // MARK: - 共用播种

    private static func seed(_ days: [LifeDay],
                             label: String,
                             now: Date,
                             calendar: Calendar,
                             context: NSManagedObjectContext) {
        guard guardTestStore() else { return }
        wipeAll(context: context)

        let today = calendar.startOfDay(for: now)
        var entryCount = 0

        for seed in days {
            guard let day = calendar.date(byAdding: .day, value: -seed.daysAgo, to: today) else { continue }
            var lastEntryAt = day

            for (n, entry) in seed.entries.enumerated() {
                let at: Date
                if seed.daysAgo == 0 {
                    // 今天的不能用固定钟点 —— 早上跑的话，写着 21 点的那篇就成了未来的日记。
                    // 在「今天零点 → 现在」之间均匀摊开，保证都在过去、先后顺序不乱。
                    let span = now.timeIntervalSince(today)
                    at = today.addingTimeInterval(span * Double(n + 1) / Double(seed.entries.count + 1))
                } else {
                    at = calendar.date(byAdding: .hour, value: entry.hour, to: day) ?? day
                }
                lastEntryAt = at

                let post = Post(context: context)
                post.id = UUID()
                post.content = entry.text
                post.createdAt = at
                post.dayKey = day                        // 归堆靠它，别漏
                post.emotion = entry.emotion.rawValue
                post.reply = "测试数据"
                entryCount += 1
            }

            if let egg = seed.egg {
                // 刚 wipeAll 过，不会撞上已有的蛋，直接建
                let record = DayEgg(context: context)
                record.date = day
                record.text = egg.text
                record.emotion = egg.emotion.rawValue
                // 必须晚于那天最后一篇 —— 否则 EggDebt 判「蛋过时了」，一开 App 就重孵一堆
                record.createdAt = lastEntryAt.addingTimeInterval(60)
            }
        }

        saveIfNeeded(context)
        print("📔 播种「\(label)」：\(days.count) 天、\(entryCount) 篇日记")
    }
}
#endif
