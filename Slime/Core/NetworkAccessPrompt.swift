//
//  NetworkAccessPrompt.swift
//  Slime
//

import Foundation

/// 国行 iPhone 的「允许"母鸡日记"使用数据？」弹窗（无线局域网与蜂窝网络 / 无线局域网 / 不允许）。
///
/// 这个弹窗**没有 API 能主动要**：系统在 App 第一次联网的那一刻自己弹，而且只有国行机型有
/// （海外机型、模拟器都看不到）。想让它在哪儿出现，就得在哪儿先发一个请求 —— 这里就是那个请求。
///
/// 为什么提前到同意页：
/// - 不提前的话，第一次联网是同意之后的某次 AI 调用，弹窗会盖在示范、或者母鸡正要回话的时候
/// - 弹窗挂着的那一刻发出的请求通常直接失败。不提前，失败的就是第一次写日记那一下 ——
///   母鸡只能回一句本地的「收好了」。现在失败的是这个无关紧要的请求
///
/// 发的是 `HEAD /privacy`：隐私政策那一页，只要响应头、不要正文。
/// - **不经过 AIClient，所以不受同意那道闸管 —— 也不需要**：不带安装 ID、不带任何用户写的东西，
///   跟同意页上「阅读完整的隐私政策」打开的是同一个地址。IP 那一条隐私政策里写了（「任何联网请求都会带上」）
/// - 静态页面由 Cloudflare 直接回，不进中转的 `index.ts`，不占限流
/// - 结果不看：成功失败都无所谓，它的作用在「发出去」那一刻就完成了
enum NetworkAccessPrompt {
    static func trigger() {
        var request = URLRequest(url: AppLinks.privacyPolicy)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 15
        URLSession.shared.dataTask(with: request).resume()
    }
}
