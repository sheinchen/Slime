//
//  TutorialScript.swift
//  Slime
//
//  示范里的所有预设内容：用户「写」的那篇、母鸡的回复、过去那些天的日记和蛋。
//  全在内存里，示范一结束就扔掉。
//

import Foundation

enum TutorialScript {

    // MARK: - 今天

    /// 用户在示范里「写」的那篇。写日记页会一个字一个字打出来
    static let diary = "下班路上买到了最后一个菠萝包，还是热的，在地铁上偷偷吃掉了一半。"
    /// 母鸡读完的回复（真 App 里是 AI 写的）
    static let reply = "最后一个还热乎乎的，今天运气站你这边，咕。"
    static let diaryEmotion = SlimeEmotion.happy

    /// 今天早上已经有的一篇 —— 写完之后今天就有两篇，「左右拖卡片」才有下一张可翻
    static let morning = "早上差点迟到，一路小跑进公司，结果会议推迟了。"
    /// 今天两篇收成的那颗蛋
    static let todayEgg = (text: "早上一场虚惊，晚上一个热菠萝包", emotion: SlimeEmotion.happy)

    // MARK: - 过去那些天

    /// 一篇日记。`alone` 是它单独剩下时那天的蛋 —— 示范里删掉一篇，那天按剩下那篇重孵，用的就是它
    struct Entry {
        let hour: Int
        let minute: Int
        let text: String
        let alone: String
    }

    struct PastDay {
        let daysAgo: Int
        /// **每天正好两篇**：示范最后要删一篇、演「按剩下的重孵」，点到哪天都得删完还剩一篇
        /// （`TutorialFlow.canDelete` 靠这个前提）
        let entries: [Entry]
        let egg: String
        let emotion: SlimeEmotion
    }

    /// 两段：最近十天（周条往回翻一周、有蛋可点），和一个多月前的六天（月历往回翻一个月、也有蛋可看）。
    ///
    /// 为什么要第二段：只有最近十天的话，月底打开时十天全在本月，月历只有一页，「翻月」那步滑不动。
    /// 32~41 天前这一段，不管今天是几号，都落在上个月或更早 —— 月历至少两页，而且上个月一定有蛋
    /// （月初打开时，上个月的蛋由最近十天那段补上）。`TutorialSandboxTests` 把一整年每一天都试过。
    ///
    /// 情绪六种都有，月历上铺开是一片不同颜色的蛋。
    /// 不写星期几：示范数据是按「几天前」排的，落在周几随打开的日子变
    static let pastDays: [PastDay] = [
        PastDay(daysAgo: 1, entries: [
            Entry(hour: 9, minute: 12, text: "地铁挤到脚不沾地，到公司的时候衬衫都皱了。", alone: "挤了一早上的地铁"),
            Entry(hour: 22, minute: 40, text: "加班到十点，回家只想躺着，连手机都懒得看。", alone: "加班到十点，只想躺着"),
        ], egg: "挤了一早上地铁，又加班到十点", emotion: .tired),

        PastDay(daysAgo: 2, entries: [
            Entry(hour: 12, minute: 30, text: "午饭和同事拼了一家新开的米粉，辣得很过瘾。", alone: "一碗辣得过瘾的米粉"),
            Entry(hour: 19, minute: 5, text: "下班看到晚霞，粉紫色的，站在路口看了好久。", alone: "下班撞见一片粉紫色晚霞"),
        ], egg: "一碗好米粉，一片好晚霞", emotion: .happy),

        PastDay(daysAgo: 3, entries: [
            Entry(hour: 10, minute: 20, text: "明天要汇报，PPT 还差一半，心里一直悬着。", alone: "汇报前一天，PPT 还差一半"),
            Entry(hour: 23, minute: 10, text: "改到十一点终于改完了，但还是有点睡不着。", alone: "改完了，还是睡不着"),
        ], egg: "赶汇报赶到深夜，心一直悬着", emotion: .anxious),

        PastDay(daysAgo: 4, entries: [
            Entry(hour: 8, minute: 40, text: "睡到自然醒，阳光正好照在被子上。", alone: "睡到自然醒的一天"),
            Entry(hour: 16, minute: 0, text: "去公园走了一圈，看老人下棋，看了一下午。", alone: "在公园看了一下午棋"),
        ], egg: "自然醒，公园里看了一下午棋", emotion: .calm),

        PastDay(daysAgo: 5, entries: [
            Entry(hour: 11, minute: 15, text: "快递又被放错柜子，打了三次电话才找到。", alone: "快递又被放错了柜子"),
            Entry(hour: 20, minute: 30, text: "楼上又在装修，电钻声一晚上都没停。", alone: "楼上电钻响了一晚上"),
        ], egg: "快递放错柜子，楼上电钻不停", emotion: .angry),

        PastDay(daysAgo: 6, entries: [
            Entry(hour: 13, minute: 0, text: "好朋友突然寄来一箱橘子，还附了张手写卡片。", alone: "收到一箱橘子和一张卡片"),
            Entry(hour: 21, minute: 0, text: "剥了三个橘子，边吃边看完了一部老电影。", alone: "吃着橘子看了部老电影"),
        ], egg: "一箱橘子，一张手写卡片", emotion: .happy),

        PastDay(daysAgo: 7, entries: [
            Entry(hour: 18, minute: 20, text: "养了两年的绿萝突然枯了一大半。", alone: "养了两年的绿萝枯了"),
            Entry(hour: 22, minute: 50, text: "查了半天，可能是浇水太勤了，有点难过。", alone: "浇水太勤，把它养坏了"),
        ], egg: "养了两年的绿萝枯了一大半", emotion: .sad),

        PastDay(daysAgo: 8, entries: [
            Entry(hour: 7, minute: 50, text: "早起煮了一锅粥，慢慢喝完才出门。", alone: "慢慢喝完一锅粥"),
            Entry(hour: 21, minute: 30, text: "把书架整理了一遍，翻出一张好几年前的车票。", alone: "整理书架，翻出一张旧车票"),
        ], egg: "一锅粥，一个整理好的书架", emotion: .calm),

        PastDay(daysAgo: 9, entries: [
            Entry(hour: 15, minute: 40, text: "下午连开三个会，嗓子都说哑了。", alone: "连开三个会，嗓子哑了"),
            Entry(hour: 20, minute: 10, text: "晚饭随便泡了碗面，洗完澡就想睡。", alone: "晚饭一碗泡面"),
        ], egg: "连开三个会，晚饭一碗泡面", emotion: .tired),

        PastDay(daysAgo: 10, entries: [
            Entry(hour: 10, minute: 0, text: "学了一个月吉他，今天终于能完整弹完一首歌。", alone: "第一次完整弹完一首歌"),
            Entry(hour: 19, minute: 30, text: "录了一段发给朋友，她回了一串感叹号。", alone: "朋友回了一串感叹号"),
        ], egg: "第一次完整弹完一首歌", emotion: .happy),

        // —— 一个多月前 ——

        PastDay(daysAgo: 32, entries: [
            Entry(hour: 9, minute: 30, text: "去图书馆待了一上午，抢到了窗边的位子。", alone: "抢到了图书馆窗边的位子"),
            Entry(hour: 17, minute: 10, text: "回家路上下起小雨，没带伞，慢慢走回去的。", alone: "淋着小雨慢慢走回家"),
        ], egg: "图书馆窗边的一上午，一场小雨", emotion: .calm),

        PastDay(daysAgo: 34, entries: [
            Entry(hour: 12, minute: 10, text: "同事过生日，中午分到一块蛋糕，奶油有点太甜。", alone: "中午分到一块生日蛋糕"),
            Entry(hour: 21, minute: 20, text: "跟妈妈视频，她新学会了发表情包。", alone: "妈妈学会了发表情包"),
        ], egg: "一块蛋糕，一串妈妈的表情包", emotion: .happy),

        PastDay(daysAgo: 35, entries: [
            Entry(hour: 8, minute: 50, text: "面试通知来了，就在下周，现在就开始紧张。", alone: "收到下周的面试通知"),
            Entry(hour: 23, minute: 30, text: "躺下又爬起来，把简历改了一遍。", alone: "半夜爬起来改简历"),
        ], egg: "收到面试通知，紧张到半夜改简历", emotion: .anxious),

        PastDay(daysAgo: 37, entries: [
            Entry(hour: 14, minute: 0, text: "搬家打包了一整天，箱子比想象的多。", alone: "打包了一整天"),
            Entry(hour: 22, minute: 10, text: "腰酸得直不起来，泡面都懒得泡。", alone: "累得泡面都懒得泡"),
        ], egg: "打包了一整天，累到懒得吃饭", emotion: .tired),

        PastDay(daysAgo: 39, entries: [
            Entry(hour: 19, minute: 0, text: "常去的那家面馆关门了，门口贴了张告别信。", alone: "常去的面馆关门了"),
            Entry(hour: 21, minute: 40, text: "想起第一次去是和老同学一起，有点舍不得。", alone: "想起和老同学去吃面"),
        ], egg: "常去的面馆关门了", emotion: .sad),

        PastDay(daysAgo: 41, entries: [
            Entry(hour: 10, minute: 40, text: "被临时拉去加一个会，原本的安排全乱了。", alone: "被临时拉去开会"),
            Entry(hour: 18, minute: 30, text: "排了半小时队，轮到我的时候说卖完了。", alone: "排了半小时队，卖完了"),
        ], egg: "安排被打乱，排队又白排", emotion: .angry),
    ]

    // MARK: - 装进假仓库

    /// 按「现在」把剧本摊成日记和蛋。日期都是现算的：示范哪天打开，「昨天」就是那天的前一天。
    static func seed(now: Date, calendar: Calendar) -> (posts: [SlimeItem], eggs: [DayEggRecord]) {
        let today = calendar.startOfDay(for: now)
        var posts: [SlimeItem] = []
        var eggs: [DayEggRecord] = []

        // 今天早上那篇。「早上八点半」不一定已经过了（凌晨打开 App），
        // 所以取八点半和「零点到现在的一半」里早的那个 —— 一定在「现在」之前
        let morningAt = today.addingTimeInterval(min(8.5 * 3600, now.timeIntervalSince(today) / 2))
        posts.append(SlimeItem(id: UUID(), content: morning, createdAt: morningAt,
                               emotion: .calm, reply: nil, day: today))

        for past in pastDays {
            guard let day = calendar.date(byAdding: .day, value: -past.daysAgo, to: today) else { continue }
            for entry in past.entries {
                let at = day.addingTimeInterval(TimeInterval(entry.hour * 3600 + entry.minute * 60))
                posts.append(SlimeItem(id: UUID(), content: entry.text, createdAt: at,
                                       emotion: past.emotion, reply: nil, day: day))
            }
            // 蛋要比那天所有日记都新，不然会被判成「过时了、还欠着」，画成「还在孵」
            eggs.append(DayEggRecord(date: day, text: past.egg, emotion: past.emotion,
                                     createdAt: day.addingTimeInterval(23.9 * 3600)))
        }
        return (posts, eggs)
    }

    // MARK: - 母鸡怎么孵

    /// 示范里的「AI 总结」：按这天剩下哪几篇，翻剧本找对应的蛋。
    /// · 今天（有用户写的那篇）→ 今天那颗
    /// · 删完只剩一篇 → 那篇的 `alone`
    /// · 其余（剧本里没有的组合，正常走不到）→ 拿第一篇的开头兜底，不会崩
    static func egg(for entries: [SlimeItem]) -> (text: String, emotion: SlimeEmotion) {
        let texts = Set(entries.map(\.content))
        if texts.contains(diary) { return todayEgg }
        if entries.count == 1 {
            for past in pastDays {
                if let entry = past.entries.first(where: { texts.contains($0.text) }) {
                    return (entry.alone, past.emotion)
                }
            }
        }
        let first = entries.first
        return (String((first?.content ?? "").prefix(14)), first?.emotion ?? .calm)
    }
}
