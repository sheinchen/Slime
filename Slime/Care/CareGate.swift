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
nonisolated enum GateBlockReason: String {
    case careAlreadyShowing = "已有关怀挂着"
    case noNewEgg           = "自上次检查后没有新蛋"
    case notEnoughDays      = "窗口内有蛋的天数不足"
    case cooling            = "距上条关怀退休不满冷却期"
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
    static let cooldown: TimeInterval = 3 * 24 * 60 * 60   // 退休后冷却 3 天

    static func decide(hasActiveCare: Bool,
                       eggsInWindow: [DayEggRecord],
                       lastCheckedAt: Date?,
                       lastRetiredAt: Date?,
                       now: Date) -> CareGateResult {

        // 0. 前置：已经有关怀挂着，不生成第二条
        if hasActiveCare { return .blocked(.careAlreadyShowing) }

        // 1. 自上次检查后有新蛋吗。
        //    从没检查过（nil）算「有新的」—— 第一次总该看一眼。
        if let lastCheckedAt,
           !eggsInWindow.contains(where: { $0.createdAt > lastCheckedAt }) {
            return .blocked(.noNewEgg)
        }

        // 2. 窗口内有蛋的天数够 AI 看出走向吗（一颗蛋 = 一天，所以数组长度就是天数）
        if eggsInWindow.count < minDaysWithEgg { return .blocked(.notEnoughDays) }

        // 3. 距上条关怀退休满冷却期了吗。
        //    从没关怀过（nil）算冷却已过。
        if let lastRetiredAt, now.timeIntervalSince(lastRetiredAt) < cooldown {
            return .blocked(.cooling)
        }

        return .pass(MoodWindow(eggs: eggsInWindow.sorted { $0.date < $1.date }))
    }
}

// MARK: - 取数适配器

/// 从仓库把数据取出来交给 CareGateRule。**自己不含任何判断**。
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

        // before: today —— 今天的蛋不算。appOpened 是跨天触发的，
        // 这会儿今天多半还没写日记，更没孵蛋。
        return CareGateRule.decide(
            hasActiveCare: messages.active() != nil,
            eggsInWindow: Array(eggs.eggs(from: start, before: today).values),
            lastCheckedAt: checks.lastCheckedAt(),
            lastRetiredAt: messages.lastRetiredAt(),
            now: now
        )
    }
}
