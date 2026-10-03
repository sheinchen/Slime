//
//  AppLinks.swift
//  Slime
//

import Foundation

/// App 里用到的外部网页。
nonisolated enum AppLinks {
    /// 隐私政策。页面在 `relay/public/privacy.html`，跟中转同一个 Worker 一起部署。
    ///
    /// **App Store Connect 里「隐私政策网址」填的也是这个** —— 两边必须是同一个地址。
    /// 以后中转换了域名，这里、App Store Connect、页面顶部的注释要一起改。
    static let privacyPolicy = URL(string: AIConfig.baseURL + "/privacy")!

    /// 支持页（`relay/public/support.html`），上面有联系邮箱。App Store Connect 的「支持网址」填的也是它
    static let support = URL(string: AIConfig.baseURL + "/support")!
}
