//
//  TutorialSandbox.swift
//  Slime
//
//  示范用的「假底层」：仓库存在内存里，AI 照剧本念台词。
//
//  真页面（首页、写日记页、日历页）只认协议 —— `PostRepository`、`DayEggStore`、`AIService`…
//  所以把底下换成这几个，页面一行都不用改就能在示范里跑；而示范里写的、孵的、删的：
//  · **不进 Core Data**：假蛋要是进了库，关怀会把它当成真实的一天读进趋势里，检索也会搜到假日记
//  · **不发给 AI**：没有一个字离开手机
//  · 示范结束，这些对象跟着页面一起被释放，没有要清理的残留
//

import Foundation

// MARK: - 日记

/// 内存里一个数组。「这篇算哪天」直接用剧本给的 `day` —— 示范里没有老数据，不用 `dayKey` 那套兼容。
final class InMemoryPostRepository: PostRepository {

    private var items: [SlimeItem]
    private let calendar: Calendar

    /// 新写了一篇。示范靠它知道用户点了「收好」
    var onCreate: (() -> Void)?

    init(items: [SlimeItem], calendar: Calendar = .current) {
        self.items = items
        self.calendar = calendar
    }

    @discardableResult
    func create(content: String) -> SlimeItem {
        let now = Date()
        let item = SlimeItem(id: UUID(), content: content, createdAt: now,
                             emotion: nil, reply: nil, day: calendar.startOfDay(for: now))
        items.append(item)
        onCreate?()
        return item
    }

    func saveAnalysis(id: UUID, emotion: SlimeEmotion?, reply: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let old = items[index]
        items[index] = SlimeItem(id: old.id, content: old.content, createdAt: old.createdAt,
                                 emotion: emotion, reply: reply, day: old.day)
    }

    func entries(on day: Date) -> [SlimeItem] {
        let start = calendar.startOfDay(for: day)
        return items.filter { $0.day == start }.sorted { $0.createdAt < $1.createdAt }
    }

    func entriesByDay(from start: Date, before end: Date) -> [Date: [SlimeItem]] {
        // 跟真仓库同一个约定：每堆按写下的时间升序
        let inRange = items.filter { $0.day >= start && $0.day < end }.sorted { $0.createdAt < $1.createdAt }
        return Dictionary(grouping: inRange, by: \.day)
    }

    func delete(id: UUID) {
        items.removeAll { $0.id == id }
    }

    // 检索那三个：示范里不聊天，用不到
    func recallCandidates(since: Date) -> [RecallCandidate] { [] }
    func postsMissingEmbedding(limit: Int) -> [(id: UUID, content: String)] { [] }
    func saveEmbeddings(_ vectors: [UUID: [Float]]) {}
}

// MARK: - 蛋

final class InMemoryDayEggStore: DayEggStore {

    private var eggs: [Date: DayEggRecord]
    private let calendar: Calendar

    init(eggs: [DayEggRecord], calendar: Calendar = .current) {
        self.eggs = Dictionary(uniqueKeysWithValues: eggs.map { ($0.date, $0) })
        self.calendar = calendar
    }

    func egg(for day: Date) -> DayEggRecord? {
        eggs[calendar.startOfDay(for: day)]
    }

    func eggs(from start: Date, before end: Date) -> [Date: DayEggRecord] {
        eggs.filter { $0.key >= start && $0.key < end }
    }

    func save(text: String, emotion: SlimeEmotion, for day: Date) {
        let date = calendar.startOfDay(for: day)
        // createdAt 记「现在」：EggDebt 靠它跟最后一篇日记比先后，判这颗蛋过没过时
        eggs[date] = DayEggRecord(date: date, text: text, emotion: emotion, createdAt: Date())
    }

    func delete(for day: Date) {
        eggs[calendar.startOfDay(for: day)] = nil
    }
}

// MARK: - 关怀

/// 永远没有关怀。示范里首页上不该冒出一张关怀卡片 —— 那是看了真实的好几天才会说的话。
final class EmptyCareMessageStore: CareMessageStore {
    func active() -> PendingCare? { nil }
    func show(text: String, referencedDates: [Date], now: Date) {}
    func retire(at date: Date) {}
    func lastRetiredAt() -> Date? { nil }
    func recentCares(limit: Int) -> [PastCare] { [] }
    #if DEBUG
    func allForDebug(limit: Int) -> [CareMessageDebugRow] { [] }
    #endif
    func markFirstSeen(id: UUID, at date: Date) {}
}

// MARK: - AI

/// 照剧本念台词的「AI」。写日记回一句、孵蛋给一颗 —— 内容全在 `TutorialScript` 里。
///
/// 故意慢一点（不到一秒）：真 AI 要等，母鸡「在听」「孵着呢」那几个画面也是示范的一部分；
/// 秒回的话一闪就过去了。
final class TutorialAI: AIService, DayEggSummarizing {

    enum Unavailable: Error {
        /// 示范里不聊天（蒙层挡着，点不到聊天入口）
        case chatNotInTutorial
    }

    func analyze(content: String) async throws -> AIAnalysis {
        try? await Task.sleep(nanoseconds: 900_000_000)
        return AIAnalysis(emotion: TutorialScript.diaryEmotion, reply: TutorialScript.reply)
    }

    func summarizeDay(_ entries: [SlimeItem]) async throws -> DayEggSummary {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        let egg = TutorialScript.egg(for: entries)
        return DayEggSummary(text: egg.text, emotion: egg.emotion)
    }

    func chat(messages: [AIChatMessage]) async throws -> String {
        throw Unavailable.chatNotInTutorial
    }

    func chatstream(messages: [AIChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish(throwing: Unavailable.chatNotInTutorial) }
    }
}
