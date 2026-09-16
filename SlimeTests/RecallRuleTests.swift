//
//  RecallRuleTests.swift
//  SlimeTests
//
//  上半部分是行为单测（RRF 融合、三路各自的脾气）。
//  下半部分是 eval：拿 RecallEvalCorpus 跑 recall@5 和 MRR。
//
//  eval 不调 API，所以不需要 RUN_EVAL 开关，跟着普通测试一起跑就行。
//  报告走 XCTAttachment —— 命令行跑测试时 print 会丢，关怀那边已经踩过。
//

import XCTest
@testable import Slime

final class RecallRuleTests: XCTestCase {

    /// 固定时刻。**测试绝不能依赖「今天」**，否则跨零点跑就会飘。
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func doc(daysAgo: Int, _ text: String, _ emotion: SlimeEmotion = .calm) -> RecallDocument {
        RecallDocument(id: RecallEvalCorpus.id(daysAgo: daysAgo),
                       date: now.addingTimeInterval(TimeInterval(-daysAgo * 86_400)),
                       text: text,
                       emotion: emotion)
    }

    // MARK: - 三路各自的脾气

    func test_三路都没捞到的文档不进结果() {
        let hits = RecallRule.rank(
            documents: [doc(daysAgo: 1, "今天天气不错", .happy)],
            query: RecallQuery(keywords: ["组长"], emotion: .angry))

        XCTAssertTrue(hits.isEmpty)
    }

    func test_关键词命中多的排前面() {
        let hits = RecallRule.rank(
            documents: [doc(daysAgo: 1, "组长说了几句"),
                        doc(daysAgo: 2, "组长在会上批评了方案")],
            query: RecallQuery(keywords: ["组长", "批评"], emotion: nil))

        XCTAssertEqual(hits.first?.document.text, "组长在会上批评了方案")
    }

    func test_情绪同调分三档() {
        // query 是 tired：同情绪 > 同为负向 > 正向（正向拿 0 分，不上榜）
        let hits = RecallRule.rank(
            documents: [doc(daysAgo: 1, "甲", .happy),
                        doc(daysAgo: 2, "乙", .sad),
                        doc(daysAgo: 3, "丙", .tired)],
            query: RecallQuery(keywords: [], emotion: .tired))

        XCTAssertEqual(hits.map(\.document.text), ["丙", "乙"])
    }

    func test_向量那一路由外部注入() {
        let old = doc(daysAgo: 200, "半年前那件事")
        let recent = doc(daysAgo: 1, "昨天那件事")

        let hits = RecallRule.rank(
            documents: [recent, old],
            query: RecallQuery(keywords: [], emotion: nil),
            similarities: [old.id: 0.9, recent.id: 0.2])

        XCTAssertEqual(hits.first?.document.text, "半年前那件事")
    }

    // MARK: - 融合

    func test_两路都上榜的压过单路第一() {
        // 甲命中两个词，关键词那一路排第一，但只占这一路。
        // 乙关键词只排第二，可情绪那一路排第一 —— 两路加起来，RRF 下乙该赢。
        let hits = RecallRule.rank(
            documents: [doc(daysAgo: 1, "组长批评了我", .happy),
                        doc(daysAgo: 2, "组长", .tired)],
            query: RecallQuery(keywords: ["组长", "批评"], emotion: .tired))

        XCTAssertEqual(hits.first?.document.text, "组长")
        XCTAssertEqual(hits.first?.ranks.count, 2)
    }

    // MARK: - 这条线松了整个 RAG 就白做了

    func test_时间不参与排名() {
        // 久远的那条命中两个词，昨天那条只命中一个。久远的必须赢。
        let hits = RecallRule.rank(
            documents: [doc(daysAgo: 1, "组长找我聊了聊"),
                        doc(daysAgo: 300, "组长在会上批评了方案")],
            query: RecallQuery(keywords: ["组长", "批评"], emotion: nil))

        XCTAssertEqual(RecallEvalCorpus.daysAgo(hits[0].document.date, from: now), 300)
    }

    func test_同分时排序是确定的() {
        // Swift 的 sort 不保证稳定。同分不做 tie-break 的话，
        // eval 分数会自己抖，而你会以为是算法在变。
        let documents = [doc(daysAgo: 1, "组长"), doc(daysAgo: 2, "组长"), doc(daysAgo: 3, "组长")]
        let query = RecallQuery(keywords: ["组长"], emotion: nil)

        let first = RecallRule.rank(documents: documents, query: query).map(\.document.date)
        for _ in 0..<20 {
            XCTAssertEqual(RecallRule.rank(documents: documents, query: query).map(\.document.date),
                           first)
        }
    }

    // MARK: - eval

    func test_检索eval() throws {
        let documents = RecallEvalCorpus.documents(now: now)
        var lines: [String] = []
        var recallSum = 0.0
        var mrrSum = 0.0

        for c in RecallEvalCorpus.cases {
            let relevant = RecallEvalCorpus.relevantDates(c, now: now)
            // limit 开大是为了算 MRR —— 第一个命中可能排在 5 名之外
            let hits = RecallRule.rank(documents: documents, query: c.query, limit: 20)

            let recall = RecallMetrics.recallAtK(hits, relevant: relevant)
            let mrr = RecallMetrics.reciprocalRank(hits, relevant: relevant)
            recallSum += recall
            mrrSum += mrr

            lines.append("""

                ── #\(c.id) \(c.name)
                   recall@5 \(fmt(recall))   MRR \(fmt(mrr))
                   检索词 \(c.keywords)   情绪 \(c.emotion?.rawValue ?? "-")
                   标注相关 \(c.relevantDaysAgo.sorted(by: >).map { "\($0)天前" }.joined(separator: " "))
                   前 5 名
                \(top5Table(hits, relevant: relevant))
                   为什么这么标
                   \(c.rationale.replacingOccurrences(of: "\n", with: "\n   "))
                """)
        }

        let n = Double(RecallEvalCorpus.cases.count)
        let header = """
            检索 eval · baseline（关键词 + 情绪，向量未接）
            用例 \(RecallEvalCorpus.cases.count) 条   语料 \(RecallEvalCorpus.entries.count) 篇   rrfK \(RecallRule.rrfK)

            平均 recall@5  \(fmt(recallSum / n))
            平均 MRR       \(fmt(mrrSum / n))
            """

        let report = header + "\n" + lines.joined(separator: "\n")
        let a = XCTAttachment(string: report)
        a.name = "recall-eval.txt"
        a.lifetime = .keepAlways   // 默认只在失败时保留，我们每次都要
        add(a)

        // 对照组不该掉分。它一掉，坏的是融合或排序，不是检索。
        let control = RecallEvalCorpus.cases.first { $0.id == 4 }!
        let controlHits = RecallRule.rank(documents: documents, query: control.query, limit: 20)
        XCTAssertEqual(RecallMetrics.recallAtK(controlHits,
                                               relevant: RecallEvalCorpus.relevantDates(control, now: now)),
                       1.0,
                       "对照组 #4 全是字面命中，recall@5 应该是满分")
    }

    // MARK: - 报告排版

    private func fmt(_ v: Double) -> String { String(format: "%.2f", v) }

    private func top5Table(_ hits: [RecallHit], relevant: Set<Date>) -> String {
        hits.prefix(5).enumerated().map { i, hit in
            let mark = relevant.contains(hit.document.date) ? "✓" : " "
            let ago = RecallEvalCorpus.daysAgo(hit.document.date, from: now)
            let by = RecallChannel.allCases.compactMap { channel -> String? in
                guard let rank = hit.ranks[channel] else { return nil }
                return "\(channel.rawValue)#\(rank)"
            }.joined(separator: " ")
            return "   \(mark) \(i + 1). [\(ago)天前] \(hit.document.text.prefix(22))  ← \(by)"
        }.joined(separator: "\n")
    }
}
