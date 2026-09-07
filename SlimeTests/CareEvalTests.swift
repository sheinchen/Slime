//
//  CareEvalTests.swift
//  SlimeTests
//
//  关怀决策的 eval —— 批量把 golden set 喂给 AI，量出 precision / recall。
//
//  ⚠️ 这不是单元测试。它没有「通过」这个概念，只有一个可以和上次对比的分数。
//     它会真的调 20 × 3 = 60 次 API（约两三分钟、几块钱），所以默认跳过。
//
//  怎么跑：
//    TEST_RUNNER_RUN_EVAL=1 DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
//      xcodebuild test -project Slime.xcodeproj -scheme Slime \
//      -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
//      -only-testing:SlimeTests/CareEvalTests
//
//  （xcodebuild 会把 TEST_RUNNER_ 前缀剥掉再传给测试进程，所以代码里读的是 RUN_EVAL）
//

import XCTest
@testable import Slime

final class CareEvalTests: XCTestCase {

    /// 每个场景跑几次。temperature 0.8 有随机性，跑一次测的是运气不是模型。
    private var runsPerCase: Int {
        Int(ProcessInfo.processInfo.environment["EVAL_RUNS"] ?? "") ?? 3
    }

    /// 固定时刻。窗口日期都是相对它算的，测试不能依赖「今天」。
    private let now = Date(timeIntervalSince1970: 1_757_000_000)

    // MARK: - 一次场景的结果

    private struct Outcome {
        let c: EvalCase
        var saidCount = 0        // 说了几次
        var failedCount = 0      // 调用失败几次
        var samples: [String] = []   // 它说了什么，人工抽查用

        var runs: Int { saidCount + failedCount + notSaidCount }
        var notSaidCount = 0

        /// 多数决。3 次里说了 2 次就算「说」。
        func predicted(of runs: Int) -> Bool { saidCount * 2 > runs }
        /// 说得稳不稳。既不是全说也不是全不说 = 它在判断边界上晃。
        func isFlaky(of runs: Int) -> Bool { saidCount != 0 && saidCount != runs - failedCount }
    }

    // MARK: -

    func test_关怀决策eval() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_EVAL"] == "1",
            "eval 要真调 API，默认跳过。要跑就加 TEST_RUNNER_RUN_EVAL=1（见文件头注释）"
        )
        // 早失败好过跑一半才发现没 key
        XCTAssertFalse(AIConfig.apiKey.isEmpty, "读不到 Secrets.plist 里的 key")

        let ai = DeepSeekAIService()
        let runs = runsPerCase
        var outcomes: [Outcome] = []

        dump("\n跑 \(CareEvalCases.all.count) 个场景 × \(runs) 次 = \(CareEvalCases.all.count * runs) 次调用\n")

        for c in CareEvalCases.all {
            var o = Outcome(c: c)

            for _ in 0..<runs {
                do {
                    let d = try await ai.decideCare(window: c.window(now: now),
                                                    recentlySaid: c.recentlySaid)
                    if d.shouldShow {
                        o.saidCount += 1
                        o.samples.append(d.message)
                    } else {
                        o.notSaidCount += 1
                    }
                } catch {
                    // 「调用失败」必须和「AI 说不」分开记。
                    // 混在一起的话，一次断网会让所有场景都变成「不说」，
                    // 报告上就是一份 precision 100% 的完美假成绩。
                    o.failedCount += 1
                }
            }

            outcomes.append(o)
            dump(line(o, runs: runs))
        }

        report(outcomes, runs: runs)
        attachTranscript()
    }

    // MARK: - 输出

    private func line(_ o: Outcome, runs: Int) -> String {
        let dots = String(repeating: "●", count: o.saidCount)
            + String(repeating: "○", count: o.notSaidCount)
            + String(repeating: "×", count: o.failedCount)
        let mark = o.predicted(of: runs) == o.c.expected ? "✅" : "❌"
        let flaky = o.isFlaky(of: runs) ? " ⚠️不稳定" : ""
        let label = o.c.expected ? "该说" : "不说"
        return "\(mark) #\(String(format: "%2d", o.c.id)) \(pad(o.c.name, 22)) 标注:\(label)  \(dots)\(flaky)"
    }

    /// 报告攒在这里，跑完一次性变成附件。
    private var transcript = ""

    /// 命令行跑 xcodebuild test 时，测试进程的 print **不会**进 xcodebuild 的 stdout，
    /// .xcresult 里也没有 —— 输出就这么丢了（Xcode 界面里跑反而看得见）。
    ///
    /// 写文件也不行：测试跑在**克隆出来的模拟器**上（日志里那句 "Clone 1 of iPhone 17 Pro"），
    /// 跑完克隆就销毁，容器里的文件跟着没。
    ///
    /// 所以用 XCTAttachment —— 它会被收进 .xcresult，跑完能用
    /// `xcrun xcresulttool export attachments` 捞出来。
    private func dump(_ text: String) {
        print(text)
        transcript += text + "\n"
    }

    private func attachTranscript() {
        let a = XCTAttachment(string: transcript)
        a.name = "eval-report.txt"
        a.lifetime = .keepAlways      // 默认只在失败时保留，我们每次都要
        add(a)
    }

    private func report(_ outcomes: [Outcome], runs: Int) {
        let failures = outcomes.reduce(0) { $0 + $1.failedCount }
        if failures > 0 {
            dump("\n⚠️ 有 \(failures) 次调用失败。失败太多的话这份报告不可信，先修网络再跑。")
        }

        // 混淆矩阵
        var tp = 0, fp = 0, fn = 0, tn = 0
        for o in outcomes {
            switch (o.predicted(of: runs), o.c.expected) {
            case (true,  true):  tp += 1
            case (true,  false): fp += 1
            case (false, true):  fn += 1
            case (false, false): tn += 1
            }
        }

        let precision = tp + fp == 0 ? 0 : Double(tp) / Double(tp + fp)
        let recall    = tp + fn == 0 ? 0 : Double(tp) / Double(tp + fn)
        let flaky = outcomes.filter { $0.isFlaky(of: runs) }

        dump("""

        ══════════════════ 结果 ══════════════════
        说对了 (TP) \(tp)      不该说却说了 (FP) \(fp)
        该说没说 (FN) \(fn)      不说也没说 (TN) \(tn)

        precision  \(String(format: "%.2f", precision))   说出口的里面，有多少是该说的
        recall     \(String(format: "%.2f", recall))   该说的里面，有多少说了
        ── precision 优先：说错一次的代价远大于漏说一次 ──

        不稳定场景 \(flaky.count)/\(outcomes.count)   同样输入给出不同答案 = 在判断边界上
        \(flaky.map { "  #\($0.c.id) \($0.c.name)" }.joined(separator: "\n"))
        ═════════════════════════════════════════
        """)

        // 错的那些要能看到它到底说了什么，否则不知道该怎么改 prompt
        let wrong = outcomes.filter { $0.predicted(of: runs) != $0.c.expected }
        if !wrong.isEmpty {
            var detail = "\n────── 判错的场景 ──────"
            for o in wrong {
                detail += "\n#\(o.c.id) \(o.c.name)（标注该\(o.c.expected ? "说" : "闭嘴")）"
                detail += "\n   理由: \(o.c.rationale)"
                for s in o.samples.prefix(2) { detail += "\n   它说: \(s)" }
                detail += "\n"
            }
            dump(detail)
        }
    }

    private func pad(_ s: String, _ n: Int) -> String {
        // 中文按两格宽算，表格才对得齐
        let w = s.reduce(0) { $0 + ($1.isASCII ? 1 : 2) }
        return s + String(repeating: " ", count: max(0, n - w))
    }
}
