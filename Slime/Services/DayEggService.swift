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

    /// 已经在路上的今日总结请求，连同它是基于哪几篇日记发的。prefetch 存进来，finish 取走。
    private var todayTask: (basis: [UUID], task: Task<DayEggSummary, Error>)?

    /// 依赖全部必填，**不给默认值**（09-25 去掉的）。
    ///
    /// 它有状态（正在孵的天、在路上的预取、重试冷却），「组合根只建一个」是正确性的前提 ——
    /// 第二个实例的防重入跟第一个互不相识，同一天会被孵两次。以前三个依赖都有默认值，
    /// 随手写一句 `DayEggService()` 就能悄悄多出一个，而且那个实例直连真 AI，`-StubAI` 管不到它。
    /// `calendar` 是个值、没有状态，留着默认。
    init(posts: PostRepository,
         eggs: DayEggStore,
         summarizer: DayEggSummarizing,
         calendar: Calendar = .current) {
        self.posts = posts
        self.eggs = eggs
        self.summarizer = summarizer
        self.calendar = calendar
    }

    // MARK: - 补过去欠的

    /// 把窗口内所有欠蛋的**过去**天全部补上。今天不自动补 —— 今天要用户自己按母鸡。
    ///
    /// 没网也能写日记（先存后分析），所以断网几天就会攒下几天的债 ——
    /// 以前「写日记要有网、最多只欠一天」的前提已经不成立了。这个循环本来就是按天补的，
    /// 攒多少天都一样，只是有网之后第一次打开会多等几次总结。
    /// 其余的洞也靠它自愈：孵蛋失败、DayEgg 之前的历史数据、用户只在首页写日记从不逛广场。
    /// - Returns: 实际补成功的颗数。
    @discardableResult
    func hatchAllPending(within days: Int = 14, now: Date = Date()) async -> Int {
        let today = calendar.startOfDay(for: now)
        guard let earliest = calendar.date(byAdding: .day, value: -days, to: today) else { return 0 }

        // 库只查一次，别在循环里反复查。日记和蛋用同一个窗口，一一对得上
        let byDay = posts.entriesByDay(from: earliest, before: today)
        let eggMap = eggs.eggs(from: earliest, before: today)

        // 从早到晚补，时间线才不会中间留洞
        let pending = byDay.keys
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
    ///
    /// 调完之后 todayTask 只有两种状态：nil，或者**基于今天现在这几篇**的请求。
    /// 按到一半松手、去写了一篇（或删了一篇）再回来按，手上那份就过时了 ——
    /// 拿它落库的话，蛋会漏掉新写的那篇；而且蛋比那篇晚，EggDebt 判不欠，永远补不回来。
    /// 所以每次都比一下「基于哪几篇」，对不上就作废重发。重复调用仍然安全。
    ///
    /// **失败的预取不留着**：按到一半时没网 → 松手 → 网好了再按满，
    /// 不能直接拿到这个旧的失败、白白「没孵出来」一次。
    func prefetchToday(now: Date = Date()) {
        let today = calendar.startOfDay(for: now)
        let entries = posts.entries(on: today)
        guard !entries.isEmpty,
              EggDebt.owes(latestEntryAt: entries.last?.createdAt, egg: eggs.egg(for: today))
        else {
            dropTodayTask()                    // 今天没什么可孵的，手上那份也不该留
            return
        }

        let basis = entries.map(\.id)
        guard todayTask?.basis != basis else { return }   // 已经在路上，而且日记没变过

        dropTodayTask()
        let task = Task {
            do {
                return try await summarizer.summarizeDay(entries)
            } catch {
                // basis 对得上才清 —— 被 dropTodayTask 换掉的旧请求也会走到这儿（取消），别误清新的那份
                if todayTask?.basis == basis { todayTask = nil }
                throw error
            }
        }
        todayTask = (basis, task)
    }

    /// 等 prefetch 的结果并落库。没 prefetch 过会就地补发一次，所以单独调它也是对的。
    /// 开头那次 prefetchToday 顺带把「基于的日记已经变了」的旧请求换掉。
    @discardableResult
    func finishToday(now: Date = Date()) async throws -> DayEggSummary {
        prefetchToday(now: now)
        guard let current = todayTask else { throw EggError.nothingToSummarize }
        defer { todayTask = nil }              // 无论成败都清掉，失败后能重按
        let summary = try await current.task.value

        // 等总结的这段时间，日记可能变了：切去首页写了一篇、在广场删了一篇。
        // 跟预取那条是同一个坑，只是发生在「等」的中途 —— 拿过时的总结落库，
        // 蛋会漏掉新写的 / 带着删掉的内容，而且蛋比日记新，EggDebt 判不欠，再也补不回来。
        // 所以落库前再对一次「基于哪几篇」，对不上就按现在的日记重孵（重新走一遍本函数）。
        let today = calendar.startOfDay(for: now)
        guard posts.entries(on: today).map(\.id) == current.basis else {
            return try await finishToday(now: now)
        }
        // 存不上就抛 —— 跟「没孵出来」走同一条路，母鸡说「等会儿再按我试试」
        try eggs.save(text: summary.text, emotion: summary.emotion, for: today)
        return summary
    }

    // MARK: - 删日记之后

    /// 删了日记，那天的蛋作废。蛋是当天日记的摘要缓存，源头变了缓存必须失效。
    /// 之后交给 EggDebt：还有日记就判「欠」，删光了就什么都不欠 —— 孤儿蛋就是这么没的。
    ///
    /// 同步执行：调用方紧接着就要刷新界面，得让它立刻看到蛋没了。
    ///
    /// 今天的预取不用在这儿管：下次按母鸡时 prefetchToday 会发现「基于的日记」对不上，自己作废重发。
    func invalidate(_ day: Date) {
        eggs.delete(for: day)
    }

    /// 作废之后立刻把过去那天的蛋补回来。
    /// 不等下次打开 App：`hatchAllPending` 只管 14 天内，更早的天会永远停在「还在孵」。
    /// 今天不补 —— 今天的蛋永远是用户按母鸡按出来的。
    /// - Returns: 补成功了没有。调用方据此决定要不要再刷一次界面。
    func rehatch(_ day: Date, now: Date = Date()) async -> Bool {
        guard day < calendar.startOfDay(for: now) else { return false }
        let entries = posts.entries(on: day)
        guard !entries.isEmpty else { return false }
        // 用户刚动手删的，不受 30 秒重试冷却限制
        return await hatch(day, entries: entries, respectsCooldown: false)
    }

    // MARK: - 私有

    /// 作废手上的预取。cancel 只是通知网络请求可以停了（协作式取消，停不停看它自己）；
    /// 真正保证它不会被拿去落库的是置 nil。
    private func dropTodayTask() {
        todayTask?.task.cancel()
        todayTask = nil
    }

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
            try eggs.save(text: summary.text, emotion: summary.emotion, for: day)
            return true
        } catch {
            return false
        }
    }

    enum EggError: Error {
        case nothingToSummarize
    }
}
