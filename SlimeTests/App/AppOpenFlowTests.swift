//
//  AppOpenFlowTests.swift
//  SlimeTests
//
//  「回到 App」那条流程：顺序（先补蛋再关怀）和防重入。
//
//  以前这段住在 SceneDelegate 里没法测，09-24 的重入 bug 只能靠模拟器拉通知中心 + 查库来验。
//  09-25 抽成 AppOpenFlow 之后，每一步都是闭包，这里换成记账的假步骤。
//

import XCTest
@testable import Slime

/// `@MainActor` + async：AppOpenFlow 是主线程隔离的类，同步测试里释放会撞运行时 bug（CLAUDE.md §5）。
@MainActor
final class AppOpenFlowTests: XCTestCase {

    /// 假步骤：每一步往 log 里记一笔；补蛋那一步可以被「卡住」，模拟它在等 AI。
    @MainActor
    private final class Script {
        var log: [String] = []
        var hatchedCount = 0
        var holdHatch = false
        private var held: CheckedContinuation<Void, Never>?
        var isHeld: Bool { held != nil }

        func hatch() async -> Int {
            log.append("补蛋")
            if holdHatch { await withCheckedContinuation { held = $0 } }
            return hatchedCount
        }

        func release() {
            held?.resume()
            held = nil
        }
    }

    private func makeFlow(_ s: Script, withBackfill: Bool = false) -> AppOpenFlow {
        AppOpenFlow(hatchPending: { await s.hatch() },
                    evaluateCare: { s.log.append("关怀") },
                    backfillIndex: withBackfill ? { @MainActor in s.log.append("补向量") } : nil,
                    refreshPages: { s.log.append("刷新") })
    }

    func test_先刷新_再补蛋_再关怀_最后再刷一次() async {
        let s = Script()
        await makeFlow(s).enterForeground()?.value
        XCTAssertEqual(s.log, ["刷新", "补蛋", "关怀", "刷新"])
    }

    func test_补出了蛋_关怀之前先刷一次() async {
        let s = Script()
        s.hatchedCount = 2
        await makeFlow(s).enterForeground()?.value
        XCTAssertEqual(s.log, ["刷新", "补蛋", "刷新", "关怀", "刷新"])
    }

    /// 09-24 那个 bug 的回归测试：补蛋还在等 AI 时用户又回来了一次。
    func test_上一轮没跑完再回来_不起第二轮_关怀不会抢在补蛋前面() async {
        let s = Script()
        s.holdHatch = true
        let flow = makeFlow(s)

        let first = flow.enterForeground()
        XCTAssertNotNil(first)
        while !s.isHeld { await Task.yield() }          // 等它卡在补蛋上

        XCTAssertNil(flow.enterForeground(), "上一轮还在跑，不该再起一轮")
        XCTAssertEqual(s.log, ["刷新", "补蛋", "刷新"],
                       "第二次只刷新（对日子）；补蛋只跑了一次；关怀还没轮到 —— 补蛋没完它就不能跑")

        s.release()
        await first?.value
        XCTAssertEqual(s.log, ["刷新", "补蛋", "刷新", "关怀", "刷新"])
    }

    func test_跑完之后_下次回来照常跑() async {
        let s = Script()
        let flow = makeFlow(s)
        await flow.enterForeground()?.value

        let second = flow.enterForeground()
        XCTAssertNotNil(second, "上一轮跑完了，running 必须清空，否则之后的回前台全被挡掉")
        await second?.value
        XCTAssertEqual(s.log.filter { $0 == "关怀" }.count, 2)
    }

    func test_补向量排在关怀之后() async {
        let s = Script()
        await makeFlow(s, withBackfill: true).enterForeground()?.value
        // 补向量是另起的 Task，这一轮结束时只保证排上了、不保证跑完 —— 让出几次让它跑
        for _ in 0..<10 where !s.log.contains("补向量") { await Task.yield() }
        XCTAssertEqual(s.log, ["刷新", "补蛋", "关怀", "刷新", "补向量"])
    }
}
