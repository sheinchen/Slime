////
//  SquareViewModel.swift
//  Slime
//
//  Created by shiying on 2026/7/6.
//

import Foundation

/// 广场页的状态机：读日记、按天归堆、驱动周条与选中。
/// 补蛋这件事全部委托给 DayEggService —— 它不再自己碰 AI。
final class SquareViewModel {

    nonisolated struct Day: Hashable {
        let date: Date
        let number: Int
        let egg: DayEggRecord?
        let hasEntries: Bool
        let isToday: Bool
        let isFuture: Bool
        let needsHatch: Bool
        /// 删了一篇、蛋正在重孵。这几秒画一颗没表情的绿壳，见 `rehatching`
        let isRehatching: Bool
        /// 月历里不属于这一页那个月的日子（首行的上月末、末行的下月初）。
        /// 周条里永远是 false —— 周条没有「这一页是哪个月」的概念
        let isOutsideMonth: Bool
    }

    /// 周条的一页。`selected` 只在选中日**落在这一页里**时才有值 ——
    /// 这样换选中日时只有涉及的那一两页 hash 变了，Diffable 只重配那几页，
    /// 而不是把 100 多页全当成新数据。
    nonisolated struct Week: Hashable {
        let start: Date
        let days: [Day]
        let selected: Date?
    }

    /// 月历的一页。`weeks` 固定 6 周，见 `makeMonths`。
    /// 选中信息藏在里面的 Week.selected 里 —— 换选中日时同样只有涉及的一两页 hash 会变。
    nonisolated struct Month: Hashable {
        /// 这个月的 1 号
        let start: Date
        let weeks: [Week]
    }

    // MARK: - 依赖

    private let repository: PostRepository
    private let eggStore: DayEggStore
    private let eggService: DayEggService
    // calendar 和 today 都注入，方便测试
    private let calendar: Calendar
    private let today: Date

    // MARK: - 状态

    private var items: [SlimeItem] = []
    private var grouped: [Date: [SlimeItem]] = [:]
    private var eggs: [Date: DayEggRecord] = [:]

    /// 删了日记、蛋正在重孵的日子。**只影响怎么画**：库里的蛋照样是立刻删的
    /// （断网、App 被杀都不会留下过时的蛋），但这几秒要是照实画成「还在孵」，
    /// 蛋会闪没了再冒出来。所以先画一颗没表情的绿壳顶着，新蛋回来再揭晓。
    private var rehatching: Set<Date> = []

    /// 从「最早一篇日记那周」到「本周」，升序。
    /// **最后一个永远是本周** —— 翻不到未来靠的就是这个数组到此为止，没有额外的边界判断。
    private(set) var weeks: [Week] = []

    /// 月历的全部页：从「最早一篇日记那个月」到「本月」，升序。
    /// 跟 weeks 同一个道理 —— **最后一个永远是本月**，翻不到未来。
    private(set) var months: [Month] = []

    /// 选中哪天。**翻周不动它** —— 所以它可能不在当前显示的那一页里，这是有意的。
    private(set) var selectedDate: Date

    /// 选中那天的日记
    var entries: [SlimeItem] {
        grouped[selectedDate] ?? []
    }

    /// 以前是 `days.first { $0.date == selectedDate }`（从当周里找）。
    /// 现在选中日可能不在显示的那周，只能直接构造。
    var selectedDay: Day {
        day(for: selectedDate)
    }

    /// 周条初次要停的位置
    var currentWeekIndex: Int {
        max(weeks.count - 1, 0)
    }

    var canHatchToday: Bool {
        needsHatch(today)
    }

    /// 判定规则和 DayEggService 共用 EggDebt 那一份，避免两边漂移。
    private func needsHatch(_ day: Date) -> Bool {
        EggDebt.owes(latestEntryAt: grouped[day]?.last?.createdAt, egg: eggs[day])
    }

    /// 默认值给 nil、构造放进 init 体内：默认参数表达式是非隔离的，
    /// 在那里 new 主线程隔离的类型会报错。
    init(repository: PostRepository? = nil,
         eggStore: DayEggStore? = nil,
         eggService: DayEggService? = nil,
         calendar: Calendar = .current,
         today: Date = Date()) {
        self.repository = repository ?? CoreDataPostRepository()
        self.eggStore = eggStore ?? CoreDataDayEggStore()
        self.eggService = eggService ?? DayEggService()
        var cal = calendar
        cal.firstWeekday = 1
        self.calendar = cal
        self.today = cal.startOfDay(for: today)
        self.selectedDate = self.today
    }

    // MARK: - 读数据

    func loadPosts() {
        items = repository.fetchAll().map { post in
            SlimeItem(id: post.id, content: post.content, createdAt: post.createdAt,
                      emotion: SlimeEmotion(rawValue: post.emotion) ?? .calm,
                      reply: post.reply, dayKey: post.dayKey)
        }

        // 日记按日期归堆
        grouped = Dictionary(grouping: items) {
            $0.dayKey ?? calendar.startOfDay(for: $0.createdAt)
        }
        // 每堆按时间顺序
        for (day, list) in grouped {
            grouped[day] = list.sorted { $0.createdAt < $1.createdAt }
        }
        rebuildWeeks()
    }

    func select(_ day: Day) {
        selectedDate = day.date
        // selected 变了，weeks 里那一两页的 hash 要跟着变，Diffable 才知道要重画高亮
        rebuildWeeks()
    }
    
    func resetToToday() {
        guard selectedDate != today else { return }
        selectedDate = today
        rebuildWeeks()
    }

    /// 删一篇日记，并让那天的蛋作废。同步 —— 返回时蛋已经没了。
    /// 「删日记蛋要作废」这条规则在 DayEggService 里，VM 只转发。
    func delete(_ item: SlimeItem) {
        let day = dayKey(of: item)
        // 过去的天、删完还剩日记 → 马上要重孵。先标上，下面这次 loadPosts 就画成过渡蛋。
        // （grouped 这会儿还没刷新，里面还算着要删的这篇，所以是 > 1）
        // 今天不标：今天的蛋要用户自己按母鸡，删完就是回到母鸡
        if day < today, (grouped[day]?.count ?? 0) > 1 {
            rehatching.insert(day)
        }
        repository.delete(id: item.id)
        eggService.invalidate(day)
        loadPosts()
    }

    /// 删完之后把过去那天的蛋补回来。
    /// - Returns: 界面要不要再刷一次。成功（新蛋回来了）和失败（撤掉过渡蛋、画回「还在孵」）都要；
    ///   今天、删光了的天没标过过渡蛋，什么都没变。
    func rehatchAfterDelete(_ item: SlimeItem) async -> Bool {
        let day = dayKey(of: item)
        guard rehatching.contains(day) else { return false }
        // 成败都一样处理：撤掉标记重读一遍。成功读到新蛋，失败读到「没蛋」→ 画回「还在孵」
        _ = await eggService.rehatch(day)
        rehatching.remove(day)
        loadPosts()                      // loadPosts → rebuildWeeks 会重读蛋、重算标记
        return true
    }

    /// 跟 grouped 的归堆口径保持一致
    private func dayKey(of item: SlimeItem) -> Date {
        item.dayKey ?? calendar.startOfDay(for: item.createdAt)
    }

    // MARK: - 组装周条
    
    /// 从 `first` 那一周逐周生成到 `last` 那一周。两个参数都必须是「周的第一天」。
    private func makeWeeks(from first: Date, through last: Date, inMonth month: Date? = nil) -> [Week] {
        var result: [Week] = []
        var cursor = first
        while cursor <= last {
            let days = (0..<7).compactMap { offset -> Day? in
                guard let date = calendar.date(byAdding: .day, value: offset, to: cursor) else { return nil }
                return day(for: calendar.startOfDay(for: date), inMonth: month)
            }
            result.append(Week(
                start: cursor,
                days: days,
                selected: days.contains { $0.date == selectedDate } ? selectedDate : nil
            ))
            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    /// 一次算出**全部**周。看着重，其实全是内存字典查询 ——
    /// 换来的是周条可以做成一个普通的横向分页列表，
    /// VM 不用维护「现在是第几周」，也就不会出现 VM 和 scrollView 两份真相。
    private func rebuildWeeks() {
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today),
              let thisMonth = calendar.dateInterval(of: .month, for: today)?.start else {
            weeks = []
            months = []
            return
        }

        // fetchAll 是 createdAt 降序（PostRepository:46），所以 last 是最早的一篇
        let earliest = items.last.map { $0.dayKey ?? calendar.startOfDay(for: $0.createdAt) } ?? today
        let monthStart = calendar.dateInterval(of: .month, for: earliest)?.start ?? earliest
        let firstStart = calendar.dateInterval(of: .weekOfYear, for: monthStart)?.start ?? thisWeek.start

        eggs = eggStore.eggs(from: firstStart, before: thisWeek.end)
        weeks = makeWeeks(from: firstStart, through: thisWeek.start)
        months = makeMonths(from: monthStart, through: thisMonth)
    }

    /// 月历的每一页。从 `first` 那个月逐月生成到 `last` 那个月，两个参数都必须是「月的 1 号」。
    ///
    /// 每页**固定 6 周**（6×7 = 42 格）：从 1 号所在的周起连数 6 周。
    /// 只跨 5 周的月份，多出来那行就是下个月的头几天 —— 换来的是每页一样高。
    private func makeMonths(from first: Date, through last: Date) -> [Month] {
        var result: [Month] = []
        var cursor = first
        while cursor <= last {
            guard let gridStart = calendar.dateInterval(of: .weekOfYear, for: cursor)?.start,
                  let gridLast = calendar.date(byAdding: .weekOfYear, value: 5, to: gridStart)
            else { break }
            result.append(Month(start: cursor,
                                weeks: makeWeeks(from: gridStart, through: gridLast, inMonth: cursor)))
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    /// - Parameter month: 月历用，传那一页的 1 号；周条不传
    private func day(for date: Date, inMonth month: Date? = nil) -> Day {
        Day(date: date,
            number: calendar.component(.day, from: date),
            egg: eggs[date],
            hasEntries: !(grouped[date] ?? []).isEmpty,
            isToday: date == today,
            isFuture: date > today,
            needsHatch: needsHatch(date),
            isRehatching: rehatching.contains(date),
            isOutsideMonth: month.map { !calendar.isDate(date, equalTo: $0, toGranularity: .month) } ?? false)
    }
    
    /// 周条的第 index 周属于月历的第几页。按周四算，跟标题同一个口径 ——
    /// 所以展开那一下标题不会变。
    ///
    /// 返回 nil 只有一种情况：最早那一周的周四落在上个月（比如 5 月 1 号是周五，
    /// 那一周的周四是 4/30），而 months 是从 5 月开始的。
    func monthIndex(ofWeek index: Int) -> Int? {
        guard let mid = midday(ofWeek: index) else { return nil }
        return months.firstIndex { calendar.isDate($0.start, equalTo: mid, toGranularity: .month) }
    }

    /// 月历收起时，周条该停在哪一周。
    ///
    /// 原则是**收起那一下标题不能跳** —— 所以只在「按周四算属于这个月」的周里挑，顺序是：
    ///   ① 周条原来停的那周：展开又收起、中间什么都没干，就该什么都没发生
    ///   ② 选中日所在的周：收起后高亮圈看得见
    ///   ③ 这个月的第一周
    /// 三条排成一个候选队列，谁先满足就用谁 —— ③ 就是「从头扫一遍所有周」。
    func weekIndex(forMonth month: Int, current: Int) -> Int {
        let candidates = [current, weekIndex(containing: selectedDate)] + weeks.indices
        return candidates.first { monthIndex(ofWeek: $0) == month } ?? current
    }

    //月历选完日期要跳周条
    func weekIndex(containing date: Date) -> Int {
        let target = calendar.startOfDay(for: date)
        return weeks.firstIndex { Week in
            Week.days.contains{ $0.date == target }
        } ?? 0
    }
    

    // MARK: - 标题

    /// 一周可能跨月（8/31–9/6）。取**周四**所在的月 —— 七天里的第四天，
    /// 也就是这周占天数多的那个月。标题在月中翻转，不会刚过一号就跳。
    func monthTitle(atWeek index: Int) -> String {
        guard let mid = midday(ofWeek: index) else { return "" }
        return monthTitle(of: mid)
    }

    /// 翻回不是今年的周时才给年份，今年返回 nil —— 平时标题一个字都不多。
    func yearTitle(atWeek index: Int) -> String? {
        guard let mid = midday(ofWeek: index) else { return nil }
        return yearTitle(of: mid)
    }

    /// 月历那边的标题。一页就是一个整月，不用像周那样挑周四
    func monthTitle(atMonth index: Int) -> String {
        guard months.indices.contains(index) else { return "" }
        return monthTitle(of: months[index].start)
    }

    func yearTitle(atMonth index: Int) -> String? {
        guard months.indices.contains(index) else { return nil }
        return yearTitle(of: months[index].start)
    }

    private func monthTitle(of date: Date) -> String {
        ChineseDate.numeral(calendar.component(.month, from: date)) + "月"
    }

    private func yearTitle(of date: Date) -> String? {
        let year = calendar.component(.year, from: date)
        guard year != calendar.component(.year, from: today) else { return nil }
        return String(year)
    }

    private func midday(ofWeek index: Int) -> Date? {
        guard weeks.indices.contains(index) else { return nil }
        return calendar.date(byAdding: .day, value: 3, to: weeks[index].start)
    }

    // MARK: - 补蛋（全部委托给 DayEggService，没变）

    func prefetchTodaySummary() {
        eggService.prefetchToday()
    }

    @discardableResult
    func finishTodaySummary() async throws -> DayEggSummary {
        let summary = try await eggService.finishToday()
        loadPosts()
        return summary
    }
}
