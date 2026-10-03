//
//  AIEmotionOutputTests.swift
//  SlimeTests
//
//  模型回了一个六类以外的情绪词，怎么办。
//
//  10-01 以前两处都兜成 calm：写完日记那句（HenChatService.analyze）和孵蛋（DayEggSummarizer）。
//  兜成 calm = 猜的和 AI 给的存进同一列，以后分不出来；蛋那处更糟，一存 EggDebt 就判不欠，错蛋永远不重孵。
//  现在：单篇存 nil、回复照存；蛋抛错，交给现成的重试。
//

import XCTest
@testable import Slime

/// 解析口本身。纯函数：同步测试就行
final class SlimeEmotionAIOutputTests: XCTestCase {

    func test_六个词原样认得() {
        for raw in ["happy", "calm", "sad", "angry", "anxious", "tired"] {
            XCTAssertEqual(SlimeEmotion(aiOutput: raw)?.rawValue, raw)
        }
    }

    func test_大小写和首尾空白是格式问题_规整后认得() {
        XCTAssertEqual(SlimeEmotion(aiOutput: "Calm"), .calm)
        XCTAssertEqual(SlimeEmotion(aiOutput: " SAD\n"), .sad)
    }

    func test_六类以外一律nil_不猜() {
        XCTAssertNil(SlimeEmotion(aiOutput: "neutral"), "映射成 calm 就是在猜")
        XCTAssertNil(SlimeEmotion(aiOutput: "平静"))
        XCTAssertNil(SlimeEmotion(aiOutput: ""))
        XCTAssertNil(SlimeEmotion(aiOutput: "sad, tired"), "给两个也不挑一个")
    }
}

/// 孵蛋拿到坏情绪词之后的表现。走真的 AIClient，回包来自假服务器。
@MainActor
final class AIEmotionFallbackTests: XCTestCase {

    override func setUp() async throws { URLProtocol.registerClass(FakeJSONProtocol.self) }
    override func tearDown() async throws { URLProtocol.unregisterClass(FakeJSONProtocol.self) }

    private func client() -> AIClient {
        AIClient(isSendingAllowed: { true },
                 baseURL: "https://\(FakeJSONProtocol.host)",
                 installID: "test")
    }

    private let entry = SlimeItem(id: UUID(), content: "加班到九点，回家路上一直想哭",
                                  createdAt: Date(), emotion: nil, reply: nil, day: Date())

    // MARK: - 蛋

    func test_蛋_情绪词不认得就抛错_不兜calm() async {
        FakeJSONProtocol.reply(#"{"emotion":"neutral","text":"一天慢慢过去了"}"#)
        do {
            let summary = try await DayEggSummarizer(client: client()).summarizeDay([entry])
            XCTFail("该抛错，却孵出了 \(summary.emotion)")
        } catch AIError.invalidContent {
            // 对：不存 → EggDebt 判还欠 → 下次回前台 / 下次按母鸡再孵
        } catch {
            XCTFail("抛错的种类不对: \(error)")
        }
    }

    func test_蛋_大小写不对照样孵出来() async throws {
        FakeJSONProtocol.reply(#"{"emotion":"Sad","text":"一天慢慢过去了"}"#)
        let summary = try await DayEggSummarizer(client: client()).summarizeDay([entry])
        XCTAssertEqual(summary.emotion, .sad)
    }

    // 写完日记那句（HenChatService.analyze）这里测不了：它带 8 秒总时限，走的是 AIClient 自己建的 URLSession，
    // 全局注册的 URLProtocol 只拦 `URLSession.shared` —— 10-01 试过，请求真的发去查 DNS 了。
    // 它只有一行 `SlimeEmotion(aiOutput:)`，解析口上面那组测过；为它把 session 改成可注入不值得
}

/// 假服务器：拦下发往 `host` 的请求，回 200 + 一个 OpenAI 格式的外层信封，`content` 是写死的那段 JSON。
/// `nonisolated`：URLSession 在自己的线程上调这些方法，不能跟着工程默认隔离到主线程。
nonisolated private final class FakeJSONProtocol: URLProtocol {
    static let host = "json.fake.invalid"
    nonisolated(unsafe) static var body = Data()

    /// 把模型写的那段（`content`）包进信封。用 JSONSerialization 包，引号转义不用手写
    static func reply(_ content: String) {
        let envelope: [String: Any] = ["choices": [["message": ["content": content]]]]
        body = try! JSONSerialization.data(withJSONObject: envelope)
    }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == host }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
