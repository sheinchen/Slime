//
//  RecallChatE2ETests.swift
//  SlimeTests
//
//  端到端：插几篇日记 → 补向量 → 发一句话 → 看母鸡回什么。
//
//  为什么要有这个文件:模拟器的文字输入只吃 ASCII,中文打不进去,
//  剪贴板同步对 UTF-8 也不可靠。所以「母鸡到底会不会提起旧事」
//  这件事**没法靠点界面来验**,只能在这儿跑。
//
//  它碰 Core Data,跟「单测只测纯函数」那条约定不一样 ——
//  这是有意的:它验的正是几层拼起来之后的行为,不是某个纯函数。
//  测试环境下 CoreDataStack 走内存库,跑完就没,不会碰到真数据。
//
//  要调 API,默认跳过:
//    TEST_RUNNER_RUN_EVAL=1 DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
//    xcodebuild -project Slime.xcodeproj -scheme Slime \
//      -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
//      test -only-testing:SlimeTests/RecallChatE2ETests -resultBundlePath E2E.xcresult
//

import XCTest
import CoreData
@testable import Slime

@MainActor
final class RecallChatE2ETests: XCTestCase {

    /// 跟 DebugSeeder 播的是同一批句子,这样手点验证和自动验证看到的是同一个世界。
    private let samples: [(daysAgo: Int, text: String, emotion: SlimeEmotion)] = [
        (1, "方案又被打回来,有点说不出话", .sad),
        (2, "翻到以前的照片,心里空落落的", .sad),
        (3, "身体没病,就是提不起劲", .tired),
        (4, "同事把锅甩过来,气得手抖", .angry),
        (5, "deadline 在后天,进度只走了一半", .anxious),
        (12, "解释了三遍还是被当耳旁风", .angry),
        (20, "开了一整天会,脑子是木的", .tired),
    ]

    func test_母鸡会不会提起旧事() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_EVAL"] == "1",
                          "要真调 API,默认跳过(见文件头注释)")
        XCTAssertFalse(AIConfig.apiKey.isEmpty, "读不到 Secrets.plist 里的 key")

        let context = CoreDataStack.shared.viewContext
        let posts = CoreDataPostRepository(context: context)
        let chatRepo = CoreDataChatRepository(context: context)
        let ai = DeepSeekAIService()
        let embedder = try TextEmbedder()

        clearDiaries(in: context)
        seedDiaries(into: context)

        // ① 补向量
        let index = RecallIndexService(posts: posts, embedder: embedder)
        let indexed = await index.backfill()
        XCTAssertEqual(indexed, samples.count, "该补的向量没补齐")

        let recallService = RecallService(posts: posts, embedder: embedder, ai: ai)

        // **措辞跟日记完全不一样**。用「方案又被打回来」当输入是自欺欺人 ——
        // 母鸡复述一遍就看着像提起了旧事,其实只是在重复用户自己的话。
        // 这句话里「工作」「不顺」「做什么都不对」一个字都没出现在日记里,
        // 母鸡要是能提起方案那次或者被当耳旁风那次,才是检索真的起了作用。
        let message = "最近工作上老是不顺,感觉自己做什么都不对"

        // ② 单独跑一次检索,好把捞到什么写进报告
        let hits = await recallService.recall(message: message, recentTurns: [])

        // ③ 走完整的聊天链路。它内部会再检索一次 ——
        //    多一次调用换「跟真实路径完全一致」,值。
        let vm = ChatViewModel(origin: .direct,
                               chatRepo: chatRepo,
                               posts: posts,
                               aiService: ai,
                               recall: recallService)
        let reply = try await vm.send(message, onDelta: {})

        let report = """
            母鸡会不会提起旧事 · 端到端

            日记 \(samples.count) 篇,向量补齐 \(indexed) 篇
            用户说:「\(message)」

            ── 检索捞到 \(hits.count) 条
            \(hits.isEmpty
              ? "   (空。要么 AI 判了不值得,要么候选里没沾边的)"
              : hits.map { "   · [\(ChineseDate.vague($0.document.date))] \($0.document.text)   \(channels($0))" }
                    .joined(separator: "\n"))

            ── 母鸡回的
            \(reply.content)

            ── 怎么读这份报告
            捞到了、回复里也自然提到了那件事 → 整条链通了
            捞到了、回复里只字未提         → AI 行使了第二次否决权,觉得硬扯不合适
            没捞到                        → 看上面那行空的原因
            """

        let attachment = XCTAttachment(string: report)
        attachment.name = "recall-chat-e2e.txt"
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTAssertFalse(reply.content.isEmpty, "母鸡没说话")
    }

    // MARK: -

    /// 先清场。测试 host 启动时 `DebugSeeder` 也会往同一个内存库里播几篇,
    /// 不清的话候选里会混进重名的日记,检索结果看起来像重复 bug,其实是数据脏。
    private func clearDiaries(in context: NSManagedObjectContext) {
        for post in (try? context.fetch(Post.fetchRequest())) ?? [] {
            context.delete(post)
        }
        try? context.save()
    }

    private func seedDiaries(into context: NSManagedObjectContext) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        for sample in samples {
            guard let day = calendar.date(byAdding: .day, value: -sample.daysAgo, to: today),
                  let at = calendar.date(byAdding: .hour, value: 10, to: day) else { continue }
            let post = Post(context: context)
            post.id = UUID()
            post.content = sample.text
            post.createdAt = at
            post.dayKey = day
            post.emotion = sample.emotion.rawValue
            post.reply = "测试数据"
        }
        try? context.save()
    }

    /// 哪几路把它捞上来的,排查时比总分有用。
    private func channels(_ hit: RecallHit) -> String {
        RecallChannel.allCases.compactMap { channel -> String? in
            guard let rank = hit.ranks[channel] else { return nil }
            return "\(channel.rawValue)#\(rank)"
        }.joined(separator: " ")
    }
}
