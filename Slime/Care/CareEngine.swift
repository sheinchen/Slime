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
    private let messages: CareMessageStore
    private let checks: CareCheckStore
    private let ai: CareDeciding

    init(gate: CareGate,
         messages: CareMessageStore,
         checks: CareCheckStore,
         ai: CareDeciding) {
        self.gate = gate
        self.messages = messages
        self.checks = checks
        self.ai = ai
    }
    
    func handle(_ event: CareEvent, now: Date = Date()) async {

            // ① 先判退场。**必须在闸门之前** —— 挂满 3 天的那条要先退掉，
            //    否则 lastRetiredAt 不更新、冷却算错，而且会把一条过期的话发给 AI。
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
                check = await askAI(window: window, now: now, check: check)
            }

            // ④ 放行与否都记一笔。这条日志本身就是下次闸门条件①的锚点。
            checks.record(check)
        }
    
    /// 闸门放行之后：问 AI，按它的回答落库。
    /// **AI 在这里行使一票否决权** —— 它说不说，这里就真的不说。
    private func askAI(window: MoodWindow, now: Date, check: CareCheckRecord) async -> CareCheckRecord {
        var check = check
        check.aiCalled = true
        let began = Date()
        

        do {
            let decision = try await ai.decideCare(window: window, recentlySaid: messages.recentCares(limit: 3))
            check.latencyMs = Int(Date().timeIntervalSince(began) * 1000)
            check.aiRaw = decision.raw

            guard decision.shouldShow else {
                check.dropReason = "AI 判断这次不值得说"
                return check
            }

            // shouldShow: true 就是「换成新的」—— show() 会先把旧的退掉，
            // 所以「替换」和「旧的退场」是同一个动作的两半。
            messages.show(text: decision.message,
                          referencedDates: decision.referencedDates,
                          now: now)
            check.finalShown = true

        } catch {
            // 失败一律当「本次不展示」：不伪造、不重试轰炸。
            // 绝不能让一次网络抖动变成一条奇怪的关怀弹在用户面前。
            check.latencyMs = Int(Date().timeIntervalSince(began) * 1000)
            check.dropReason = "AI 调用失败: \(error.localizedDescription)"
        }

        return check
    }
    
    /// 关怀什么时候退场。
    ///
    /// **本地只剩「满 3 天必退」这一条兜底。**
    /// 「这句话还贴不贴切」是语义判断，交给 AI —— 它每次都能看到挂着的那条
    /// （recentCares 带着 stillShowing），自己判断要不要换成新的；
    /// 要换的时候 show() 会把旧的退掉。所以「替换」就是旧的退场。
    ///
    /// 这条兜底不能删：AI 不可达时（断网、API 挂了），关怀不能永远挂在那儿。
    ///
    /// ⚠️ 已知缺口：AI 现在只能表达「保持」或「替换」，没法说「撤掉但不换新的」。
    ///    所以一句略过时的话最多会多挂到第 3 天。等真觉得难受再上三元契约。
    private func retireIfNeeded(now: Date) {
        guard let care = messages.active() else { return }

        let deadline = care.createdAt.addingTimeInterval(Self.validity)
        guard deadline <= now else { return }

        // 记它**实际**死的那一刻，不是 now ——
        // 隔一周才打开的话，记成「今天退场」会让冷却又白等一轮。
        messages.retire(at: deadline)
    }
}

