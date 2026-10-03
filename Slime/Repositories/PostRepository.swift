//
//  PostRepository.swift
//  Slime
//
//  Created by shiying on 2026/7/6.
//

import CoreData

/// 日记的存取。**只吐值类型**（`SlimeItem` / `RecallCandidate`），`Post` 这个托管对象出不了这个文件。
///
/// 以前 `fetchAll()` 直接返回 `[Post]`，后果有三个（09-25 改）：
/// · 「Post → SlimeItem、再按天归堆」在 DayEggService 和 SquareViewModel 里各写了一份，几乎逐行相同；
///   「这篇算哪天」的规则（`dayKey ?? startOfDay(createdAt)`）散在 3 个文件 5 处 ——
///   哪天要改成「凌晨 3 点前算前一天」，漏改一处蛋和日记就对不上天
/// · 假仓库必须造出 `Post`，造 `Post` 就得有 Core Data 上下文 ——
///   依赖它的 Service 没法用一个普通数组去单测
/// · 按一次母鸡要拉全表，只为了找今天那几篇
///
/// 其它几个仓库（DayEggStore / CareMessageStore）一直都是这么做的，这里补齐。
protocol PostRepository {
    /// 存一篇还没被 AI 读过的日记：情绪和回复先空着，等 `saveAnalysis` 补。
    /// 写日记是「先存后分析」—— 日记是用户的，不该等 AI 点头才落库。
    ///
    /// **存不进去会抛错**（最常见是手机存储满了），这时这篇不在库里、也不在内存里。
    /// 全 App 只有这一处保存失败要让用户知道：别的失败（AI 的回复、蛋、关怀、聊天）都有地方补救或者无关紧要，
    /// 只有「我写的字没存上」不能悄悄发生
    @discardableResult
    func create(content: String) throws -> SlimeItem
    /// 给已经存下的那篇补上 AI 的分析。那篇已经不在了（被删了）就什么都不做。
    /// `emotion` 为 nil = AI 回了话，但情绪词读不出来 —— 回复照存，情绪留空。
    func saveAnalysis(id: UUID, emotion: SlimeEmotion?, reply: String)

    /// 某一天的日记，按写下的时间升序。
    func entries(on day: Date) -> [SlimeItem]
    /// [start, end) 这几天的日记，按天归好堆（key = 那天零点），每堆按写下的时间升序。
    /// 没写日记的天不在字典里。
    func entriesByDay(from start: Date, before end: Date) -> [Date: [SlimeItem]]

    func delete(id: UUID)

    func recallCandidates(since: Date) -> [RecallCandidate]
    func postsMissingEmbedding(limit: Int) -> [(id: UUID, content: String)]
    func saveEmbeddings(_ vectors: [UUID: [Float]])
}

extension PostRepository {
    /// 全部日记，按天归好堆。广场页要从最早那篇一直画到今天，所以要全量。
    ///
    /// 写在协议扩展里而不是协议本身：它只是 `entriesByDay` 的一种调法，
    /// 假仓库不用多实现一个方法。
    func allEntriesByDay() -> [Date: [SlimeItem]] {
        entriesByDay(from: .distantPast, before: .distantFuture)
    }
}

final class CoreDataPostRepository: PostRepository {

    private let context: NSManagedObjectContext
    /// 「这篇算哪天」用的日历。存和读必须是同一个，所以跟仓库绑在一起
    private let calendar: Calendar

    //依赖注入 默认用共享栈的主context
    init(context: NSManagedObjectContext = CoreDataStack.shared.viewContext,
         calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    @discardableResult
    func create(content: String) throws -> SlimeItem {
        let post = Post(context: context)
        post.id = UUID()
        post.content = content
        post.createdAt = Date()
        // 存的是「今天是几月几号」，不是「今天零点那个时刻」—— 换了时区也认得出是哪天（见 DayStamp）
        post.dayKey = DayStamp.stored(post.createdAt, in: calendar.timeZone)
        // emotion / reply 故意不写，留 nil = 「AI 还没读过」。
        // 模型里 emotion 已经没有默认值了，不写就真的是空 —— 以前这里不写会被填成 calm。
        // 落盘。存不进去就撤回、抛给页面 —— 以前这里只 print，页面照样显示「收好了」
        try context.saveOrRollback()
        return item(post)
    }

    func saveAnalysis(id: UUID, emotion: SlimeEmotion?, reply: String) {
        let request = Post.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        // 按 id 重新查：中间隔着一次网络等待，那篇可能已经被删了，查不到就算了。
        guard let post = try? context.fetch(request).first else { return }
        post.emotion = emotion?.rawValue
        post.reply = reply
        saveIfNeeded()
    }

    func entries(on day: Date) -> [SlimeItem] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return entriesByDay(from: start, before: end)[start] ?? []
    }

    func entriesByDay(from start: Date, before end: Date) -> [Date: [SlimeItem]] {
        let request = Post.fetchRequest()
        request.predicate = dayRange(from: start, before: end)
        // 升序取回来，归堆之后每堆天然就是按时间排好的 —— Dictionary(grouping:) 保留原顺序
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Post.createdAt, ascending: true)]
        do {
            let posts = try context.fetch(request)
            return Dictionary(grouping: posts.map(item), by: \.day)
        } catch {
            print("查询失败： \(error)")
            return [:]
        }
    }

    func delete(id: UUID) {
        let request = Post.fetchRequest()

        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1

        if let post = try? context.fetch(request).first {
            context.delete(post)
            saveIfNeeded()
        }
    }

    func recallCandidates(since: Date) -> [RecallCandidate] {
        let request = Post.fetchRequest()
        request.predicate = NSPredicate(format: "createdAt >= %@", since as NSDate)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Post.createdAt, ascending: false)]

        return ((try? context.fetch(request)) ?? []).map { post in
            RecallCandidate(
                document: RecallDocument(
                    id: post.id,
                    // 用「算哪天」而不是 createdAt：命中之后要按「哪一天」取回整天的内容
                    date: day(of: post),
                    text: post.content,
                    emotion: post.slimeEmotion),
                vector: post.embedding?.vectorFloats)
        }
    }

    func postsMissingEmbedding(limit: Int) -> [(id: UUID, content: String)] {
        let request = Post.fetchRequest()
        request.predicate = NSPredicate(format: "embedding == nil")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Post.createdAt, ascending: false)]
        request.fetchLimit = limit
        return ((try? context.fetch(request)) ?? []).map { ($0.id, $0.content) }
    }

    func saveEmbeddings(_ vectors: [UUID: [Float]]) {
        guard !vectors.isEmpty else { return }
        let request = Post.fetchRequest()
        // 一次把这批全查回来。**别在循环里一篇一篇查** —— 两百篇就是两百次查询。
        request.predicate = NSPredicate(format: "id IN %@", Array(vectors.keys))
        for post in (try? context.fetch(request)) ?? [] {
            post.embedding = vectors[post.id]?.vectorData
        }
        saveIfNeeded()
    }

    // MARK: - 「这篇算哪天」—— 全项目只有这里回答这个问题

    /// 这篇算哪一天：**当前时区**那一天的零点。
    ///
    /// dayKey 存的是日历日期（见 `DayStamp`），读出来在这里换成当前时区的零点 ——
    /// 上层拿它跟 `calendar.startOfDay(for:)` 比，换了时区照样对得上。
    /// 以前直接把 dayKey 交出去，那是「写的时候那个时区的零点」，换了时区一天都对不上（10-02 修）。
    ///
    /// dayKey 是 nil 的老日记，启动时的 `DayStampMigration` 已经补上了；这里的兜底防的是哪条路漏写
    private func day(of post: Post) -> Date {
        guard let dayKey = post.dayKey else { return calendar.startOfDay(for: post.createdAt) }
        return DayStamp.local(dayKey, in: calendar.timeZone)
    }

    /// 「算哪天」落在 [start, end) 里的日记。start / end 是当前时区的某天零点。
    ///
    /// 库里的 dayKey 是新存法，所以两头先换成新存法再比 —— 拿本地零点直接比的话，
    /// 不在 UTC+0 的人会整片错开。
    ///
    /// 后半句捞 dayKey 是 nil 的：迁移之后正常不会有，留着兜底 ——
    /// 只写前半句的话，没 dayKey 的日记会从广场上整片消失，不报错、只是看不见。
    /// 区间两头都是零点时，「startOfDay(createdAt) 落在区间里」和「createdAt 落在区间里」是一回事。
    private func dayRange(from start: Date, before end: Date) -> NSPredicate {
        let storedStart = DayStamp.stored(start, in: calendar.timeZone)
        let storedEnd = DayStamp.stored(end, in: calendar.timeZone)
        return NSPredicate(format: "(dayKey >= %@ AND dayKey < %@) OR (dayKey == nil AND createdAt >= %@ AND createdAt < %@)",
                           storedStart as NSDate, storedEnd as NSDate, start as NSDate, end as NSDate)
    }

    /// 托管对象变成值类型的唯一出口。
    private func item(_ post: Post) -> SlimeItem {
        SlimeItem(id: post.id, content: post.content, createdAt: post.createdAt,
                  emotion: post.slimeEmotion,
                  reply: post.reply, day: day(of: post))
    }

    /// 有改动，把内容写进磁盘。存不进去就撤回（见 `saveOrRollback`），不往上抛：
    /// 补分析、删日记、存向量失败都不值得打扰用户 —— 撤回之后库里还是改之前的样子，界面刷新时照实显示
    private func saveIfNeeded() {
        do {
            try context.saveOrRollback()
        } catch {
            print("保存失败，已撤回: \(error)")
        }
    }
}
