//
//  EvalClient.swift
//  SlimeTests
//
//  eval 专用的 AIClient：走跟 App 一模一样的中转，但带开发者通行证、不被限流。
//

import Foundation
@testable import Slime

/// **为什么 eval 也走中转，不留一条直连 DeepSeek 的后门**：
/// 模型是中转定的（`relay/wrangler.jsonc` 的 MODEL）。直连的话，哪天中转换了模型，
/// eval 测的还是旧模型 —— 基线就和 App 实际在用的对不上了。
///
/// **为什么要通行证**：中转按设备一分钟限 30 次。重排 eval 并发 4 路，一分钟上百次，会撞上。
/// 被限流时重排返回空选 —— 跟「模型判断这次不提旧事」**长得一模一样**，eval 会静默地算错，不报错。
///
/// 通行证放在**仓库根目录**的 `Secrets.plist`（`RelayDevToken`）—— 不在 `Slime/` 里，
/// 所以不会被打进 App；`.gitignore` 忽略它，不会提交。
/// 测试进程读得到它，是因为**模拟器里的进程能直接读 Mac 上的文件**，
/// 所以 eval 只能在模拟器上跑（本来也只在模拟器上跑）。
@MainActor
enum EvalClient {
    static func make() -> AIClient {
        // eval 是开发者自己在测，不经过同意页 —— 闸门直接放行。
        // 不能读 App 的同意状态：那是这台模拟器上的 UserDefaults，没点过同意 eval 就会全部 notAllowed
        AIClient(isSendingAllowed: { true }, devToken: devToken)
    }

    /// 读不到就是 nil。eval 开头会断言它不是 nil —— 早失败好过跑一半被限流、结果悄悄算错。
    static let devToken: String? = {
        // #filePath 是这个源文件在 Mac 上的路径：<仓库>/SlimeTests/EvalClient.swift
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // <仓库>/SlimeTests
            .deletingLastPathComponent()   // <仓库>
        let url = repoRoot.appendingPathComponent("Secrets.plist")
        guard let dict = NSDictionary(contentsOf: url),
              let token = dict["RelayDevToken"] as? String,
              !token.isEmpty else { return nil }
        return token
    }()
}
