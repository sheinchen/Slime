//
//  AIConfig.swift
//  Slime
//
//  Created by shiying on 2026/7/15.
//

import Foundation

// nonisolated：纯常量 + 读 UserDefaults，谁都该能直接读 —— AIClient 的默认参数就在非隔离的上下文里读它。
nonisolated enum AIConfig {
    /// 自己的中转（Cloudflare Worker，代码在仓库根目录 `relay/`）。
    /// **App 里没有任何密钥**：DeepSeek 的 key 只存在中转那边，用哪个模型也是中转定。
    /// 以前是直连 `https://api.deepseek.com` + 包里带着 Secrets.plist —— IPA 一解压 key 就在那儿。
    static let baseURL = "https://slime-relay.hen-diary-2026.workers.dev"

    /// 这次安装的随机 ID，第一次用到时生成、存进 UserDefaults。中转拿它**按设备限流**。
    ///
    /// 它**不是密钥，也不认人**：App 自己报的，谁都能编一个。所以中转那边还按 IP 另限一道。
    /// 删 App 重装会换一个新的 —— 对限流来说无所谓。
    ///
    /// `static let` 的初始化只跑一次，而且是线程安全的（Swift 保证），不会两个请求同时生成两个 ID。
    static let installID: String = {
        let key = "AIConfig.installID"
        if let saved = UserDefaults.standard.string(forKey: key) { return saved }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }()
}
