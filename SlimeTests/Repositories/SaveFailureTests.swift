//
//  SaveFailureTests.swift
//  SlimeTests
//
//  保存失败之后（最常见是手机存储满了）：抛给该知道的人、撤回坏账、不连累下一次（10-02）。
//
//  以前各个仓库存失败只 print：没存上的改动留在 context 里，页面以为存上了；
//  下一次随便谁保存都带着它一起失败；切后台时 saveContext 再存一次，那里是 fatalError —— 崩。
//  这组碰 Core Data（内存库）：要测的就是「context 里还剩什么」，纯函数测不到。
//  @MainActor + async：仓库和 Service 都是主线程隔离的类，见 CLAUDE.md §5。
//

import XCTest
import CoreData
@testable import Slime

@MainActor
final class SaveFailureTests: XCTestCase {

    private var calendar: Calendar { .current }
    private var today: Date { calendar.startOfDay(for: Date()) }

    /// 干净的内存库，套一个会按吩咐保存失败的 context。模型借共享栈那份（同 TimeZoneRepositoryTests）
    private func failingContext() -> FailingSaveContext {
        let model = CoreDataStack.shared.persistentContainer.managedObjectModel
        let container = NSPersistentContainer(name: "Slime", managedObjectModel: model)
        container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        container.loadPersistentStores { _, error in XCTAssertNil(error) }
        let context = FailingSaveContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = container.persistentStoreCoordinator
        return context
    }

    // MARK: - 写日记：唯一要让用户知道的那一处

    func test_日记没存上_抛错_而且哪儿都没留下() async {
        let context = failingContext()
        let repo = CoreDataPostRepository(context: context)

        context.failuresLeft = 1
        XCTAssertThrowsError(try repo.create(content: "没存上的一篇"), "以前只 print，页面照样说「收好了」")
        XCTAssertFalse(context.hasChanges, "没存上的要撤回，不能留在内存里冒充存上了")
        XCTAssertEqual(repo.entries(on: today).count, 0)
    }

    /// 撤回的意义：一笔失败不能变成之后每一笔都失败、或者被下一次保存悄悄捎带进库
    func test_一篇没存上_不连累下一篇() async throws {
        let context = failingContext()
        let repo = CoreDataPostRepository(context: context)

        context.failuresLeft = 1
        _ = try? repo.create(content: "坏的")
        try repo.create(content: "好的")

        XCTAssertEqual(repo.entries(on: today).map(\.content), ["好的"],
                       "不撤回的话，「坏的」会跟着第二次保存一起进库 —— 用户以为没存上、换了个说法重写，结果两篇都在")
    }

    // MARK: - 蛋：抛给孵蛋那两条路，走「没孵出来」

    func test_蛋没存上_抛错_库里没有() async {
        let context = failingContext()
        let eggs = CoreDataDayEggStore(context: context)

        context.failuresLeft = 1
        XCTAssertThrowsError(try eggs.save(text: "蛋", emotion: .calm, for: today))
        XCTAssertFalse(context.hasChanges)
        XCTAssertNil(eggs.egg(for: today))
    }

    func test_按母鸡孵今天_蛋没存上_走没孵出来那条路_之后能重按() async throws {
        let context = failingContext()
        let posts = CoreDataPostRepository(context: context)
        let eggs = CoreDataDayEggStore(context: context)
        let service = DayEggService(posts: posts, eggs: eggs, summarizer: FixedSummarizer())
        try posts.create(content: "今天的一篇")

        context.failuresLeft = 1
        do {
            _ = try await service.finishToday()
            XCTFail("以前这里照样返回总结：母鸡那边以为孵出来了，鸟巢刷新却是空的")
        } catch {}
        XCTAssertNil(eggs.egg(for: today))

        _ = try await service.finishToday()
        XCTAssertEqual(eggs.egg(for: today)?.text, "总结", "失败后能重按")
    }

    func test_打开App补蛋_蛋没存上_不算孵出来() async throws {
        let context = failingContext()
        let posts = CoreDataPostRepository(context: context)
        let eggs = CoreDataDayEggStore(context: context)
        let service = DayEggService(posts: posts, eggs: eggs, summarizer: FixedSummarizer())
        // 昨天的一篇：直接建实体，create() 写的是「现在」
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))
        let post = Post(context: context)
        post.id = UUID()
        post.content = "昨天的"
        post.createdAt = yesterday.addingTimeInterval(9 * 3600)
        post.dayKey = DayStamp.stored(yesterday, in: calendar.timeZone)
        try context.save()

        context.failuresLeft = 1
        let hatched = await service.hatchAllPending()
        XCTAssertEqual(hatched, 0)
        XCTAssertNil(eggs.egg(for: yesterday))
    }

    // MARK: - 不往上抛的那几个：也得撤回

    /// 换关怀 = 旧的退场 + 新的上任，同一次保存。没存上时两件一起撤：不会出现「旧的退了、新的没上」
    func test_换关怀没存上_旧的还挂着_不留坏账() async {
        let context = failingContext()
        let cares = CoreDataCareMessageStore(context: context)
        cares.show(text: "旧的", referencedDates: [], now: Date())

        context.failuresLeft = 1
        cares.show(text: "新的", referencedDates: [], now: Date())
        XCTAssertFalse(context.hasChanges, "留着的话，切后台那次保底保存会再撞一次 —— 以前那里是 fatalError")

        let all = cares.recentCares(limit: 10)
        XCTAssertEqual(all.map(\.text), ["旧的"])
        XCTAssertEqual(all.first?.stillShowing, true, "退场跟着一起撤回了，旧的还挂着")
    }
}

/// 能指定「接下来几次保存失败」的 context。失败时抛的是「磁盘满了」，跟真机上最常见的那种一样
private final class FailingSaveContext: NSManagedObjectContext {
    var failuresLeft = 0

    override func save() throws {
        if failuresLeft > 0 {
            failuresLeft -= 1
            throw CocoaError(.fileWriteOutOfSpace)
        }
        try super.save()
    }
}

@MainActor
private final class FixedSummarizer: DayEggSummarizing {
    func summarizeDay(_ entries: [SlimeItem]) async throws -> DayEggSummary {
        DayEggSummary(text: "总结", emotion: .calm)
    }
}
