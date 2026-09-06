//
//  DayEggService.swift
//  Slime
//

import Foundation

/// 「这天欠不欠一颗蛋」的判定规则。
///
/// 单独拎出来，是因为 DayEggService 和 SquareViewModel 手里的缓存不一样
/// （一个现查库，一个有当周缓存），但判定规则必须只有一份，否则两边会漂移。
/// 标 nonisolated 是因为它是纯函数，不碰任何状态，谁都该能直接调。
nonisolated enum EggDebt {
    static func owes(latestEntryAt: Date?, egg: DayEggRecord?) -> Bool {
        guard let latestEntryAt else { return false }   // 那天没写过 → 不欠
        guard let egg else { return true }              // 有日记没蛋 → 欠
        return egg.createdAt < latestEntryAt            // 蛋比日记旧 → 过时了，欠
    }
}

/// 「蛋」这件事的唯一负责人：把欠的补上、手动孵今天。
///
/// 为什么独立成 Service：
/// 补蛋原本长在 SquareViewModel 里，只有广场页够得着。但主动关怀在首页触发，
/// 而且必须先补完蛋才能跑 —— 缺了最新一天的蛋，AI 看到的就是过时的时间线。
/// 一个要被两个页面共用的能力，不该住在其中一个页面的 ViewModel 里。
@MainActor
final class DayEggService {

    // MARK: - 依赖（全部注入，测试时可换成假的）

    private let posts: PostRepository
    private let eggs: DayEggStore
    private let summarizer: DayEggSummarizing
    private let calendar: Calendar

    // MARK: - 防重入

    /// 正在孵的天。同一天不允许并发孵两次。
    private var hatching: Set<Date> = []
    /// 上次尝试的时刻。失败后 30 秒内不重试，避免没网时反复打 API。
    private var lastAttempt: [Date: Date] = [:]
    private let retryCooldown: TimeInterval = 30

    /// 已经在路上的今日总结请求。prefetch 存进来，finish 取走。
    private var todayTask: Task<DayEggSummary, Error>?

    /// 默认参数表达式是在「非隔离」上下文里求值的，没法在那儿 new 主线程隔离的类型。
    /// 所以默认值给 nil，真正的构造放进 init 体内 —— 这里才是 @MainActor 的。
    init(posts: PostRepository? = nil,
         eggs: DayEggStore? = nil,
         summarizer: DayEggSummarizing? = nil,
         calendar: Calendar = .current) {
        self.posts = posts ?? CoreDataPostRepository()
        self.eggs = eggs ?? CoreDataDayEggStore()
        self.summarizer = summarizer ?? DeepSeekAIService()
        self.calendar = calendar
    }

    // MARK: - 补过去欠的

    /// 把窗口内所有欠蛋的**过去**天全部补上。今天不自动补 —— 今天要用户自己按母鸡。
    ///
    /// 正常情况下最多只欠一天：写日记要有网，没网就写不进新债，债务的产生和偿还
    /// 被同一个条件卡住。所以这个循环几乎总是跑 0 或 1 次，成本可以忽略。
    /// 它存在是为了自愈那些异常累积的洞 —— 孵蛋失败、DayEgg 之前的历史数据、
    /// 用户只在首页写日记从不逛广场。
    /// - Returns: 实际补成功的颗数。
    @discardableResult
    func hatchAllPending(within days: Int = 14, now: Date = Date()) async -> Int {
        let today = calendar.startOfDay(for: now)
        guard let earliest = calendar.date(byAdding: .day, value: -days, to: today) else { return 0 }

        // 库只查一次，别在循环里反复查
        let byDay = grouped()
        let eggMap = eggs.eggs(from: earliest, before: today)

        // 从早到晚补，时间线才不会中间留洞
        let pending = byDay.keys
            .filter { $0 >= earliest && $0 < today }
            .filter { EggDebt.owes(latestEntryAt: byDay[$0]?.last?.createdAt, egg: eggMap[$0]) }
            .sorted()

        var hatched = 0
        for day in pending {
            guard let entries = byDay[day] else { continue }
            if await hatch(day, entries: entries, respectsCooldown: true) { hatched += 1 }
        }
        return hatched
    }

    // MARK: - 今天（手动孵）

    /// 提前发起今天的总结 —— 用户按母鸡按到一半就调，让按压动画盖住网络延迟。
    /// 重复调用安全：已经在路上就不会再发一次。
    func prefetchToday(now: Date = Date()) {
        guard todayTask == nil else { return }
        let today = calendar.startOfDay(for: now)
        guard let entries = grouped()[today], !entries.isEmpty else { return }
        guard EggDebt.owes(latestEntryAt: entries.last?.createdAt,
                           egg: eggs.egg(for: today)) else { return }
        todayTask = Task { try await summarizer.summarizeDay(entries) }
    }

    /// 等 prefetch 的结果并落库。没 prefetch 过会就地补发一次，所以单独调它也是对的。
    @discardableResult
    func finishToday(now: Date = Date()) async throws -> DayEggSummary {
        prefetchToday(now: now)
        guard let task = todayTask else { throw EggError.nothingToSummarize }
        defer { todayTask = nil }              // 无论成败都清掉，失败后能重按
        let summary = try await task.value
        eggs.save(text: summary.text, emotion: summary.emotion, for: calendar.startOfDay(for: now))
        return summary
    }

    // MARK: - 私有

    /// 孵一颗。重复调用安全。
    /// 失败返回 false 而不抛 —— 批量补蛋时不该被某一天的失败打断后面几天。
    private func hatch(_ day: Date, entries: [SlimeItem], respectsCooldown: Bool) async -> Bool {
        guard !hatching.contains(day) else { return false }
        if respectsCooldown,
           let last = lastAttempt[day],
           Date().timeIntervalSince(last) < retryCooldown { return false }

        hatching.insert(day)
        lastAttempt[day] = Date()
        defer { hatching.remove(day) }         // 不管怎么退出都摘掉标记，免得这天被永久锁死

        do {
            let summary = try await summarizer.summarizeDay(entries)
            eggs.save(text: summary.text, emotion: summary.emotion, for: day)
            return true
        } catch {
            return false
        }
    }

    /// 全部日记按天归堆，每堆按时间升序。
    private func grouped() -> [Date: [SlimeItem]] {
        let items = posts.fetchAll().map {
            SlimeItem(id: $0.id, content: $0.content, createdAt: $0.createdAt,
                      emotion: SlimeEmotion(rawValue: $0.emotion) ?? .calm,
                      reply: $0.reply, dayKey: $0.dayKey)
        }
        var byDay = Dictionary(grouping: items) {
            $0.dayKey ?? calendar.startOfDay(for: $0.createdAt)
        }
        for (day, list) in byDay {
            byDay[day] = list.sorted { $0.createdAt < $1.createdAt }
        }
        return byDay
    }

    enum EggError: Error {
        case nothingToSummarize
    }
}
