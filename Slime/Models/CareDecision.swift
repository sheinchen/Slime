//
//  CareDecision.swift
//  Slime
//
//  Created by shiying on 2026/9/6.
//

import Foundation

/// AI 判定的安全级别。第 8 步的边界层会让 crisis 走完全不同的路径。
nonisolated enum CareSafety: String {
    case normal     // 日常
    case concern    // 有点担心
    case crisis     // 严重低落 / 绝望 / 自伤倾向
}

nonisolated struct PastCare {
    let text: String
    let stillShowing: Bool
    let saidAt: Date
    let about: [Date]

    /// 某颗蛋是不是这条关怀「之后」才出现的信息 —— 发给 AI 的 isNew 就是它算的。
    ///
    /// · **跨天看日期**：迟补的旧蛋孵出时刻很新、内容很旧，按孵出时刻会被误标成新
    /// · **关怀当天看孵出时刻**：日记只能写进今天，这颗蛋不可能是旧账；
    ///   只按日期比又会漏掉「中午说了关怀、晚上重孵」和「昨晚说了关怀、今早才补上昨天的蛋」
    func isNewEvidence(_ egg: DayEggRecord, calendar: Calendar = .current) -> Bool {
        let careDay = calendar.startOfDay(for: saidAt)
        if egg.date != careDay { return egg.date > careDay }
        return egg.createdAt > saidAt
    }
}

/// AI 决策层的结构化返回。
nonisolated struct CareDecision {
    let shouldShow: Bool
    let message: String

    /// AI 用自己的话描述的情绪走向，如「从持续压力中缓过来了」。
    /// v1 的 `CareReason` 枚举就是被它取代的 —— 模式改由 AI 自由描述，
    /// 本地不再试图穷举有哪些情绪模式。
    let pattern: String

    /// 模型自报的置信度。**只记录，禁止用作阈值。**
    /// 模型的校准极差，写 `if confidence > 0.8` 的结果是它几乎永远大于 0.8。
    let confidence: Double

    /// 这句话是基于哪几天说的。已按窗口校验过，不含幻觉日期。
    let referencedDates: [Date]

    let safety: CareSafety

    /// 原始 JSON，写进 `CareCheck.aiRaw` 供排查。
    let raw: String
}
