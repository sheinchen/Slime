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

    /// 只跑指定 id 的场景，逗号分隔（`TEST_RUNNER_EVAL_ONLY=37,38,39,40`）。空 = 全跑。
    /// 改 prompt 时先拿一小撮快速对比，省得每次都烧掉全量 × 5 次调用。
    /// ⚠️ 子集跑出来的 precision / recall **不能和全量基线比**，只能和同一子集的上一次比。
    private var onlyIDs: Set<Int> {
        let raw = ProcessInfo.processInfo.environment["EVAL_ONLY"] ?? ""
        return Set(raw.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) })
    }

    /// 固定时刻。窗口日期都是相对它算的，测试不能依赖「今天」。
    private let now = Date(timeIntervalSince1970: 1_757_000_000)

    // MARK: - 一次场景的结果

    /// 说出口的一句话 —— 连同判断文案要用到的两个附带信息。
    ///
    /// **光存 text 不够**:范围词那条检查要知道它引用了几天
    /// (「那几天」只在引用了一天时才是错的),长度那条要知道安全级别
    /// (concern / crisis 时 prompt 允许说长一点)。
    nonisolated struct Said {
        let text: String
        let days: Int           // referencedDates 的天数
        let normal: Bool        // safety == .normal
    }

    private struct Outcome {
        let c: EvalCase
        var saidCount = 0        // 说了几次
        var failedCount = 0      // 调用失败几次
        var samples: [Said] = []     // 它说了什么，文案抽查用

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

        let only = onlyIDs
        let cases = only.isEmpty ? CareEvalCases.all : CareEvalCases.all.filter { only.contains($0.id) }
        XCTAssertFalse(cases.isEmpty, "EVAL_ONLY 里的 id 一个都没匹配上：\(only.sorted())")

        dump("\n跑 \(cases.count) 个场景 × \(runs) 次 = \(cases.count * runs) 次调用"
             + (only.isEmpty ? "" : "（只跑 \(only.sorted().map(String.init).joined(separator: ","))）") + "\n")

        for c in cases {
            var o = Outcome(c: c)

            for _ in 0..<runs {
                do {
                    let d = try await ai.decideCare(window: c.window(now: now),
                                                    recentlySaid: c.recentlySaid)
                    if d.shouldShow {
                        o.saidCount += 1
                        o.samples.append(Said(text: d.message,
                                              days: d.referencedDates.count,
                                              normal: d.safety == .normal))
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
        let hardHits = copyAudit(outcomes)
        attachTranscript()

        // **只有硬禁词才断言失败。** precision / recall 是分数、没有「通过」一说
        // (见文件头),但禁词是条亮线:规格第 10 节写的就是「禁词 0 例」。
        // 放在 attachTranscript 之后 —— 失败也要能捞到报告。
        XCTAssertEqual(hardHits, 0, "文案里出现了 prompt 明令禁止的词,详见报告「文案抽查」一节")
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

        // 错的那些要能看到它到底说了什么，否则不知道该怎么改 prompt。
        // **跑子集时全都打** —— 那时候你盯的往往是文案而不是 shouldShow，
        // 而判对的场景同样可能说出有问题的话(#41 就是:它判对，但文案里把一天说成了几天)。
        let wrong = onlyIDs.isEmpty
            ? outcomes.filter { $0.predicted(of: runs) != $0.c.expected }
            : outcomes
        if !wrong.isEmpty {
            var detail = onlyIDs.isEmpty ? "\n────── 判错的场景 ──────" : "\n────── 全部样本（子集模式）──────"
            for o in wrong {
                detail += "\n#\(o.c.id) \(o.c.name)（标注该\(o.c.expected ? "说" : "闭嘴")）"
                detail += "\n   理由: \(o.c.rationale)"
                // 抽查文案时 2 条不够看 —— 判错的场景里,**它说了什么**往往比「说没说」更要紧:
                // 同一条用例可能一半是有分量的综合、一半是「注意休息」级别的空话,
                // 只看两条会把这个差别藏起来。
                for s in o.samples.prefix(10) { detail += "\n   它说: \(s.text)" }
                detail += "\n"
            }
            dump(detail)
        }
    }

    // MARK: - 文案抽查
    //
    // 和 precision / recall 是两回事:那两个量的是**说不说**,这里量的是**说了什么**。
    // 规格第 10 节列的「文案铁律:禁词 0 例」一直没实现,这里补上。
    //
    // 分两档,分界线和闸门那条一样 —— **算术的硬判,语义的只报不判**:
    // · 硬禁词:prompt 里**逐字点名**禁止的,出现即失败,没有判断余地
    // · 可疑项:要看上下文才能定的,列出来给人看
    //
    // 范围词是典型的第二类:「这几天」在真的连着好几天时完全正确,
    // **只在它引用了一天时才是把事实说错**(09-23 外婆那次就是 —— 外婆只出现在一天,
    // 模型反复说「外婆住院那几天」)。所以判据不是「有没有这个词」,而是「词 + 引用了几天」。

    private enum Copy {
        /// 暴露判断依据(铁律②)。**prompt 里是逐字点名禁止的**,所以敢硬判。
        static let leaks = ["连续", "检测", "记录显示", "数据显示", "从日记看", "我注意到"]

        /// 很快过期的时间词。同样是 prompt 里逐字点名的。
        static let expiring = ["今天", "今晚", "刚刚"]

        /// 范围词:把一天说成好几天。**只在只引用了一天时才可疑**,所以只报不判。
        /// ⚠️ 这张表是**实测补出来的**,不是一次想全的。
        /// 第一版漏了「那段」——「外婆住院那段揪心」明显是同类错误却没被抓到。
        /// 改 prompt 时再看到新花样就往里加。
        static let spans = ["这几天", "那几天", "这阵子", "那阵子",
                            "这段", "那段", "好几天", "好些天", "连着", "一连"]

        /// safety normal 时「**尽量**不超过 32 个汉字」—— prompt 写的是「尽量」,所以只报。
        /// **只数汉字**:prompt 说的是「汉字」,把标点和「咕」后面那些符号算进去会虚报。
        static let maxChars = 32

        static func hanCount(_ s: String) -> Int {
            s.unicodeScalars.filter { (0x4E00...0x9FFF).contains($0.value) }.count
        }
    }

    private struct Hit { let id: Int; let tag: String; let text: String }

    /// - Returns: 硬禁词命中数。调用方据此断言。
    private func copyAudit(_ outcomes: [Outcome]) -> Int {
        var hard: [Hit] = [], spans: [Hit] = [], long: [Hit] = []
        var total = 0

        for o in outcomes {
            for said in o.samples {
                total += 1
                for w in Copy.leaks + Copy.expiring where said.text.contains(w) {
                    hard.append(Hit(id: o.c.id, tag: w, text: said.text))
                }
                // 范围词:只在**引用不超过 2 天**时才报。
                //
                // 这个阈值是调出来的,两头都撞过:
                // · 第一版卡 days == 1 → 全量 0 例,**假阴性**。referencedDates 数的是
                //   「这条关怀基于哪几天」,不是「它说的那件事跨几天」;模型会引用 2 天
                //   (外婆 + 加班)却仍然把单日的外婆说成「那几天」。
                // · 第二版不预筛、全报 → 110 句里 19 例,其中 11 例是 `引用4~5天`,
                //   那些场景真的连着好几天,「这几天」完全正确。**噪声淹掉信号**。
                // · 现在卡 ≤ 2 天:「几天」口语上至少是三天,引用一两天却说「几天」才可疑。
                //
                // 仍然只报不判 —— 判断是语义的。days == 1 标 ⚠️,那种基本是错的。
                if said.days <= 2 {
                    for w in Copy.spans where said.text.contains(w) {
                        let mark = said.days == 1 ? "⚠️ " : ""
                        spans.append(Hit(id: o.c.id, tag: "\(mark)\(w)·引用\(said.days)天", text: said.text))
                    }
                }
                let han = Copy.hanCount(said.text)
                if said.normal, han > Copy.maxChars {
                    long.append(Hit(id: o.c.id, tag: "\(han) 汉字", text: said.text))
                }
            }
        }

        // ⚠️ 的排前面,列表被截断时先保住最可能是错的那些
        spans.sort { $0.tag.hasPrefix("⚠️") && !$1.tag.hasPrefix("⚠️") }

        func block(_ title: String, _ hits: [Hit]) -> String {
            guard !hits.isEmpty else { return "\n\(title): 0 例 ✅" }
            var out = "\n\(title): \(hits.count) 例"
            for h in hits.prefix(12) { out += "\n  #\(h.id) 「\(h.tag)」 \(h.text)" }
            if hits.count > 12 { out += "\n  …另有 \(hits.count - 12) 例" }
            return out
        }

        dump("\n────── 文案抽查（共 \(total) 句）──────"
             + block("硬禁词·暴露判断依据 / 会过期的时间词（0 例才算过）", hard)
             + block("可疑·范围词（只看引用 ≤2 天的；⚠️ = 只引用一天，基本是说错了）", spans)
             + block("可疑·超过 \(Copy.maxChars) 字（prompt 写的是「尽量」）", long)
             + "\n")

        return hard.count
    }

    private func pad(_ s: String, _ n: Int) -> String {
        // 中文按两格宽算，表格才对得齐
        let w = s.reduce(0) { $0 + ($1.isASCII ? 1 : 2) }
        return s + String(repeating: " ", count: max(0, n - w))
    }
}
