//
//  PendingCare.swift
//  Slime
//
//  Created by shiying on 2026/7/23.
//

import Foundation

nonisolated enum CareStatus: String {
    case shown  // 正在挂着
    case retired    // 已退休：挂满 3 天
}

//给UI的值类型
nonisolated struct PendingCare {
    let id: UUID
    let text: String
    let createdAt: Date

    /// 这条话**第一次真正被看到**的时刻。nil = 还没被看到过。
    ///
    /// 它区分的是关怀的两个生命：
    /// · 内容的生命 —— `status`，最多 3 天，由 AI 判替换、引擎兜底退场；
    /// · 露面的生命 —— 这一条。
    ///
    /// 「说」是一次性事件，「在」是持续状态。**动画属于「说」，不属于「在」。**
    /// nil → 母鸡刚开口，滑出、尾巴指着她、10 秒兜底淡出；
    /// 有值 → 那句话还飘在那儿没散，安静地出现、不自动走。
    ///
    /// 必须落库：只靠 VC 里的内存态，杀掉 App 重开又会是「第一次」。
    let firstSeenAt: Date?
}
