//
//  TutorialSandboxTests.swift
//  SlimeTests
//
//  示范的假数据和假底层。
//
//  剧本（TutorialFlow）有几条前提是靠示范数据撑着的：今天写完正好两篇（才有下一张可翻）、
//  过去每天正好两篇且蛋是新的（点哪天都能删、删完能重孵）。数据一改，前提可能悄悄不成立 ——
//  示范就会在那一步卡住。这里把前提一条条锁住。
//

import XCTest
@testable import Slime

/// 碰 App 里的类：一律 `@MainActor` + async（CLAUDE.md §5）
@MainActor
final class TutorialSandboxTests: XCTestCase {

    private let calendar = Calendar.current

    // MARK: - 示范数据的前提

    func test_今天_只有早上一篇_还没有蛋() async {
        let now = Date()
        let seed = TutorialScript.seed(now: now, calendar: calendar)
        let today = calendar.startOfDay(for: now)

        let todays = seed.posts.filter { $0.day == today }
        XCTAssertEqual(todays.count, 1, "用户再写一篇就是两篇，「左右拖卡片」才有下一张")
        XCTAssertLessThan(todays[0].createdAt, now, "早上那篇不能写在「现在」之后")
        XCTAssertFalse(seed.eggs.contains { $0.date == today }, "今天的蛋要用户自己按母鸡孵")
    }

    /// 凌晨打开 App：「早上八点半」还没到，那篇也得落在现在之前
    func test_凌晨打开_早上那篇也在现在之前() async {
        let today = calendar.startOfDay(for: Date())
        let justAfterMidnight = today.addingTimeInterval(10 * 60)
        let seed = TutorialScript.seed(now: justAfterMidnight, calendar: calendar)
        let morning = seed.posts.first { $0.day == today }
        XCTAssertNotNil(morning)
        XCTAssertLessThan(morning!.createdAt, justAfterMidnight)
    }

    func test_过去每天_正好两篇_能删_而且蛋是新的() async {
        let seed = TutorialScript.seed(now: Date(), calendar: calendar)
        let today = calendar.startOfDay(for: Date())
        let byDay = Dictionary(grouping: seed.posts.filter { $0.day < today }, by: \.day)

        XCTAssertEqual(byDay.count, TutorialScript.pastDays.count)
        for (day, entries) in byDay {
            XCTAssertTrue(TutorialFlow.canDelete(isToday: false, entryCount: entries.count), "\(day)")
            let egg = seed.eggs.first { $0.date == day }
            XCTAssertNotNil(egg, "\(day) 没有蛋")
            // 蛋比日记旧 = 过时了，日历页会把那天画成「还在孵」，而不是一颗蛋
            XCTAssertFalse(EggDebt.owes(latestEntryAt: entries.map(\.createdAt).max(), egg: egg), "\(day)")
        }
    }

    /// 「往右滑，翻到上一周」「左右滑，翻到别的月份」两步要有东西可看。
    /// 数据按「几天前」摊开，能不能看到取决于今天是几号、周几 —— 所以把一整年每一天都当成「今天」试一遍：
    /// · 上一周至少有一天有日记（周日打开时本周没有过去的日子，全靠上一周）
    /// · 月历至少两页，而且上个月至少有一颗蛋（只有一页的话翻月那步滑不动）
    func test_不管哪天打开_上一周和上个月都有东西可看() async throws {
        var cal = Calendar.current
        cal.firstWeekday = 1                          // 跟 SquareViewModel 一样，周日是一周第一天
        let jan1 = try XCTUnwrap(cal.date(from: DateComponents(year: 2027, month: 1, day: 1, hour: 12)))

        for offset in 0..<365 {
            let now = try XCTUnwrap(cal.date(byAdding: .day, value: offset, to: jan1))
            let seed = TutorialScript.seed(now: now, calendar: cal)
            let postDays = Set(seed.posts.map(\.day))
            let eggDays = Set(seed.eggs.map(\.date))

            let thisWeek = try XCTUnwrap(cal.dateInterval(of: .weekOfYear, for: now)).start
            let lastWeek = try XCTUnwrap(cal.date(byAdding: .day, value: -7, to: thisWeek))
            XCTAssertTrue(postDays.contains { $0 >= lastWeek && $0 < thisWeek }, "\(now) 上一周是空的")

            let thisMonth = try XCTUnwrap(cal.dateInterval(of: .month, for: now)).start
            let lastMonth = try XCTUnwrap(cal.date(byAdding: .month, value: -1, to: thisMonth))
            XCTAssertTrue(eggDays.contains { $0 >= lastMonth && $0 < thisMonth }, "\(now) 上个月没有蛋")
        }
    }

    // MARK: - 剧本 AI 怎么孵

    func test_今天两篇_孵出今天那颗() async {
        let items = [item(TutorialScript.morning), item(TutorialScript.diary)]
        XCTAssertEqual(TutorialScript.egg(for: items).text, TutorialScript.todayEgg.text)
    }

    /// 删掉一篇之后，按剩下那篇重孵 —— 蛋上的字得是那篇自己的，不能还是两篇合起来的那句
    func test_删完只剩一篇_孵出那篇自己的蛋() async {
        let past = TutorialScript.pastDays[0]
        let egg = TutorialScript.egg(for: [item(past.entries[1].text)])
        XCTAssertEqual(egg.text, past.entries[1].alone)
        XCTAssertEqual(egg.emotion, past.emotion)
    }

    // MARK: - 跟真服务接起来

    /// 整条「写 → 孵 → 删 → 重孵」用真的 DayEggService 跑一遍：假仓库得满足它的所有约定
    func test_写一篇_孵今天_删一篇_那天重孵() async throws {
        let seed = TutorialScript.seed(now: Date(), calendar: calendar)
        let posts = InMemoryPostRepository(items: seed.posts)
        let eggs = InMemoryDayEggStore(eggs: seed.eggs)
        let service = DayEggService(posts: posts, eggs: eggs, summarizer: TutorialAI())
        let today = calendar.startOfDay(for: Date())

        var saved = 0
        posts.onCreate = { saved += 1 }
        posts.create(content: TutorialScript.diary)
        XCTAssertEqual(saved, 1, "示范靠它认「点了收好」")
        XCTAssertEqual(posts.entries(on: today).count, 2)

        let summary = try await service.finishToday()
        XCTAssertEqual(summary.text, TutorialScript.todayEgg.text)
        XCTAssertEqual(eggs.egg(for: today)?.text, TutorialScript.todayEgg.text)

        // 删昨天的第一篇 → 蛋作废 → 按剩下那篇重孵
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))
        let first = try XCTUnwrap(posts.entries(on: yesterday).first)
        posts.delete(id: first.id)
        service.invalidate(yesterday)
        XCTAssertNil(eggs.egg(for: yesterday))

        let rehatched = await service.rehatch(yesterday)
        XCTAssertTrue(rehatched)
        let past = try XCTUnwrap(TutorialScript.pastDays.first { $0.daysAgo == 1 })
        XCTAssertEqual(eggs.egg(for: yesterday)?.text, past.entries[1].alone)
    }

    // MARK: -

    private func item(_ text: String) -> SlimeItem {
        SlimeItem(id: UUID(), content: text, createdAt: Date(), emotion: .calm, reply: nil,
                  day: calendar.startOfDay(for: Date()))
    }
}

/// 每条用一个独立的 UserDefaults suite，不碰 App 真正的 `.standard`
@MainActor
final class UserDefaultsTutorialStoreTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suiteName = "TutorialTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func test_新装的App_没看过() async {
        XCTAssertFalse(UserDefaultsTutorialStore(defaults: defaults).hasFinished)
    }

    /// 存下来的，不是记在内存里：换一个实例（= 下次打开 App）还认
    func test_看过_跨实例保留() async {
        UserDefaultsTutorialStore(defaults: defaults).markFinished()
        XCTAssertTrue(UserDefaultsTutorialStore(defaults: defaults).hasFinished)
    }

    func test_重置之后_再看一遍() async {
        let store = UserDefaultsTutorialStore(defaults: defaults)
        store.markFinished()
        store.reset()
        XCTAssertFalse(store.hasFinished)
    }
}
