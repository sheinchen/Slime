//
//  SquareViewModel.swift
//  Slime
//
//  Created by shiying on 2026/7/6.
//

import Foundation

/// 广场页的状态机：读日记、按天归堆、驱动周条与选中。
/// 补蛋这件事全部委托给 DayEggService —— 它不再自己碰 AI。
final class SquareViewModel {

    struct Day: Hashable {
        let date: Date
        let number: Int
        let egg: DayEggRecord?
        let hasEntries: Bool
        let isToday: Bool
        let needsHatch: Bool
    }

    // MARK: - 依赖

    private let repository: PostRepository
    private let eggStore: DayEggStore
    private let eggService: DayEggService
    // calendar 和 today 都注入，方便测试
    private let calendar: Calendar
    private let today: Date

    // MARK: - 状态（只剩 UI 要的）

    private var items: [SlimeItem] = []
    private var grouped: [Date: [SlimeItem]] = [:]
    private var eggs: [Date: DayEggRecord] = [:]

    private(set) var days: [Day] = []
    private(set) var selectedDate: Date

    /// 选中那天的日记
    var entries: [SlimeItem] {
        grouped[selectedDate] ?? []
    }

    var monthTitle: String {
        ChineseDate.numeral(calendar.component(.month, from: selectedDate)) + "月"
    }

    var selectedDay: Day? {
        days.first { $0.date == selectedDate }
    }

    var canHatchToday: Bool {
        needsHatch(today)
    }

    /// 数据取自当周缓存（rebuildWeek 会一周七天各调一次，不能每天现查库），
    /// 判定规则则和 DayEggService 共用 EggDebt 那一份，避免两边漂移。
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
        rebuildWeek()
    }

    func select(_ day: Day) {
        selectedDate = day.date
    }

    func delete(_ item: SlimeItem) {
        repository.delete(id: item.id)
        loadPosts()
    }

    // MARK: - 组装周条

    private func rebuildWeek() {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: selectedDate) else {
            days = []
            return
        }
        eggs = eggStore.eggs(from: week.start, before: week.end)

        days = (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: week.start) else { return nil }
            let day = calendar.startOfDay(for: date)
            return Day(date: day,
                       number: calendar.component(.day, from: day),
                       egg: eggs[day],
                       hasEntries: !(grouped[day] ?? []).isEmpty,
                       isToday: day == today,
                       needsHatch: needsHatch(day))
        }
    }

    // MARK: - 补蛋（全部委托给 DayEggService）

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
