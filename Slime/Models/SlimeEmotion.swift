//
//  SlimeEmotion.swift
//  Slime
//
//  Created by shiying on 2026/7/8.
//

import Foundation

enum SlimeEmotion: String {
    case happy
    case calm
    case sad
    case angry
    case anxious   // 焦虑
    case tired     // 疲惫

    static func random() -> SlimeEmotion {
        [.happy, .calm, .sad, .angry, .anxious, .tired].randomElement()!
    }
}

extension SlimeEmotion {
    /// 解析 AI 吐出来的情绪词。所有「AI 给的情绪」都走这一个口。
    ///
    /// 只规整大小写和首尾空白 —— `"Calm"`、`" calm"` 是格式问题，不是没读上。
    /// 六类以外的一律 nil：把 `"neutral"`、`"平静"` 映射成 calm 就是在猜，
    /// 猜的和 AI 给的存进同一列，以后分不出来。调用方拿到 nil 怎么办各自定：
    /// 单篇日记存 nil（回复照存），蛋抛错交给 `EggDebt` 重孵。
    ///
    /// `nonisolated`：`SlimeEmotion` 跟着工程默认隔离在主线程，不标的话纯函数单测没法同步调用。
    nonisolated init?(aiOutput raw: String) {
        self.init(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}

enum SlimeSpecialState {
    case none
    case rainbow
}
