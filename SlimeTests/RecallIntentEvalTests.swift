//
//  RecallIntentEvalTests.swift
//  SlimeTests
//
//  考的是「让 AI 提炼检索词」这一步到底值多少。
//
//  对照组是 RecallEvalCorpus 里手工写的 keywords —— 那是我照着语料挑的，
//  等于开卷考试。AI 只看用户那一句话，看不到语料。
//  **所以 AI 版接近手工版就算成功，超过才是意外之喜。**
//
//  要调 API，默认跳过：
//    TEST_RUNNER_RUN_EVAL=1 DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
//    xcodebuild -project Slime.xcodeproj -scheme Slime \
//      -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
//      test -only-testing:SlimeTests/RecallIntentEvalTests -resultBundlePath Intent.xcresult
//

import XCTest
@testable import Slime

final class RecallIntentEvalTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func test_提炼检索词eval() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_EVAL"] == "1",
                          "eval 要真调 API，默认跳过（见文件头注释）")
        XCTAssertFalse(AIConfig.apiKey.isEmpty, "读不到 Secrets.plist 里的 key")

        let ai = DeepSeekAIService()
        let embedder = try TextEmbedder()
        let documents = RecallEvalCorpus.documents(now: now)

        var docVectors: [UUID: [Float]] = [:]
        for d in documents { docVectors[d.id] = try embedder.embed(d.text) }

        var manualSum = 0.0
        var aiSum = 0.0
        var manualNoVecSum = 0.0
        var aiNoVecSum = 0.0
        var lines: [String] = []

        for c in RecallEvalCorpus.cases {
            let relevant = RecallEvalCorpus.relevantDates(c, now: now)

            let queryVector = try embedder.embedQuery(c.name)
            var similarities: [UUID: Double] = [:]
            for (id, vector) in docVectors {
                similarities[id] = Double(dot(queryVector, vector))
            }

            let intent = try await ai.extractRecallIntent(message: c.name, recentTurns: [])

            func recall(_ query: RecallQuery, withVector: Bool) -> Double {
                let hits = RecallRule.rank(documents: documents, query: query,
                                           similarities: withVector ? similarities : [:],
                                           limit: 20)
                return RecallMetrics.recallAtK(hits, relevant: relevant, k: 10)
            }

            let manualRecall = recall(c.query, withVector: true)
            let aiRecall = recall(intent.query, withVector: true)
            // 关掉向量那一路，同义词扩展的功劳才露出来 ——
            // 三路全开时向量已经把 recall@10 拉满，扩不扩词都看不出差别。
            let manualNoVec = recall(c.query, withVector: false)
            let aiNoVec = recall(intent.query, withVector: false)

            manualSum += manualRecall
            aiSum += aiRecall
            manualNoVecSum += manualNoVec
            aiNoVecSum += aiNoVec

            lines.append("""

                ── #\(c.id) \(c.name)
                   手工词 \(c.keywords)   情绪 \(c.emotion?.rawValue ?? "-")
                   AI 词  \(intent.keywords)   情绪 \(intent.emotion?.rawValue ?? "-")
                   shouldRecall \(intent.shouldRecall)
                   三路全开   手工 \(fmt(manualRecall))   AI \(fmt(aiRecall))
                   关掉向量   手工 \(fmt(manualNoVec))   AI \(fmt(aiNoVec))
                """)
        }

        let n = Double(RecallEvalCorpus.cases.count)
        let report = """
            检索词提炼 eval（指标是 recall@10）

                          手工挑词   AI 提炼
            三路全开      \(fmt(manualSum / n))       \(fmt(aiSum / n))
            关掉向量      \(fmt(manualNoVecSum / n))       \(fmt(aiNoVecSum / n))

            手工词是照着语料挑的，等于开卷；AI 只看用户那一句话。
            「关掉向量」那一行才看得出同义词扩展值多少 ——
            三路全开时向量把 recall@10 拉满，扩词的功劳被盖住了。

            """ + lines.joined(separator: "\n")

        let attachment = XCTAttachment(string: report)
        attachment.name = "recall-intent-eval.txt"
        attachment.lifetime = .keepAlways
        add(attachment)

        // AI 看不到语料，允许比手工版差一点，但差太多说明 prompt 有问题。
        XCTAssertGreaterThan(aiSum / n, manualSum / n - 0.15,
                             "AI 提炼的检索词比手工版差了 0.15 以上，去看 prompt")
    }

    /// 寒暄和简单回应不该触发检索 —— 那种句子捞回来的全是噪声，还白费一次编码。
    func test_寒暄不触发检索() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_EVAL"] == "1",
                          "eval 要真调 API，默认跳过")

        let ai = DeepSeekAIService()
        let smallTalk = ["在吗", "嗯嗯", "好呀", "你叫什么名字呀"]
        var results: [String] = []

        for text in smallTalk {
            let intent = try await ai.extractRecallIntent(message: text, recentTurns: [])
            results.append("  \(text) → shouldRecall \(intent.shouldRecall)  \(intent.keywords)")
            XCTAssertFalse(intent.shouldRecall, "「\(text)」不该触发检索")
        }

        let attachment = XCTAttachment(string: "寒暄判断\n" + results.joined(separator: "\n"))
        attachment.name = "small-talk.txt"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func dot(_ a: [Float], _ b: [Float]) -> Float {
        zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
    }

    private func fmt(_ v: Double) -> String { String(format: "%.2f", v) }
}
