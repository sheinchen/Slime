//
//  ChatIncompleteReplyTests.swift
//  SlimeTests
//
//  母鸡的回复断在半路时，那半句**不能当成她说完的话**。
//
//  两层各管一半：
//  · AIClient 判断「说完没有」—— 只有 finish_reason == "stop" 才算。
//    没发 [DONE] 就断开、上游中断（insufficient_system_resource），循环都会正常退出，
//    以前会被当成说完了，半句原样交给 VM。
//  · ChatViewModel 决定「没说完的不进历史」—— messages 就是下一次发给模型的上下文。
//    以前半句会进 messages（那时还落库），重试时模型看到自己已经「回过话」了。
//
//  还有第三个入口：**关掉聊天页 = 这一轮被取消**。取消时 `for try await` 是正常退出的（不抛错），
//  半句会绕过上面两道，被当成说完的话进历史 —— 所以 streamReply 开流前、流结束后各有一个取消检查点。
//
//  聊天 10-03 起不存库，messages 就是全部；以前这里还查一遍「库里有没有半句」，那一半随仓库一起删了。
//
//  09-27 修之前，这里除了「正常说完」那条，其余全挂。
//

import XCTest
@testable import Slime

// MARK: - ChatViewModel：半句不进历史

@MainActor
final class ChatIncompleteReplyTests: XCTestCase {

    func test_断在半路_重试的上下文跟第一次一模一样() async throws {
        let ai = CutOffOnceChatAI()
        let vm = ChatViewModel(aiService: ai, recall: nil)

        try vm.addUserMessage("我外婆住院了")
        do {
            _ = try await vm.reply(onDelta: {})
            XCTFail("第一次应该断线失败")
        } catch {}
        _ = try await vm.retry(onDelta: {})

        XCTAssertEqual(ai.contexts.count, 2)
        XCTAssertEqual(ai.contexts[0].map(\.role), ai.contexts[1].map(\.role))
        XCTAssertEqual(ai.contexts[0].map(\.content), ai.contexts[1].map(\.content),
                       "重试时上下文里多了东西 —— 多半是那半句")
        XCTAssertEqual(ai.contexts[1].last?.role, "user", "重试时最后一条必须是用户那句，不能是母鸡自己的话")
    }

    func test_断在半路_半句不进历史也不上屏() async throws {
        let ai = CutOffOnceChatAI()
        let vm = ChatViewModel(aiService: ai, recall: nil)

        try vm.addUserMessage("我外婆住院了")
        do { _ = try await vm.reply(onDelta: {}) } catch {}

        XCTAssertFalse(vm.messages.contains { $0.content == CutOffOnceChatAI.half }, "半句进了历史")
        XCTAssertNil(vm.streamingText, "断了之后正在流的气泡要收掉")
        // 用户那句是真说了的，要留着
        XCTAssertEqual(vm.messages.last?.content, "我外婆住院了")
    }

    /// 母鸡说到一半，用户关了聊天页。
    /// 09-27 实测：不拦的话，流以 `.cancelled` 结束、循环正常退出，reply **正常返回「外婆的事」并进历史**。
    func test_关页面_流到一半被取消_半句不进历史() async throws {
        let ai = HangingChatAI()
        let vm = ChatViewModel(aiService: ai, recall: nil)
        try vm.addUserMessage("我外婆住院了")

        // 半句一上屏就取消 —— 跟用户看到半句后点关闭一样。
        // Task 在测试 await 之前不会开跑（都在主线程上），所以 box 一定先装好
        let box = RoundBox()
        box.round = Task {
            try await vm.reply(onDelta: {
                if vm.streamingText == HangingChatAI.half { box.round?.cancel() }
            })
        }
        let result = await box.round!.result

        if case .success(let m) = result { XCTFail("取消之后不该正常返回，却返回了「\(m.content)」") }
        XCTAssertTrue(ai.endedByCancel, "流没收到「那头不要了」—— AIClient 就是在这一刻断开网络连接的")
        XCTAssertFalse(vm.messages.contains { $0.content == HangingChatAI.half }, "半句进了历史")
        XCTAssertNil(vm.streamingText)
        XCTAssertEqual(vm.messages.last?.content, "我外婆住院了")
    }

    /// 检索期间关了页面：检索会把取消吞掉、照常返回（提不起旧事不该让对话失败），
    /// 所以开流前必须再看一眼，不然白发一个聊天请求。
    /// 这里 recall 是 nil，用「开跑前就已经取消」来模拟「检索返回时已经取消」。
    func test_已经作废的一轮_不再发聊天请求() async throws {
        let ai = HangingChatAI()
        let vm = ChatViewModel(aiService: ai, recall: nil)
        try vm.addUserMessage("我外婆住院了")

        let round = Task { try await vm.reply(onDelta: {}) }
        round.cancel()
        let result = await round.result

        if case .success = result { XCTFail("取消之后不该正常返回") }
        XCTAssertEqual(ai.calls, 0, "页面已经关了，还是发出了聊天请求")
    }
}

// MARK: - AIClient：只有 finish_reason == "stop" 才算说完

@MainActor
final class AIClientStreamCompletionTests: XCTestCase {

    override func setUp() async throws { URLProtocol.registerClass(FakeSSEProtocol.self) }
    override func tearDown() async throws { URLProtocol.unregisterClass(FakeSSEProtocol.self) }

    func test_正常说完_拿到整句() async {
        FakeSSEProtocol.body = sse(
            #"{"choices":[{"delta":{"role":"assistant","content":""},"finish_reason":null}]}"#,
            #"{"choices":[{"delta":{"content":"外婆的事"},"finish_reason":null}]}"#,
            #"{"choices":[{"delta":{"content":"还压着你吧。"},"finish_reason":null}]}"#,
            #"{"choices":[{"delta":{"content":""},"finish_reason":"stop"}]}"#,
            "[DONE]")

        let r = await drain()

        XCTAssertNil(r.error)
        XCTAssertEqual(r.text, "外婆的事还压着你吧。")
    }

    func test_没收到结尾就断开_算没说完() async {
        FakeSSEProtocol.body = sse(
            #"{"choices":[{"delta":{"content":"外婆的事"},"finish_reason":null}]}"#)

        let r = await drain()

        XCTAssertEqual(r.error as? AIError, .incompleteStream, "连接关了被当成正常说完")
    }

    func test_上游中断_即使发了DONE也算没说完() async {
        FakeSSEProtocol.body = sse(
            #"{"choices":[{"delta":{"content":"外婆的事"},"finish_reason":null}]}"#,
            #"{"choices":[{"delta":{"content":""},"finish_reason":"insufficient_system_resource"}]}"#,
            "[DONE]")

        let r = await drain()

        XCTAssertEqual(r.error as? AIError, .incompleteStream, "上游掐断的半句被当成正常说完")
    }

    // MARK: -

    /// 把几行 payload 拼成 SSE 的样子：每行 `data: …`，之间空一行
    private func sse(_ payloads: String...) -> String {
        payloads.map { "data: \($0)\n\n" }.joined()
    }

    private func drain() async -> (text: String, error: Error?) {
        let client = AIClient(isSendingAllowed: { true },
                              baseURL: "https://\(FakeSSEProtocol.host)",
                              installID: "test")
        var text = ""
        do {
            for try await piece in client.streamText(messages: [.init(role: "user", content: "hi")],
                                                     temperature: 1) {
                text += piece
            }
            return (text, nil)
        } catch {
            return (text, error)
        }
    }
}

// MARK: - 替身

/// 第一次：吐出半句就断线；之后：完整说完。每次都记下收到的上下文。
@MainActor
private final class CutOffOnceChatAI: AIService {
    static let half = "外婆的事"
    private(set) var contexts: [[AIChatMessage]] = []

    func analyze(content: String) async throws -> AIAnalysis { fatalError("聊天测试用不到") }
    func chat(messages: [AIChatMessage]) async throws -> String { fatalError("聊天测试用不到") }

    func chatstream(messages: [AIChatMessage]) -> AsyncThrowingStream<String, Error> {
        contexts.append(messages)
        let isFirst = contexts.count == 1
        return AsyncThrowingStream { c in
            if isFirst {
                c.yield(Self.half)
                c.finish(throwing: URLError(.networkConnectionLost))
            } else {
                c.yield("外婆的事还压着你吧。")
                c.finish()
            }
        }
    }
}

/// 吐出半句之后一直挂着、永远不结束 —— 母鸡说到一半，等用户关页面。
@MainActor
private final class HangingChatAI: AIService {
    static let half = "外婆的事"
    private(set) var calls = 0
    /// 流是不是因为「那头不要了」而结束的。onTermination 不在主线程上调，所以 nonisolated(unsafe)
    nonisolated(unsafe) private(set) var endedByCancel = false

    func analyze(content: String) async throws -> AIAnalysis { fatalError("聊天测试用不到") }
    func chat(messages: [AIChatMessage]) async throws -> String { fatalError("聊天测试用不到") }

    func chatstream(messages: [AIChatMessage]) -> AsyncThrowingStream<String, Error> {
        calls += 1
        return AsyncThrowingStream { c in
            c.onTermination = { [weak self] reason in
                if case .cancelled = reason { self?.endedByCancel = true }
            }
            c.yield(Self.half)
            // 故意不 finish
        }
    }
}

/// 让 onDelta 回调里够得着「这一轮」的 Task，好在半句上屏时取消它
@MainActor
private final class RoundBox {
    var round: Task<ChatMessageItem, Error>?
}

/// 假服务器：拦下发往 `host` 的请求，回 200 + 一段写死的 SSE，然后**干净地**关掉连接。
/// 注册在 URLProtocol 上对 `URLSession.shared` 生效 —— AIClient 流式走的正是它。
/// `nonisolated`：URLSession 在自己的线程上调这些方法，不能跟着工程默认隔离到主线程。
nonisolated private final class FakeSSEProtocol: URLProtocol {
    static let host = "sse.fake.invalid"
    nonisolated(unsafe) static var body = ""

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == host }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
