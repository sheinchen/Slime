//
//  TutorialStore.swift
//  Slime
//

import Foundation

/// 示范看过没有（走完或跳过都算）。跟别的仓库一样用协议，测试时能换成独立的一份。
protocol TutorialStore: AnyObject {
    var hasFinished: Bool { get }
    func markFinished()
    /// 只给 Debug 的 `-ResetTutorial` 用 —— 产品上不能重看（09-29 定）
    func reset()
}

/// 存在 UserDefaults 里，一个 Bool。
///
/// 为什么不进 Core Data：跟同意状态（`AIConsentStore`）一样，是一个开关，不是一批记录。
/// 删 App 时一起清掉 —— 重装之后是新用户，本来就该再看一遍。
///
/// 示范走到一半 App 被杀：没记上，下次打开从头再来。示范只有两三分钟，不值得存进度
final class UserDefaultsTutorialStore: TutorialStore {

    private let defaults: UserDefaults
    private static let key = "Tutorial.finished"

    /// `defaults` 留默认值：全 App 共享的那一份，多建几个 store 也是同一份数据（CLAUDE.md §5 的判据）。
    /// 测试传一个独立的 suite。
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var hasFinished: Bool {
        defaults.bool(forKey: Self.key)
    }

    func markFinished() {
        defaults.set(true, forKey: Self.key)
    }

    func reset() {
        defaults.removeObject(forKey: Self.key)
    }
}
