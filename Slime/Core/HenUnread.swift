//
//  HenUnread.swift
//  Slime
//

import Foundation

/// 写完日记、AI 没读上时（没网、超时、AI 出错），母鸡说的那一句。
///
/// 跟 `HenGreeting` 一样**不走 AI** —— 本来就是因为 AI 不在才轮到它。
/// 所以它只能说「收好了」，**不能假装读过**：不评价内容、不猜情绪、不安慰，
/// 也不许诺「等会儿再看」—— 没有补读，许诺了做不到。
///
/// 口径跟聊天失败那句「刚刚走神了」一致：用母鸡自己的方式交代这次没顾上细看，
/// 不提网络 —— 母鸡不知道什么是网。
enum HenUnread {

    private static let lines = [
        "咕……刚刚走神了，不过替你收好啦",
        "咕咕，收进窝里啦",
        "收好啦，一个字都没落下",
    ]

    static func random() -> String {
        lines.randomElement() ?? "咕咕，收进窝里啦"
    }
}
