//
//  AIConsentStore.swift
//  Slime
//

import Foundation

/// 「允许把日记交给 AI」的规则。纯函数，不碰存储 —— `AIConsentRuleTests` 锁着。
nonisolated enum AIConsent {
    /// 同意页的内容版本。**发给 AI 的东西变了（多了一种数据、换了接收方），这个数 +1**：
    /// 之前的同意全部作废，所有人下次打开都会重新看到同意页。
    /// 同意页（AIConsentViewController）上的文字要跟着一起改。
    static let currentVersion = 1

    /// 用户同意过的版本现在还算不算数。nil = 没同意过，或者撤回了。
    static func isValid(grantedVersion: Int?) -> Bool {
        guard let grantedVersion else { return false }
        return grantedVersion >= currentVersion
    }
}

/// 用户的同意存在哪。跟别的仓库一样用协议，测试时能换成独立的一份。
protocol AIConsentStore: AnyObject {
    /// 现在算不算数：同意过，而且同意的是当前这一版
    var hasConsented: Bool { get }
    func grant()
    func withdraw()
}

/// 存在 UserDefaults 里，只存一个整数：同意的是第几版。没有这个键 = 没同意过 / 撤回了。
///
/// 为什么不进 Core Data：这是一个开关，不是一批记录；而且 AIClient 每发一次请求都要读它。
/// UserDefaults 就是给这种「小、常读」的设置用的（读的是内存里的缓存，几乎不花钱）。
final class UserDefaultsAIConsentStore: AIConsentStore {

    private let defaults: UserDefaults
    private static let key = "AIConsent.grantedVersion"

    /// `defaults` 留默认值：它是全 App 共享的那一份，多建几个 store 也是同一份数据，
    /// 被悄悄用上也不会多出状态（CLAUDE.md §5 的判据）。测试传一个独立的 suite。
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var hasConsented: Bool {
        // 用 object(forKey:) 而不是 integer(forKey:)：后者没有这个键时返回 0，
        // 「从没同意过」和「同意过第 0 版」就分不清了
        AIConsent.isValid(grantedVersion: defaults.object(forKey: Self.key) as? Int)
    }

    func grant() {
        defaults.set(AIConsent.currentVersion, forKey: Self.key)
    }

    func withdraw() {
        defaults.removeObject(forKey: Self.key)
    }
}
