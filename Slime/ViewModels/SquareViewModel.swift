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
    }

    /// 周条的一页。`selected` 只在选中日**落在这一页里**时才有值 ——
    /// 这样换选中日时只有涉及的那一两页 hash 变了，Diffable 只重配那几页，
    /// 而不是把 100 多页全当成新数据。
    nonisolated struct Week: Hashable {
        let start: Date
        let days: [Day]
        let selected: Date?
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

    /// 从「最早一篇日记那周」到「本周」，升序。
    /// **最后一个永远是本周** —— 翻不到未来靠的就是这个数组到此为止，没有额外的边界判断。
    private(set) var weeks: [Week] = []

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

    func delete(_ item: SlimeItem) {
        repository.delete(id: item.id)
        loadPosts()
    }

    // MARK: - 组装周条
    
    /// 从 `first` 那一周逐周生成到 `last` 那一周。两个参数都必须是「周的第一天」。
    private func makeWeeks(from first: Date, through last: Date) -> [Week] {
        var result: [Week] = []
        var cursor = first
        while cursor <= last {
            let days = (0..<7).compactMap { offset -> Day? in
                guard let date = calendar.date(byAdding: .day, value: offset, to: cursor) else { return nil }
                return day(for: calendar.startOfDay(for: date))
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
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today) else {
                   weeks = []
                   return
               }

               // fetchAll 是 createdAt 降序（PostRepository:46），所以 last 是最早的一篇
               let earliest = items.last.map { $0.dayKey ?? calendar.startOfDay(for: $0.createdAt) } ?? today
        let monthStart = calendar.dateInterval(of: .month, for: earliest)?.start ?? earliest
               let firstStart = calendar.dateInterval(of: .weekOfYear, for: monthStart)?.start ?? thisWeek.start

               eggs = eggStore.eggs(from: firstStart, before: thisWeek.end)
               weeks = makeWeeks(from: firstStart, through: thisWeek.start)
    }

    private func day(for date: Date) -> Day {
        Day(date: date,
            number: calendar.component(.day, from: date),
            egg: eggs[date],
            hasEntries: !(grouped[date] ?? []).isEmpty,
            isToday: date == today,
            isFuture: date > today,
            needsHatch: needsHatch(date))
    }
    
    func weeksInMonth(ofWeek index: Int) -> [Week] {
            guard let anchor = midday(ofWeek: index),
                  let month = calendar.dateInterval(of: .month, for: anchor),
                  let lastDay = calendar.date(byAdding: .day, value: -1, to: month.end),
                  let first = calendar.dateInterval(of: .weekOfYear, for: month.start)?.start,
                  let last = calendar.dateInterval(of: .weekOfYear, for: lastDay)?.start
            else { return [] }
            return makeWeeks(from: first, through: last)
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
        return ChineseDate.numeral(calendar.component(.month, from: mid)) + "月"
    }

    /// 翻回不是今年的周时才给年份，今年返回 nil —— 平时标题一个字都不多。
    func yearTitle(atWeek index: Int) -> String? {
        guard let mid = midday(ofWeek: index) else { return nil }
        let year = calendar.component(.year, from: mid)
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
