//
//  RecallIntent.swift
//  Slime
//
//  检索前的意图提炼结果。
//
//  放在 Recall/ 而不是 Models/，是因为它只服务检索这一条线 ——
//  跟 RecallDocument / RecallQuery 摆在一起，改的时候一眼看全。
//

import Foundation

nonisolated struct RecallIntent {

    /// 要不要去翻历史日记。
    ///
    /// **AI 在这里有否决权**：纯寒暄、对上一句的简单回应、问母鸡自己的事，
    /// 这些去检索只会捞一堆噪声回来，还白费一次编码。
    /// 跟关怀那边的权限结构一样 —— AI 能说「这次不必」，但不能绕过本地的调用时机。
    let shouldRecall: Bool

    /// 检索词，**已经做过同义词扩展**。
    ///
    /// 这是这一步存在的主要理由。关键词那一路是逐字匹配，
    /// 用户说「组长」就只能命中写着「组长」的日记，写「领导」「上司」的全漏。
    /// 把一个词扩成一簇同义说法，那条短板就补上了。
    let keywords: [String]

    /// 用户**此刻**的情绪，喂给情绪同调那一路。
    /// 注意不是他正在回忆的往事的情绪。
    let emotion: SlimeEmotion?

    /// 原始 JSON，排查用。
    let raw: String

    /// 转成纯函数吃的查询。
    var query: RecallQuery {
        RecallQuery(keywords: keywords, emotion: emotion)
    }

    /// 什么都不做的意图。AI 判否决、或者本地闸门没放行时用它。
    static let skip = RecallIntent(shouldRecall: false, keywords: [], emotion: nil, raw: "")
}
