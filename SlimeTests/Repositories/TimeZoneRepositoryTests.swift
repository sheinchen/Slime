//
//  TimeZoneRepositoryTests.swift
//  SlimeTests
//
//  换时区之后，日记和蛋还找不找得到（10-02 的 bug）。
//
//  这组故意碰 Core Data（内存库），跟「单测只测纯函数」那条不一样 ——
//  bug 就出在「库里怎么存 ↔ 上层怎么比」这道缝上，只测 DayStamp 的纯函数测不到这道缝。
//  @MainActor + async：仓库和 Service 都是主线程隔离的类，见 CLAUDE.md §5。
//

import XCTest
import CoreData
@testable import Slime

@MainActor
final class TimeZoneRepositoryTests: XCTestCase {

    private let brisbane = TimeZone(identifier: "Australia/Brisbane")!   // +10
    private let shanghai = TimeZone(identifier: "Asia/Shanghai")!        // +8
    private let losAngeles = TimeZone(identifier: "America/Los_Angeles")! // -7

    private func calendar(_ tz: TimeZone) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = tz
        return c
    }

    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, in tz: TimeZone) -> Date {
        calendar(tz).date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    /// 干净的内存库。模型借共享栈那份：同一个进程里加载两份模型，Post(context:) 会认不出实体
    private func freshContext() -> NSManagedObjectContext {
        let model = CoreDataStack.shared.persistentContainer.managedObjectModel
        let container = NSPersistentContainer(name: "Slime", managedObjectModel: model)
        container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        container.loadPersistentStores { _, error in XCTAssertNil(error) }
        return container.viewContext
    }

    // MARK: - 换时区：仓库读得到

    func test_在一个时区写的日记_换个时区读_还在那一天() async throws {
        let context = freshContext()
        let written = try CoreDataPostRepository(context: context, calendar: calendar(brisbane)).create(content: "在布里斯班写的")
        let writtenDay = calendar(brisbane).dateComponents([.year, .month, .day], from: written.createdAt)

        for reader in [shanghai, losAngeles, brisbane] {
            let repo = CoreDataPostRepository(context: context, calendar: calendar(reader))
            let sameDayThere = calendar(reader).date(from: writtenDay)!
            XCTAssertEqual(repo.entries(on: sameDayThere).map(\.id), [written.id], "在 \(reader.identifier) 读")
            XCTAssertEqual(repo.allEntriesByDay()[sameDayThere]?.map(\.id), [written.id],
                           "日历页走的是这条：按天归堆的 key 得是那边的零点")
        }
    }

    func test_在一个时区孵的蛋_换个时区读_还在那一天() async throws {
        let context = freshContext()
        let day10 = at(2026, 10, 2, in: brisbane)
        try CoreDataDayEggStore(context: context, calendar: calendar(brisbane)).save(text: "蛋", emotion: .calm, for: day10)

        let store8 = CoreDataDayEggStore(context: context, calendar: calendar(shanghai))
        let day8 = at(2026, 10, 2, in: shanghai)
        XCTAssertEqual(store8.egg(for: day8)?.text, "蛋")
        let window = store8.eggs(from: at(2026, 9, 28, in: shanghai), before: at(2026, 10, 3, in: shanghai))
        XCTAssertEqual(Array(window.keys), [day8], "关怀窗口、日历页都按这个 key 找")
    }

    /// 10-02 复现时的第二个症状：今天的日记在新时区被当成「过去欠蛋的一天」，打开 App 就被自动孵了
    func test_换了时区_打开App的补蛋不会去孵今天() async {
        let context = freshContext()
        // 今天（10-02）在布里斯班写了两篇；昨天写了一篇、没有蛋 —— 昨天该补，今天不该。
        // 直接建实体而不是走 create()：create 写的是「现在」，测试要固定的日期
        for (d, h) in [(2, 8), (2, 9), (1, 20)] {
            let post = Post(context: context)
            post.id = UUID()
            post.content = "\(d) 号 \(h) 点"
            post.createdAt = at(2026, 10, d, h, in: brisbane)
            post.dayKey = DayStamp.stored(post.createdAt, in: brisbane)
        }
        try? context.save()

        let summarizer = CountingSummarizer()
        let service = DayEggService(posts: CoreDataPostRepository(context: context, calendar: calendar(shanghai)),
                                    eggs: CoreDataDayEggStore(context: context, calendar: calendar(shanghai)),
                                    summarizer: summarizer,
                                    calendar: calendar(shanghai))
        let hatched = await service.hatchAllPending(now: at(2026, 10, 2, 12, in: shanghai))

        XCTAssertEqual(hatched, 1)
        XCTAssertEqual(summarizer.summarized, [["1 号 20 点"]], "只补昨天；今天那两篇得留给用户按母鸡")
    }

    // MARK: - 迁移老数据

    func test_迁移_老存法和没有dayKey的日记_换成新存法_而且只迁一次() async {
        let context = freshContext()
        let legacyDay = at(2026, 10, 2, in: brisbane)            // 旧存法 = 写的时候那个时区的零点

        let withKey = Post(context: context)
        withKey.id = UUID(); withKey.content = "有 dayKey"; withKey.createdAt = at(2026, 10, 2, 8, in: brisbane)
        withKey.dayKey = legacyDay
        let withoutKey = Post(context: context)
        withoutKey.id = UUID(); withoutKey.content = "更老的，没 dayKey"; withoutKey.createdAt = at(2026, 10, 1, 21, in: brisbane)
        let egg = DayEgg(context: context)
        egg.date = legacyDay; egg.text = "蛋"; egg.emotion = "calm"; egg.createdAt = at(2026, 10, 2, 22, in: brisbane)
        try? context.save()

        DayStampMigration.runIfNeeded(in: context, timeZone: brisbane)

        XCTAssertEqual(withKey.dayKey, DayStamp.stored(legacyDay, in: brisbane))
        XCTAssertEqual(withoutKey.dayKey, DayStamp.stored(at(2026, 10, 1, in: brisbane), in: brisbane), "没 dayKey 的顺手补上")
        XCTAssertEqual(egg.date, DayStamp.stored(legacyDay, in: brisbane))
        XCTAssertFalse(context.hasChanges, "迁完要存进库")

        // 迁移之后，换个时区照样读得到
        let repo8 = CoreDataPostRepository(context: context, calendar: calendar(shanghai))
        XCTAssertEqual(repo8.entries(on: at(2026, 10, 2, in: shanghai)).map(\.content), ["有 dayKey"])
        XCTAssertEqual(repo8.entries(on: at(2026, 10, 1, in: shanghai)).map(\.content), ["更老的，没 dayKey"])

        // 迁过了：再放一条旧存法的进去，第二次不该再扫（靠 metadata 里的标记跳过）
        let late = Post(context: context)
        late.id = UUID(); late.content = "迁移之后才出现的旧值"; late.createdAt = Date(); late.dayKey = legacyDay
        try? context.save()
        DayStampMigration.runIfNeeded(in: context, timeZone: brisbane)
        XCTAssertEqual(late.dayKey, legacyDay, "标记在 metadata 里，第二次直接跳过")
    }

    func test_迁移_升级那会儿人在别的时区_也还原对() async {
        let context = freshContext()
        let post = Post(context: context)
        post.id = UUID(); post.content = "在布里斯班写的"; post.createdAt = at(2026, 10, 2, 8, in: brisbane)
        post.dayKey = at(2026, 10, 2, in: brisbane)
        try? context.save()

        DayStampMigration.runIfNeeded(in: context, timeZone: losAngeles)   // 升级时人在洛杉矶

        let repoLA = CoreDataPostRepository(context: context, calendar: calendar(losAngeles))
        XCTAssertEqual(repoLA.entries(on: at(2026, 10, 2, in: losAngeles)).map(\.content), ["在布里斯班写的"])
    }
}

/// 假总结器：记下每次被要求总结的是哪几篇
@MainActor
private final class CountingSummarizer: DayEggSummarizing {
    var summarized: [[String]] = []
    func summarizeDay(_ entries: [SlimeItem]) async throws -> DayEggSummary {
        summarized.append(entries.map(\.content))
        return DayEggSummary(text: "总结", emotion: .calm)
    }
}
