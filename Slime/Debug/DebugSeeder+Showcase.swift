//
//  DebugSeeder+Showcase.swift
//  Slime
//
//  App Store 截图用的数据。启动参数 -SeedShowcase 触发。
//

#if DEBUG
import CoreData

extension DebugSeeder {

    /// 把新手示范那套剧本（`TutorialScript`）写进测试库：最近十天 + 一个多月前六天，六种情绪都有。
    ///
    /// 为什么复用示范数据、不另写一份：那套是专门写过的，内容轻松、情绪各不相同，
    /// 月历上铺开是一片不同颜色的蛋 —— 正好是商品页想给人看的样子。
    /// 今天只有早上那一篇、没蛋：截图时自己写一篇、按住母鸡孵，拿到真的 AI 回复和总结。
    ///
    /// 会清库（连关怀和检查日志一起）。只在测试库上生效。
    static func seedShowcase(calendar: Calendar = .current,
                             context: NSManagedObjectContext = CoreDataStack.shared.viewContext) {
        guard guardTestStore() else { return }
        wipeAll()

        let seed = TutorialScript.seed(now: Date(), calendar: calendar)
        for item in seed.posts {
            let post = Post(context: context)
            post.id = item.id
            post.content = item.content
            post.createdAt = item.createdAt
            post.dayKey = DayStamp.stored(item.day, in: .current)   // 归堆靠它，别漏。存法见 DayStamp
            post.emotion = item.emotion?.rawValue
            post.reply = item.reply
        }
        // 刚清过库，每天一定还没有蛋，直接建不会插出第二颗
        for record in seed.eggs {
            let egg = DayEgg(context: context)
            egg.date = DayStamp.stored(record.date, in: .current)
            egg.text = record.text
            egg.emotion = record.emotion.rawValue
            egg.createdAt = record.createdAt       // 剧本里已经保证晚于那天最后一篇，EggDebt 不会判欠
        }

        // 剧本只铺了最近十天和一个多月前那六天（够示范用），月历上会空出一大片。
        // 截图要的是「一整个月都有蛋」，所以把 11~31 天前剧本没占的日子，轮流拿剧本里的日子补上
        let today = calendar.startOfDay(for: Date())
        let taken = Set(TutorialScript.pastDays.map(\.daysAgo))
        var filled = 0
        for daysAgo in 11...31 where !taken.contains(daysAgo) {
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) else { continue }
            let source = TutorialScript.pastDays[daysAgo % TutorialScript.pastDays.count]
            for entry in source.entries {
                let post = Post(context: context)
                post.id = UUID()
                post.content = entry.text
                post.createdAt = day.addingTimeInterval(TimeInterval(entry.hour * 3600 + entry.minute * 60))
                post.dayKey = DayStamp.stored(day, in: .current)
                post.emotion = source.emotion.rawValue
            }
            let egg = DayEgg(context: context)
            egg.date = DayStamp.stored(day, in: .current)
            egg.text = source.egg
            egg.emotion = source.emotion.rawValue
            egg.createdAt = day.addingTimeInterval(23.9 * 3600)   // 晚于那天所有日记
            filled += 1
        }

        saveIfNeeded(context)
        print("📸 截图数据：剧本 \(seed.posts.count) 篇日记、\(seed.eggs.count) 颗蛋，另补 \(filled) 天")
    }
}
#endif
