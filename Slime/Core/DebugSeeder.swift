//
//  DebugSeeder.swift
//  Slime
//
//  只在 Debug 构建里存在的测试数据播种器。
//

#if DEBUG
import CoreData

/// 造历史数据用的脚手架。
///
/// 为什么需要它：App 正常只往「今天」写日记，所以你造不出
/// 「过去几天有记录」这种状态 —— 而补蛋、主动关照、eval 全都要靠它。
///
/// 为什么直接建实体而不走 PostRepository：
/// 一是 `create` 写死了 `createdAt = Date()`，造不了历史；
/// 二是测试脚手架需要对 dayKey / createdAt 有完全控制权，绕过仓库是正常的；
/// 三是绝不能触发 AI 调用 —— 造 10 天不该打 10 次 API。
///
/// **安全前提**：所有方法都会先检查当前是不是测试库（.testFile / .inMemory）。
/// 在正式库上调用会直接被拒绝并打印警告，一个字节都不会写。
enum DebugSeeder {

    // MARK: - 安全闸

    /// 只有跑在测试库上才放行。
    /// 这是最后一道防线：即使有人在 Debug 构建里误调了播种，
    /// 只要 Scheme 没开 -UseTestStore，就碰不到真数据。
    private static func guardTestStore(_ caller: String = #function) -> Bool {
        switch CoreDataStack.shared.mode {
        case .testFile, .inMemory:
            return true
        case .persistent:
            print("⛔️ \(caller) 被拒绝：当前是正式库。到 Edit Scheme → Run → Arguments 打开 -UseTestStore 再试。")
            return false
        }
    }

    // MARK: - 播种

    /// 从昨天开始往前造，`emotions` 第一个是昨天，依次往前推。
    /// - Parameters:
    ///   - withEggs: 顺便把蛋也孵好。**测补蛋要传 false**，那样才是「有日记没蛋」的欠债状态。
    ///   - entriesPerDay: 每天几篇日记，默认 1。想验「一天多篇」的归堆就调大。
    static func seedHistory(emotions: [SlimeEmotion],
                            withEggs: Bool,
                            entriesPerDay: Int = 1,
                            calendar: Calendar = .current,
                            context: NSManagedObjectContext = CoreDataStack.shared.viewContext) {
        guard guardTestStore() else { return }

        let today = calendar.startOfDay(for: Date())

        for (index, emotion) in emotions.enumerated() {
            let offset = index + 1                       // 1 = 昨天
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }

            var lastEntryAt = day

            for n in 0..<max(1, entriesPerDay) {
                // 当天 10 点起，每篇隔两小时 —— 避开时区边界，也让「那天最新一篇」有明确先后
                guard let at = calendar.date(byAdding: .hour, value: 10 + n * 2, to: day) else { continue }
                lastEntryAt = at

                let post = Post(context: context)
                post.id = UUID()
                post.content = Self.sampleEntry(emotion, dayIndex: index, n: n)
                post.createdAt = at
                post.dayKey = day                        // 归堆靠它，别漏
                post.emotion = emotion.rawValue
                post.reply = "测试数据"
            }

            if withEggs {
                // 先查后建（upsert）。直接 new 会在那天已有蛋时插出第二行，
                // 而 DayEggStore.eggs(from:before:) 用的是 Dictionary(uniqueKeysWithValues:)，
                // 撞 key 会直接 fatalError —— 一进广场页就崩。
                let egg = existingEgg(for: day, in: context) ?? DayEgg(context: context)
                egg.date = day
                egg.text = Self.sampleSummary(emotion, dayIndex: index)
                egg.emotion = emotion.rawValue
                // 必须晚于那天最后一篇日记 —— EggDebt.owes 判的就是 egg.createdAt < latestEntryAt。
                // 写反了会被判成「蛋过时了」，一开 App 就重孵一堆。
                egg.createdAt = lastEntryAt.addingTimeInterval(60)
            }
        }

        saveIfNeeded(context)
        print("🌱 播种 \(emotions.count) 天 × \(entriesPerDay) 篇，withEggs=\(withEggs)")
    }

    /// 只删这颗蛋，日记留着 —— 直接造出「欠蛋」状态，用来验补蛋。
    static func removeEggs(daysBack: Int,
                           calendar: Calendar = .current,
                           context: NSManagedObjectContext = CoreDataStack.shared.viewContext) {
        guard guardTestStore() else { return }

        let today = calendar.startOfDay(for: Date())
        let store = CoreDataDayEggStore(context: context)
        for offset in 1...max(1, daysBack) {
            if let day = calendar.date(byAdding: .day, value: -offset, to: today) {
                store.delete(for: day)
            }
        }
        print("🥚 删掉了过去 \(daysBack) 天的蛋（日记保留）")
    }

    // MARK: - 清空

    /// 把测试库清空：所有日记 + 所有蛋。
    ///
    /// 注意跟以前的区别：以前要靠「【测试】前缀」保护你的真日记，
    /// 现在库本身就是隔离的，可以放心全清 —— 也就不会漏掉手动写的那些。
    static func wipeAll(context: NSManagedObjectContext = CoreDataStack.shared.viewContext) {
        guard guardTestStore() else { return }

        let posts = (try? context.fetch(Post.fetchRequest())) ?? []
        posts.forEach { context.delete($0) }

        let eggs = (try? context.fetch(NSFetchRequest<DayEgg>(entityName: "DayEgg"))) ?? []
        eggs.forEach { context.delete($0) }

        // 关怀那两张表也要清，否则改一次代码只能验一次：
        // ① CareCheck 留着 → lastCheckedAt 是上次那一刻，而播种的蛋 createdAt 都在过去
        //    → 闸门条件①「自上次检查后没有新蛋」直接挡下。
        // ② 上次生成的关怀还挂着 → 闸门第 0 条挡；而播种的蛋触发不了退场
        //    （createdAt 在过去，不满足 > care.createdAt），只能干等 3 天保质期。
        let messages = (try? context.fetch(CareMessage.fetchRequest())) ?? []
        messages.forEach { context.delete($0) }

        let checks = (try? context.fetch(CareCheck.fetchRequest())) ?? []
        checks.forEach { context.delete($0) }

        saveIfNeeded(context)
        print("🧹 清空测试库：\(posts.count) 篇日记、\(eggs.count) 颗蛋、\(messages.count) 条关怀、\(checks.count) 条检查日志")
    }

    /// 一步到位：清空 + 播种。手动测试最常用的入口。
    static func reset(to emotions: [SlimeEmotion],
                      withEggs: Bool,
                      entriesPerDay: Int = 1) {
        wipeAll()
        seedHistory(emotions: emotions, withEggs: withEggs, entriesPerDay: entriesPerDay)
    }

    // MARK: - 像样的测试内容

    /// 蛋的 text 是**唯一发给关怀 AI 的内容**（窗口里的 summary 就是它）。
    /// 用「【测试】3 天前的一天」这种占位符,AI 手上就只剩 emotion 一个真信息 ——
    /// 实测它会直接回 shouldShow: false,并在 pattern 里吐槽「信息仅为测试标签」。
    /// 那样测不出语义判断,只能测出管道通不通。
    private static let summaries: [SlimeEmotion: [String]] = [
        .happy:   ["久违地睡到自然醒,阳光很好", "和朋友吃了顿饭,笑到肚子疼", "小事都挺顺,一整天轻飘飘的"],
        .calm:    ["没什么特别的,把手边的事做完了", "傍晚去河边走了走,风不冷不热", "一个人待着,觉得挺舒服"],
        .sad:     ["方案又被打回来,有点说不出话", "翻到以前的照片,心里空落落的", "跟人说了几句,还是觉得没被听懂"],
        .angry:   ["排队被插了,忍了半天没发作", "同事把锅甩过来,气得手抖", "解释了三遍还是被当耳旁风"],
        .anxious: ["deadline 在后天,进度只走了一半", "消息发出去半天没回,一直在想", "明天要汇报,晚上翻来覆去"],
        .tired:   ["连着加班第四天,回家只想躺着", "开了一整天会,脑子是木的", "身体没病,就是提不起劲"],
    ]

    /// 同一种情绪连着几天时轮换句子,免得时间线读起来像复读机。
    private static func sampleSummary(_ emotion: SlimeEmotion, dayIndex: Int) -> String {
        let list = summaries[emotion] ?? ["平平常常的一天"]
        return list[dayIndex % list.count]
    }

    private static func sampleEntry(_ emotion: SlimeEmotion, dayIndex: Int, n: Int) -> String {
        let base = sampleSummary(emotion, dayIndex: dayIndex)
        return n == 0 ? base : "\(base)(第 \(n + 1) 篇)"
    }

    // MARK: - 私有

    private static func existingEgg(for day: Date, in context: NSManagedObjectContext) -> DayEgg? {
        let request = NSFetchRequest<DayEgg>(entityName: "DayEgg")
        request.predicate = NSPredicate(format: "date == %@", day as NSDate)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    private static func saveIfNeeded(_ context: NSManagedObjectContext) {
        guard context.hasChanges else { return }
        do { try context.save() } catch { print("播种保存失败: \(error)") }
    }
}
#endif
