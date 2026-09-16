//
//  RecallGate.swift
//  Slime
//
//  聊天检索的本地闸门。
//

import Foundation

/// 要不要为这句话发起一次检索。**只做算术，不碰语义。**
///
/// 它只剩一条规则，薄得不像个闸门 —— 这是有意的。
/// 原本还有一条「距上次提起旧事隔几轮」，砍掉了：
/// 用户追问「上次那个你还记得吗」和母鸡自作多情地翻旧账，
/// 在本地眼里都只是「过了几轮」，分不开。**那是语义判断，归 AI。**
/// 拿数数去代理语义，就是 v1 用「连续三篇 sad」猜低谷的同类错误。
///
/// 权限结构跟关怀那边一致：本地管「值不值得问一次」，
/// AI 管「问出来该不该用」。AI 有一票否决权，没有一票通过权 ——
/// 这里挡下来，它根本没机会开口。
nonisolated enum RecallGate {

    /// 太短的句子提炼不出检索词，也没什么可查的。
    static let minLength = 4

    static func shouldTry(message: String) -> Bool {
        message.trimmingCharacters(in: .whitespacesAndNewlines).count >= minLength
    }
}
