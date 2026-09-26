//
//  AIConsentTests.swift
//  SlimeTests
//
//  「同意还算不算数」的规则，和 UserDefaults 那份存取。
//
//  这条规则一旦判错，要么是**没同意就把日记发出去了**（违反审核规则 5.1.2(i)），
//  要么是同意过的人每次打开都被拦在同意页 —— 两头都是事故，所以单独锁住。
//

import XCTest
@testable import Slime

/// 纯函数：同步测试就行（没有 isolated deinit，不撞 §5 那个运行时 bug）
final class AIConsentRuleTests: XCTestCase {

    func test_没同意过_不算数() {
        XCTAssertFalse(AIConsent.isValid(grantedVersion: nil))
    }

    func test_同意的是当前版本_算数() {
        XCTAssertTrue(AIConsent.isValid(grantedVersion: AIConsent.currentVersion))
    }

    /// 发给 AI 的内容变了、版本号 +1 之后，旧的同意必须作废 —— 用户没看过新内容
    func test_同意的是旧版本_不算数() {
        XCTAssertFalse(AIConsent.isValid(grantedVersion: AIConsent.currentVersion - 1))
    }

    /// 装过新版又退回旧版（TestFlight 上会发生）：同意的比现在的还新，照样算数，不该把人拦住
    func test_同意的比当前版本还新_算数() {
        XCTAssertTrue(AIConsent.isValid(grantedVersion: AIConsent.currentVersion + 1))
    }
}

/// 碰 App 里的类：一律 `@MainActor` + async（CLAUDE.md §5）。
/// 每条用一个独立的 UserDefaults suite，不碰 App 真正的 `.standard`。
@MainActor
final class UserDefaultsAIConsentStoreTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suiteName = "AIConsentTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func test_新装的App_没同意() async {
        let store = UserDefaultsAIConsentStore(defaults: defaults)
        XCTAssertFalse(store.hasConsented)
    }

    func test_同意之后_算数() async {
        let store = UserDefaultsAIConsentStore(defaults: defaults)
        store.grant()
        XCTAssertTrue(store.hasConsented)
    }

    func test_撤回之后_不算数() async {
        let store = UserDefaultsAIConsentStore(defaults: defaults)
        store.grant()
        store.withdraw()
        XCTAssertFalse(store.hasConsented)
    }

    /// 同意是存下来的，不是记在内存里：换一个实例（= 下次打开 App）还认
    func test_同意跨实例保留() async {
        UserDefaultsAIConsentStore(defaults: defaults).grant()
        XCTAssertTrue(UserDefaultsAIConsentStore(defaults: defaults).hasConsented)
    }
}

/// AIClient 那道闸：没同意时请求**根本没发出去**，而不是「发了、失败了」。
///
/// 怎么分辨这两种：baseURL 指向本机一个没人监听的端口。
/// 真发出去了会得到连接被拒的网络错误（URLError）；只有在发之前就被拦下，才会是 `notAllowed`。
@MainActor
final class AIClientConsentGateTests: XCTestCase {

    private func makeClient(allowed: Bool) -> AIClient {
        AIClient(isSendingAllowed: { allowed }, baseURL: "http://127.0.0.1:9")
    }

    private let messages = [AIChatMessage(role: "user", content: "今天有点累")]

    func test_没同意_普通请求在发出前就被拦下() async {
        do {
            _ = try await makeClient(allowed: false).requestText(messages: messages, temperature: 0)
            XCTFail("没同意也拿到了回复")
        } catch AIError.notAllowed {
            // 对了：没发出去
        } catch {
            XCTFail("请求发出去了（报的是网络错误）：\(error)")
        }
    }

    /// 聊天走的是流式，拼请求的时机跟上面不一样（在返回流之前），单独锁一条
    func test_没同意_流式请求也被拦下() async {
        do {
            for try await _ in makeClient(allowed: false).streamText(messages: messages, temperature: 0) {}
            XCTFail("没同意也收到了流")
        } catch AIError.notAllowed {
        } catch {
            XCTFail("请求发出去了（报的是网络错误）：\(error)")
        }
    }

    /// 反过来确认这个测试法本身有效：同意了就真的会发出去，撞上那个没人监听的端口
    func test_同意了_请求真的发出去() async {
        do {
            _ = try await makeClient(allowed: true).requestText(messages: messages, temperature: 0)
            XCTFail("本机 9 号端口不该有人回复")
        } catch AIError.notAllowed {
            XCTFail("同意了还被拦下")
        } catch {
            // 对了：是网络错误，说明请求真的出去了
        }
    }
}
