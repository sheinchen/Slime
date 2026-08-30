//
//  SquareViewModel.swift
//  Slime
//
//  Created by shiying on 2026/7/6.
//

import Foundation


final class SquareViewModel {
    
    struct Day: Hashable {
        let date: Date
        let number: Int
        let egg: DayEggRecord?
        let hasEntries: Bool
        let isToday: Bool
    }
    
    //MARK: - 依赖
    
    private let repository: PostRepository
    private let eggStore: DayEggStore
    private let summarizer: DayEggSummarizing
    //calender和today都注入 方便测试
    private let calendar: Calendar
    private let today: Date
    
    //MARK: - 状态
    
    private var items: [SlimeItem] = []
    private var grouped: [Date: [SlimeItem]] = [:]
    private var eggs: [Date: DayEggRecord] = [:]
    
    private(set) var days: [Day] = []
    private(set) var selectedDate: Date
    
    //防止正在补的帖子的守卫
    private var hatching: Set<Date> = []
    private var lastAttempt: [Date: Date] = [:]
    private let retryCooldown: TimeInterval = 30
    
    //选中那天帖子
    var entries: [SlimeItem] {
        grouped[selectedDate] ?? []
    }
    
    var monthTitle: String {
        ChineseDate.numeral(calendar.component(.month, from: selectedDate)) + "月"
    }
    
    
    var selectedDay: Day? {
        days.first {
            $0.date == selectedDate
        }
    }
    
    var canHatchToday: Bool {
        guard let entries = grouped[today], let latest = entries.last else { return false }
        guard let egg = eggs[today] else { return true }
        return egg.createdAt < latest.createdAt
    }
    
    init(repository: PostRepository = CoreDataPostRepository(),
         eggStore: DayEggStore = CoreDataDayEggStore(),
         summariszer: DayEggSummarizing = DeepSeekAIService(),
         calendar: Calendar = .current,
         today: Date = Date()) {
        self.repository = repository
        self.eggStore = eggStore
        self.summarizer = summariszer
        var cal = calendar
        cal.firstWeekday = 1
        self.calendar = cal
        self.today = cal.startOfDay(for: today)
        self.selectedDate = self.today
    }

    
    func loadPosts() {
        items = repository.fetchAll().map({ post in
            SlimeItem(id: post.id, content: post.content, createdAt: post.createdAt, emotion: SlimeEmotion(rawValue: post.emotion) ?? .calm, reply: post.reply, dayKey: post.dayKey)
        })
        
        //梯子按日期归堆
        grouped = Dictionary(grouping: items) {
            $0.dayKey ?? calendar.startOfDay(for: $0.createdAt)
        }
        //每堆按时间顺序
        for (day, list) in grouped {
            grouped[day] = list.sorted {
                $0.createdAt < $1.createdAt
            }
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
    
    //MARK: - 组装周条
    
    private func rebuildWeek() {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: selectedDate) else {
            days = []
            return
        }
        eggs = eggStore.eggs(from: week.start, before: week.end)
        
        days = (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: week.start ) else { return nil }
            let day = calendar.startOfDay(for: date)
            return Day(date: day, number: calendar.component(.day, from: day), egg: eggs[day],hasEntries: !(grouped[day] ?? []).isEmpty, isToday: day == today)
            
        }
    }
    
    //MARK: - 补蛋
    private func pendingDay() -> Date? {
        grouped.keys.filter { day in
            guard day < today else { return false }
            guard let entries = grouped[day],
                  let latest = entries.last else { return false}
            guard let egg = eggs[day] else { return true }
            return egg.createdAt < latest.createdAt
          
        }.max()
    }
    
    /// 孵一颗蛋。重复调用安全。
    /// - Parameter respectsCooldown: 自动补蛋要守 30 秒冷却(防止失败时反复打 API);
    ///   用户手动按母鸡是明确的意图,不该被冷却挡住。
    private func hatch(_ day: Date, respectsCooldown: Bool = true) async {
        guard !hatching.contains(day) else { return }
        if respectsCooldown,
           let last = lastAttempt[day],
           Date().timeIntervalSince(last) < retryCooldown { return }
        
        hatching.insert(day)
        lastAttempt[day] = Date()
        defer {
            hatching.remove(day)
        }
        
        guard let entries = grouped[day],
              !entries.isEmpty else { return }
        
        do {
            let summary = try await summarizer.summarizeDay(entries)
            eggStore.save(text: summary.text, emotion: summary.emotion, for: day)
            rebuildWeek()
        } catch {
            
        }
    }
    
    func hatchPendingEggIfNeeded() async {
        guard let day = pendingDay() else { return }
        await hatch(day)
    }
    
    func hatchToday() async {
        await hatch(today, respectsCooldown: false)
    }
}

    
