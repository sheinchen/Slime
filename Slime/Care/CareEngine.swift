//
//  CareEngine.swift
//  Slime
//
//  Created by shiying on 2026/7/29.
//

import Foundation

@MainActor
final class CareEngine {

    /// 关怀最长挂 3 天。保质期和露面次数上限是同一件事的两面，这个数不能放大。
    private static let validity: TimeInterval = 3 * 24 * 60 * 60

    private let gate: CareGate
    private let eggs: DayEggStore
    private let messages: CareMessageStore
    private let checks: CareCheckStore
    private let calendar: Calendar
    
    
    init(gate: CareGate,
         eggs: DayEggStore,
         messages: CareMessageStore,
         checks: CareCheckStore,
         calendar: Calendar = .current) {
        self.gate = gate
        self.eggs = eggs
        self.messages = messages
        self.checks = checks
        self.calendar = calendar
    }
    
    func handle(_ event: CareEvent, now: Date = Date()) async {

            // ① 先判退场。**必须在闸门之前** ——
            //    否则那条早该走的关怀还占着「已有关怀挂着」，闸门第 0 条把自己永远挡死。
            retireIfNeeded(now: now)

            var check = CareCheckRecord(checkedAt: now)

            // ② 闸门。**必须在 checks.record 之前** ——
            //    闸门条件①读的就是 lastCheckedAt，先记日志等于先把自己挡掉。
            switch gate.evaluate(now: now) {

            case .blocked(let reason):
                check.gateReason = reason.rawValue

            case .pass(let window):
                check.gatePassed = true
                // ③ 第 7 步在这里调 AI 决策层，返回后 messages.show(...)。
                //    本地只负责放行；说不说、说什么是 AI 的事 —— 它有一票否决权。
                check.dropReason = "AI 决策层未接入"
                _ = window
            }

            // ④ 放行与否都记一笔。这条日志本身就是下次闸门条件①的锚点。
            checks.record(check)
        }
    
    /// 退场规则只有两条，**谁先到算谁**。
       private func retireIfNeeded(now: Date) {
           guard let care = messages.active() else { return }

            // 规则②：生成后满 3 天，内容过保质期。用户停写日记时靠它兜底。
            let deadline = care.createdAt.addingTimeInterval(Self.validity)

            // 规则①：关怀之后有了新蛋 —— 语境翻篇了。补蛋、手动孵都算，
            //        只要这颗蛋代表的日子没落在关怀之前。
            let careDay = calendar.startOfDay(for: care.createdAt)
            let newEgg = eggs.firstEgg(bornAfter: care.createdAt,
                                          forDayOnOrAfter: careDay)?.createdAt

            // 「或」在这里就是两个时刻取 min
            let death = min(deadline, newEgg ?? .distantFuture)

            guard death <= now else { return }

            // 记它**实际**死的那一刻，不是 now。
            // 你隔一周才打开 App，这条三天前就该走的关怀不该被记成"今天退场"，
            // 否则冷却又白等 3 天。
            messages.retire(at: death)
       }
}

