//
//  AppOpenFlow.swift
//  Slime
//

import Foundation

/// 「用户回到 App」时要做的事：先让各页对一下日子，再 补蛋 → 关怀 → 刷界面 → 补向量。
///
/// 以前这段直接写在 SceneDelegate 里（09-25 搬出来）。搬的理由只有一个：**它能测了**。
/// 「先补完蛋再跑关怀」是 CLAUDE.md 里的红线，09-24 修的重入 bug 也在这段 ——
/// 那时候只能靠模拟器拉通知中心、再查库来验。现在 `AppOpenFlowTests` 用假步骤就能锁住。
///
/// 每一步是一个闭包而不是一个具体类型：这个流程只关心「这一步做完没有」，
/// 不需要知道补蛋是 DayEggService、关怀是 CareEngine。组合根把真的接上，测试换成记账的假步骤。
@MainActor
final class AppOpenFlow {

    private let hatchPending: @MainActor () async -> Int
    private let evaluateCare: @MainActor () async -> Void
    private let backfillIndex: (@MainActor () async -> Void)?
    private let refreshPages: @MainActor () -> Void

    /// 正在跑的那一轮。nil = 没在跑。
    ///
    /// 一轮可能要跑很久（补蛋、关怀都要调 AI），这期间用户完全可能再回来一次。
    /// 以前每次都起一个新 Task，两轮会**交错着跑**：
    /// @MainActor 只保证同一时刻只有一段代码在执行，每个 await 都是让出点，别的 Task 能插进来（actor 重入）。
    ///
    /// 交错的后果（09-24 在模拟器上复现过：-StubSlow 下拉一次通知中心就触发了第二轮）：
    /// · 闸门条件①的锚点 lastCheckedAt 要等 AI 回来才写，第二轮看到的还是旧锚点 →
    ///   两次 AI 调用、两条关怀，第一条刚落库就被第二条顶掉 —— debug 页里多出一次假替换
    /// · 第二轮的补蛋看到那几天正在孵会直接跳过、秒返回 →
    ///   在第一轮还没孵完时就去跑关怀，违反「先补完蛋再跑关怀」
    ///
    /// 所以防重入挂在**整段流程**上，不挂在 CareEngine 里：要保护的是「顺序」，
    /// 顺序归流程的主人管。只在 CareEngine 里挡，挡得住两次 AI，挡不住第二条。
    private var running: Task<Void, Never>?

    /// - Parameters:
    ///   - hatchPending: 把欠的蛋补上，返回补了几颗
    ///   - evaluateCare: 跑一遍关怀（闸门 → AI → 落库）
    ///   - backfillIndex: 给日记补向量。向量模型没加载起来时是 nil
    ///   - refreshPages: 让各页重读一遍（日子、蛋、关怀卡片）
    init(hatchPending: @escaping @MainActor () async -> Int,
         evaluateCare: @escaping @MainActor () async -> Void,
         backfillIndex: (@MainActor () async -> Void)?,
         refreshPages: @escaping @MainActor () -> Void) {
        self.hatchPending = hatchPending
        self.evaluateCare = evaluateCare
        self.backfillIndex = backfillIndex
        self.refreshPages = refreshPages
    }

    /// 回到前台（冷启动也算）时调。
    ///
    /// - Returns: 这次起的那一轮；上一轮还没跑完就是 nil（这次跳过了）。
    ///   组合根不用管返回值，测试拿它来等这一轮跑完。
    @discardableResult
    func enterForeground() -> Task<Void, Never>? {
        // ① 先让各页对一下「今天」—— 同步、立刻，**不等下面那一轮**，也不受防重入限制。
        //    隔夜回来的第一件事就是补昨天的蛋（要调 AI），弱网下可能等好几分钟，
        //    等它跑完再刷的话，这期间首页标题一直挂着昨天、广场的今天也还是昨天。
        refreshPages()

        // ② 上一轮还没跑完就不起新的，直接跳过 —— 不用排队再跑一遍：
        //    那一轮每一步都是现查库，读到的就是最新的数据，事情它会做完。
        //    代价：补蛋卡在拥堵的 DeepSeek 上时，这期间的回前台都被跳过，关怀要等它跑完才评估。
        //    这跟「孵蛋不加总时限」那次接受的代价是同一个，不新增。
        guard running == nil else { return nil }

        // 先赋值、后清空，顺序是有保证的：这个 Task 继承主线程隔离，
        // 而我们此刻正占着主线程 —— 它的第一行最早也要等这个函数 return 才能跑。
        // 所以不会出现「Task 先跑完清了空、这里才赋值」，running 卡在非 nil、之后全被挡掉。
        let task = Task {
            await runOnce()
            running = nil
        }
        running = task
        return task
    }

    private func runOnce() async {
        // 补蛋 → 关怀，**顺序是红线**：缺了最新一天的蛋，AI 看到的就是过时的时间线，
        // 而情绪反转恰恰藏在最新那一天里。
        let hatched = await hatchPending()
        if hatched > 0 { refreshPages() }        // 补出了蛋，广场页先看得到

        await evaluateCare()
        // 关怀可能刚落库，让首页看一眼 ——
        // 这一轮跑完时 viewDidAppear 早就过去了，不刷的话卡片不会出现。
        refreshPages()

        // 补向量纯本地、跟前面没有顺序关系，另起一个 Task，不拖住这一轮的结束
        if let backfillIndex {
            Task { await backfillIndex() }
        }
    }
}
