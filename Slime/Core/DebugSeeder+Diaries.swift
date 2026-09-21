//
//  DebugSeeder+Diaries.swift
//  Slime
//
//  一套「像真在用」的日记。启动参数 -SeedDiaries 触发。
//

#if DEBUG
import CoreData

/// 给手动验证删除、卡片堆、周条、月历用的数据。
///
/// 跟 `seedHistory` 的区别：那边是给关怀造情绪曲线的，同一天几篇只是同一句话加编号，
/// 删掉一篇重孵出来的总结跟原来一模一样，看不出任何东西。
/// 这边每篇是一件**具体、互不相同**的事，蛋的总结点名这些事 ——
/// 删掉一篇后重孵，一眼就能看出总结里还有没有它。
///
/// 每天对应一个要验的场景：
/// - 今天 3 篇、没蛋 —— 按母鸡孵，再删一篇看蛋是否作废、能否重按
/// - 昨天 3 篇 —— 删一篇，看重孵后的总结里还有没有那件事（火锅最好认）
/// - 前天只有 1 篇 —— 删光，看周条上那天的蛋是否消失
/// - 16 / 18 / 20 天前 —— 在关怀窗口（14 天）外，看删了之后是否当场重孵，而不是永远「还在孵」
/// - 中间留几天空白 —— 周条和鸟巢的「你没有理我」状态
extension DebugSeeder {

    private struct SeedEntry {
        /// 那天几点写的。**今天的不用这个**，见 seedDiaries 里的说明。
        let hour: Int
        let emotion: SlimeEmotion
        let text: String
    }

    private struct SeedDay {
        let daysAgo: Int
        /// nil = 还没孵。只有今天这样 —— 今天的蛋要留给按母鸡。
        let egg: (emotion: SlimeEmotion, text: String)?
        let entries: [SeedEntry]
    }

    /// 蛋的总结都压在 20 字内。鸟巢下面那行是单行，这个字号一行只放得下 22 字左右，
    /// 再长两头会被截掉；真实的总结 prompt 要求不超过 25 字，这里跟它对齐、留点余量。
    private static let diaryLife: [SeedDay] = [
        SeedDay(daysAgo: 0, egg: nil, entries: [
            SeedEntry(hour: 0, emotion: .calm, text: "早上买到了最后一个肉松面包，小小的好运"),
            SeedEntry(hour: 0, emotion: .anxious, text: "下午的评审突然提前了，临时改了半天 PPT"),
            SeedEntry(hour: 0, emotion: .tired, text: "改完已经七点，地铁上站着都快睡着了"),
        ]),
        SeedDay(daysAgo: 1, egg: (.tired, "被组长点名，火锅缓了口气，又加班到十点"), entries: [
            SeedEntry(hour: 9, emotion: .angry, text: "早会上组长当着大家的面说我方案没想清楚"),
            SeedEntry(hour: 12, emotion: .happy, text: "中午和小林去吃了那家新开的火锅，辣得很过瘾"),
            SeedEntry(hour: 21, emotion: .tired, text: "晚上加班到十点，回家洗完澡就不想动了"),
        ]),
        SeedDay(daysAgo: 2, egg: (.calm, "在家洗了一周的衣服，平平静静"), entries: [
            SeedEntry(hour: 20, emotion: .calm, text: "什么也没干，在家把积了一周的衣服洗了"),
        ]),
        SeedDay(daysAgo: 4, egg: (.sad, "外婆住院很揪心，视频里她还笑着"), entries: [
            SeedEntry(hour: 11, emotion: .sad, text: "妈妈打电话说外婆住院了，不严重，但心里一直揪着"),
            SeedEntry(hour: 22, emotion: .calm, text: "视频里外婆还笑着让我别担心，稍微放下一点"),
        ]),
        SeedDay(daysAgo: 5, egg: (.anxious, "三杯咖啡赶报告，下午总算写顺了"), entries: [
            SeedEntry(hour: 8, emotion: .anxious, text: "后天要交的报告还差一大半"),
            SeedEntry(hour: 13, emotion: .anxious, text: "咖啡喝了三杯，心跳有点快"),
            SeedEntry(hour: 17, emotion: .happy, text: "写顺了！一下午推进了两节"),
            SeedEntry(hour: 23, emotion: .calm, text: "关电脑前列好了明天的清单，睡觉"),
        ]),
        SeedDay(daysAgo: 6, egg: (.happy, "睡到自然醒，和室友玩桌游笑到肚子疼"), entries: [
            SeedEntry(hour: 10, emotion: .happy, text: "难得睡到十一点，阳光正好照在被子上"),
            SeedEntry(hour: 16, emotion: .happy, text: "和大学室友约了桌游，笑到肚子疼"),
        ]),
        SeedDay(daysAgo: 7, egg: (.angry, "快递放错驿站，白跑了两趟"), entries: [
            SeedEntry(hour: 19, emotion: .angry, text: "快递被放错了驿站，来回跑了两趟才拿到"),
        ]),
        SeedDay(daysAgo: 9, egg: (.tired, "早起赶车，想法没人接，一碗面缓过来"), entries: [
            SeedEntry(hour: 9, emotion: .tired, text: "连着第三天早起赶车，眼睛都睁不开"),
            SeedEntry(hour: 15, emotion: .sad, text: "在会上提的想法没人接，有点失落"),
            SeedEntry(hour: 22, emotion: .calm, text: "回家煮了碗面，看了两集老剧"),
        ]),
        SeedDay(daysAgo: 10, egg: (.happy, "稿子过审了，奖励自己一副耳机"), entries: [
            SeedEntry(hour: 12, emotion: .happy, text: "收到之前投的稿子过审的邮件！"),
            SeedEntry(hour: 20, emotion: .happy, text: "给自己买了一直想要的那副耳机"),
        ]),
        SeedDay(daysAgo: 12, egg: (.anxious, "体检有项偏高，查完资料安心一点"), entries: [
            SeedEntry(hour: 10, emotion: .anxious, text: "体检报告有一项偏高，约了下周复查"),
            SeedEntry(hour: 21, emotion: .calm, text: "查了查资料，好像大多数都是虚惊一场"),
        ]),
        SeedDay(daysAgo: 13, egg: (.calm, "下雨天窝在家拼完了拼图"), entries: [
            SeedEntry(hour: 15, emotion: .calm, text: "下了一天雨，窝在家里拼完了那幅一千片的拼图"),
        ]),

        // —— 以下在关怀窗口（14 天）外 ——

        SeedDay(daysAgo: 16, egg: (.sad, "翻到旧日记本有点难过，新房间的灯很暖"), entries: [
            SeedEntry(hour: 14, emotion: .sad, text: "搬家整理出以前的日记本，读着读着有点难过"),
            SeedEntry(hour: 22, emotion: .calm, text: "新房间的灯很暖，慢慢收拾吧"),
        ]),
        SeedDay(daysAgo: 18, egg: (.angry, "为押金拉扯一整天，最后全退了"), entries: [
            SeedEntry(hour: 9, emotion: .angry, text: "房东说押金要扣一半，理由是墙上有钉子眼"),
            SeedEntry(hour: 13, emotion: .angry, text: "打了三个电话才把事情讲清楚"),
            SeedEntry(hour: 20, emotion: .happy, text: "押金最后全退了，晚上吃了顿好的庆祝一下"),
        ]),
        SeedDay(daysAgo: 20, egg: (.happy, "第一次做成番茄牛腩，吃撑了绕小区三圈"), entries: [
            SeedEntry(hour: 11, emotion: .happy, text: "第一次自己做成了番茄牛腩，比外卖好吃"),
            SeedEntry(hour: 21, emotion: .calm, text: "吃撑了，在小区里绕了三圈"),
        ]),
    ]

    /// 清空测试库，再播上面这套日记。关怀表也一起清 —— 所以启动时关怀会重新评估一次（调一次 AI）。
    /// 过去的天全都带蛋，所以启动时的补蛋不会调 AI。
    static func seedDiaries(now: Date = Date(),
                            calendar: Calendar = .current,
                            context: NSManagedObjectContext = CoreDataStack.shared.viewContext) {
        guard guardTestStore() else { return }
        wipeAll(context: context)

        let today = calendar.startOfDay(for: now)
        var entryCount = 0

        for seed in diaryLife {
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
        print("📔 播种 \(diaryLife.count) 天、\(entryCount) 篇日记（今天的待孵）")
    }
}
#endif
