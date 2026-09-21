//
//  CareGate.swift
//  Slime
//
//  Created by shiying on 2026/9/4.
//

import Foundation

/// 交给 AI 的情绪时间线。一天一颗蛋，按日期升序。
nonisolated struct MoodWindow: Equatable {
    let eggs: [DayEggRecord]
}

/// 被哪一条挡下的。rawValue 直接写进 CareCheck.gateReason，
/// 以后 debug 页上一眼就能看出「昨天那条为什么没弹」。
///
/// v2 原本还有一条「已有关怀挂着」。改成「让 AI 决定要不要替换」之后删掉了 ——
/// 关怀挂着时，AI 每次都该有机会判断「旧的还贴切吗」，本地不再替它做主。
nonisolated enum GateBlockReason: String {
    case noNewEgg      = "自上次检查后没有新蛋"
    case notEnoughDays = "窗口内有蛋的天数不足"
    case cooling       = "距上条关怀退场不满冷却期"
}

nonisolated enum CareGateResult: Equatable {
    case pass(MoodWindow)
    case blocked(GateBlockReason)
}


// MARK: - 判断规则（纯函数）

/// 闸门的全部判断逻辑。
///
/// 它只回答三件算术：有新蛋吗 / 天数够吗 / 刚说过吗。
/// **一个 emotion 字样都没有** —— 而且它拿不到任何仓库，想违规也违规不了。
nonisolated enum CareGateRule {

    static let windowDays = 14
    static let minDaysWithEgg = 3

    /// 冷却：上条关怀退场后，至少隔这么多个**自然天**才能再生成。
    ///
    /// 从 3 天降到 1 天，是因为「要不要换成新的」现在交给了 AI ——
    /// 本地这条只剩兜底作用，防它天天想说话。
    /// 而「同一天不会重复」已经由条件①（有新蛋）保证了。
    ///
    /// 按**自然天**而不是小时：用户今天 10 点打开、明天 9 点打开只差 23 小时，
    /// 按小时算会被挡下 —— 但那只是打开时刻的随机偏差，不该影响该不该关怀。
    static let cooldownDays = 1

    /// - Parameter daysSinceLastRetire: 距上条关怀退场过了几个自然天。nil = 从没关怀过。
    ///   日历计算放在 `CareGate` 里做，这里只比数字 —— 纯函数不碰 Calendar。
    static func decide(eggsInWindow: [DayEggRecord],
                       lastCheckedAt: Date?,
                       daysSinceLastRetire: Int?) -> CareGateResult {

        // 1. 自上次检查后有新蛋吗。
        //    从没检查过（nil）算「有新的」—— 第一次总该看一眼。
        if let lastCheckedAt,
           !eggsInWindow.contains(where: { $0.createdAt > lastCheckedAt }) {
            return .blocked(.noNewEgg)
        }

        // 2. 窗口内有蛋的天数够 AI 看出走向吗（一颗蛋 = 一天，所以数组长度就是天数）
        if eggsInWindow.count < minDaysWithEgg { return .blocked(.notEnoughDays) }

        // 3. 距上条关怀退场满冷却了吗。从没关怀过（nil）算冷却已过。
        if let daysSinceLastRetire, daysSinceLastRetire < cooldownDays {
            return .blocked(.cooling)
        }

        return .pass(MoodWindow(eggs: eggsInWindow.sorted { $0.date < $1.date }))
    }
}

// MARK: - 取数适配器

/// 从仓库把数据取出来交给 CareGateRule。**自己不含任何判断**，只做日历换算。
@MainActor
final class CareGate {

    private let eggs: DayEggStore
    private let messages: CareMessageStore
    private let checks: CareCheckStore
    private let calendar: Calendar

    init(eggs: DayEggStore,
         messages: CareMessageStore,
         checks: CareCheckStore,
         calendar: Calendar = .current) {
        self.eggs = eggs
        self.messages = messages
        self.checks = checks
        self.calendar = calendar
    }

    func evaluate(now: Date = Date()) -> CareGateResult {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -CareGateRule.windowDays, to: today) ?? today

        // 距上条关怀退场过了几个自然天。两边都取 startOfDay 再相减，
        // 这样「昨天退的」永远是 1，跟具体几点无关。
        let daysSinceRetire = messages.lastRetiredAt().map {
            calendar.dateComponents([.day], from: calendar.startOfDay(for: $0), to: today).day ?? 0
        }

        // 窗口含今天。今天的蛋只在用户按住母鸡时才会出现 —— 那个动作本身就是「收束今天」，
        // 不是半成品。而评估只在 sceneDidBecomeActive 时跑，所以在 App 里连续写日记、孵蛋，
        // 关怀不会当场冒出来，要切走再回来才会评估。
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        return CareGateRule.decide(
            eggsInWindow: Array(eggs.eggs(from: start, before: tomorrow).values),
            lastCheckedAt: checks.lastCheckedAt(),
            daysSinceLastRetire: daysSinceRetire
        )
    }
}
