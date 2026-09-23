//
//  RecallRerankEvalTests.swift
//  SlimeTests
//
//  重排(第二阶段)的 eval —— 把 RecallRerankEvalCases 真喂给模型，量出
//  「该提的提了没」和「不该提的忍住了没」。
//
//  ⚠️ 这不是单元测试。它没有「通过」这个概念，只有一个可以和上次对比的分数。
//     26 条 × 5 次 = 130 次真实 API 调用，所以默认跳过。
//
//  怎么跑：
//    TEST_RUNNER_RUN_EVAL=1 DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
//      xcodebuild test -project Slime.xcodeproj -scheme Slime \
//      -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
//      -only-testing:SlimeTests/RecallRerankEvalTests
//
//  ── 为什么不能只看一个总分 ──
//
//  26 条里有 10 条 gold 是空选。一个永远返回空数组的重排器什么都不做就能拿下
//  这 10 条 —— **「模型变保守了」会长得跟「模型变好了」一模一样。**
//  所以必须拆成两个数报，并且跟两条基线比：
//
//    全空基线      一条都不选。它拿到的分 = 这套用例的「白送分」
//    前三条基线    无脑返回 m0,m1,m2。**它代表 RRF 的排序**，
//                 重排器要是赢不过它，这次调用就是白花的钱。
//
//  两条基线都是纯算术，不调 API，每次跑都会一起打印出来。
//

import XCTest
@testable import Slime

@MainActor
final class RecallRerankEvalTests: XCTestCase {

    /// 每条跑几次。CLAUDE.md 的教训：3 次的噪声能让结果翻转，至少 5 次。
    private var runsPerCase: Int {
        Int(ProcessInfo.processInfo.environment["EVAL_RUNS"] ?? "") ?? 5
    }

    /// 并发几路。130 次串行要十几分钟；网络等待时主线程是空的，可以叠。
    private let concurrency = 4

    /// 固定时刻。候选日期都是相对它算的，测试不能依赖「今天」。
    private let now = Date(timeIntervalSince1970: 1_757_000_000)

    // MARK: - 一条 case 的结果

    private struct Outcome {
        let c: RerankEvalCase
        var picks: [[Int]] = []      // 每次选中了哪些（已翻回 daysAgo / inline key）
        var reasons: [String] = []
        var failed = 0

        /// 这一次算不算对：must 全中，且一条 exclude 都没碰。
        func ok(_ pick: [Int]) -> Bool {
            c.mustInclude.isSubset(of: Set(pick)) && Set(pick).isDisjoint(with: c.mustExclude)
        }

        var okCount: Int { picks.filter(ok).count }

        /// 摇摆 = 既不是全对也不是全错。这时先别改 prompt，先读 reason。
        var isFlaky: Bool { okCount != 0 && okCount != picks.count }

        var averagePicked: Double {
            picks.isEmpty ? 0 : Double(picks.map(\.count).reduce(0, +)) / Double(picks.count)
        }

        var excludeViolations: Int {
            picks.filter { !Set($0).isDisjoint(with: c.mustExclude) }.count
        }

        /// must 命中率：跨 run 平均「must 里中了几成」。
        var mustRecall: Double? {
            guard !c.mustInclude.isEmpty, !picks.isEmpty else { return nil }
            let total = picks.reduce(0.0) {
                $0 + Double(c.mustInclude.intersection(Set($1)).count) / Double(c.mustInclude.count)
            }
            return total / Double(picks.count)
        }
    }

    // MARK: -

    func test_重排eval() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_EVAL"] == "1",
            "eval 要真调 API，默认跳过。要跑就加 TEST_RUNNER_RUN_EVAL=1（见文件头注释）"
        )
        XCTAssertFalse(AIConfig.apiKey.isEmpty, "读不到 Secrets.plist 里的 key")

        let ai = DeepSeekAIService()
        let runs = runsPerCase
        let cases = RerankEvalCases.all

        dump("跑 \(cases.count) 条 × \(runs) 次 = \(cases.count * runs) 次调用，并发 \(concurrency)\n")

        // (caseIndex, runIndex) 摊平成一个任务队列，限流跑。
        var jobs: [(Int, Int)] = []
        for i in cases.indices { for r in 0..<runs { jobs.append((i, r)) } }

        var results: [Int: [(pick: [Int], reason: String)?]] =
            Dictionary(uniqueKeysWithValues: cases.indices.map { ($0, Array(repeating: nil, count: runs)) })

        var cursor = 0
        await withTaskGroup(of: (Int, Int, [Int], String)?.self) { group in
            func push() {
                guard cursor < jobs.count else { return }
                let (i, r) = jobs[cursor]
                cursor += 1
                let c = cases[i]
                let hits = RerankEvalCases.hits(for: c, now: now)
                let turns = RerankEvalCases.turns(c)
                group.addTask { @MainActor in
                    do {
                        let selection = try await ai.rerank(message: c.message,
                                                            recentTurns: turns,
                                                            candidates: hits)
                        // 模型给的是 m0...mN，这里翻回 daysAgo 好跟标注比。
                        // ⚠️ 编造的 id 已经被 RecallSelectionRule 静默丢掉了，
                        //    所以「模型编了个 m9」和「模型明确不选」在这儿长得一样。
                        //    要分开，得给 RecallSelection 加个 eval 用的 rawTokens。
                        let keys = selection.selectedDocumentIDs.compactMap {
                            RerankEvalCases.key(for: $0, in: c)
                        }
                        return (i, r, keys, selection.reason)
                    } catch {
                        return nil
                    }
                }
            }

            for _ in 0..<concurrency { push() }
            for await result in group {
                if let (i, r, keys, reason) = result {
                    results[i]?[r] = (keys, reason)
                }
                push()
            }
        }

        var outcomes: [Outcome] = []
        for (i, c) in cases.enumerated() {
            var o = Outcome(c: c)
            for slot in results[i] ?? [] {
                if let slot {
                    o.picks.append(slot.pick)
                    o.reasons.append(slot.reason)
                } else {
                    o.failed += 1
                }
            }
            outcomes.append(o)
            dump(line(o))
        }

        report(outcomes)
        attachTranscript()
    }

    // MARK: - 报告

    private func line(_ o: Outcome) -> String {
        let dots = o.picks.map { o.ok($0) ? "●" : "○" }.joined()
            + String(repeating: "×", count: o.failed)
        let gold = o.c.mustInclude.isEmpty
            ? "空选"
            : o.c.mustInclude.sorted().map(String.init).joined(separator: ",")
        let picks = o.picks.map { $0.isEmpty ? "-" : $0.map(String.init).joined(separator: ",") }
            .joined(separator: " | ")
        let tag = o.c.scored ? (o.isFlaky ? " ⚠️摇摆" : "") : " 〔观察项，不计分〕"
        return """
            \(o.c.scored && o.okCount == o.picks.count && o.failed == 0 ? "✅" : "❌") \
            #\(pad(String(o.c.id), 3))\(pad(o.c.name, 18)) 标注:\(pad(gold, 12)) \(dots)\(tag)
                选中: \(picks)
            """
    }

    private func report(_ all: [Outcome]) {
        let scored = all.filter(\.c.scored)
        let positives = scored.filter { !$0.c.mustInclude.isEmpty }
        let empties = scored.filter { $0.c.mustInclude.isEmpty }

        let mustRecall = positives.compactMap(\.mustRecall)
        let avgMustRecall = mustRecall.isEmpty ? 0 : mustRecall.reduce(0, +) / Double(mustRecall.count)

        let totalRuns = scored.map(\.picks.count).reduce(0, +)
        let violations = scored.map(\.excludeViolations).reduce(0, +)
        let emptyRuns = empties.flatMap(\.picks)
        let emptyKept = emptyRuns.filter(\.isEmpty).count

        let avgPicked = scored.flatMap(\.picks).map(\.count)
        let avg = avgPicked.isEmpty ? 0 : Double(avgPicked.reduce(0, +)) / Double(avgPicked.count)

        dump("""

            ════════════════════════════════════════════
            计分用例 \(scored.count) 条（正例 \(positives.count) / 空选 \(empties.count)），
            观察项 \(all.count - scored.count) 条不计分

            must 命中率      \(pct(avgMustRecall))    （只在 \(positives.count) 条正例上算）
            exclude 违反     \(violations)/\(totalRuns) 次
            空选类守住       \(emptyKept)/\(emptyRuns.count) 次
            平均选中条数     \(String(format: "%.2f", avg)) 条 / 次（上限 3）
            逐条全对         \(scored.filter { $0.okCount == $0.picks.count && $0.failed == 0 }.count)/\(scored.count)
            摇摆             \(scored.filter(\.isFlaky).count) 条

            ── 基线（纯算术，不调 API）──
            \(baseline(scored, name: "全空    ") { _ in [] })
            \(baseline(scored, name: "前三条  ") { Array($0.c.candidates.prefix(3).map(\.key)) })
            ════════════════════════════════════════════
            """)

        dump("\n── 模型自己的理由（抽查用，每条取第一次）──")
        for o in all where !o.reasons.isEmpty {
            dump("#\(o.c.id) \(o.c.name): \(o.reasons[0])")
        }
    }

    /// 基线：给定一个「假重排器」的选法，算它在同一套标注下能拿多少。
    private func baseline(_ scored: [Outcome], name: String, pick: (Outcome) -> [Int]) -> String {
        var hit = 0.0, positives = 0, violations = 0, allOK = 0
        for o in scored {
            let p = Set(pick(o))
            if !o.c.mustInclude.isEmpty {
                positives += 1
                hit += Double(o.c.mustInclude.intersection(p).count) / Double(o.c.mustInclude.count)
            }
            if !p.isDisjoint(with: o.c.mustExclude) { violations += 1 }
            if o.c.mustInclude.isSubset(of: p) && p.isDisjoint(with: o.c.mustExclude) { allOK += 1 }
        }
        let recall = positives == 0 ? 0 : hit / Double(positives)
        return "\(name)must 命中 \(pct(recall))  exclude 违反 \(violations)/\(scored.count)  逐条全对 \(allOK)/\(scored.count)"
    }

    private func pct(_ v: Double) -> String { String(format: "%5.1f%%", v * 100) }

    private func pad(_ s: String, _ n: Int) -> String {
        let width = s.reduce(0) { $0 + ($1.isASCII ? 1 : 2) }
        return s + String(repeating: " ", count: max(0, n - width))
    }

    // MARK: - 输出

    /// 命令行跑 xcodebuild test 时测试进程的 print 会丢（见 CareEvalTests 的注释），
    /// 所以报告攒起来走 XCTAttachment。
    private var transcript = ""

    private func dump(_ text: String) {
        print(text)
        transcript += text + "\n"
    }

    private func attachTranscript() {
        let attachment = XCTAttachment(string: transcript)
        attachment.name = "rerank-eval-report.txt"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
