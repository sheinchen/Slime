//
//  AIClient.swift
//  Slime
//
//  所有 AI 请求的唯一出口。
//

import Foundation

/// 跟模型服务打交道的那一层：拼请求、带鉴权、查状态码、拆外层信封、解析流式（SSE）。
///
/// **为什么单独一层**（09-25 从 DeepSeekAIService 里拆出来）：
/// 以前「拼 URL + 塞 Bearer key + 查状态码 + 解外层 JSON」在每个 AI 能力里各抄一遍，一共 7 处。
/// 拆出来之后，接后端中转（09-25）就只改了这一个文件，各能力一行没动。
///
/// **请求发给自己的中转（`relay/`），不直连 DeepSeek。** App 里没有 key，只带一个安装 ID；
/// 中转校验、限流、换上 key 和模型，再把 DeepSeek 的回复**原样边收边转**回来 ——
/// 所以下面的超时、SSE 解析跟直连时一模一样。
///
/// 它**不懂任何业务**：不知道 prompt、不知道情绪、不知道要解成什么结构。
/// 能力那一层（CareDecider / DayEggSummarizer / …）只告诉它三件事：
/// 发哪几条消息、要 JSON 还是文本、愿意等多久。
final class AIClient {

    /// 这次调用愿意等多久。**每个能力自己声明**，这里不替谁拿主意 ——
    /// 写日记、孵蛋、关怀、检索失败的代价各不一样，时限要分别想，别顺手套用。
    ///
    /// 标 `nonisolated`：它是纯值，而且要出现在默认参数里（默认参数在非隔离的上下文里求值）。
    nonisolated enum Patience {
        /// 空闲超时：连续这么多秒一个字节都没收到才算超时，有数据陆续到就重新计时。
        /// DeepSeek 拥堵时会先回 200、再不停发空行占着连接，所以用它**可能等很久**（最长 10 分钟）。
        case idle(TimeInterval)
        /// 总时限：从发出那一刻算总时长，到点抛 `URLError.timedOut`，不管中间有没有字节在到。
        case total(TimeInterval)

        /// 系统默认：60 秒空闲超时。
        static let standard = Patience.idle(60)
    }

    private let baseURL: String
    /// 中转按它限流（见 `AIConfig.installID`）
    private let installID: String
    /// 开发者通行证：带上它中转不限流。**只有 eval 测试会传**（重排 eval 并发 4 路，一分钟上百次），
    /// App 里永远是 nil —— 通行证要是进了 App，就跟以前的 key 一样人人都拿得到。
    private let devToken: String?
    /// 现在能不能往外发。每发一次都现问 —— 用户可能刚在设置里撤回了同意。
    /// AIClient 不知道「同意」是什么，它只认这一个是非题；规则在 AIConsent 里。
    private let isSendingAllowed: () -> Bool

    /// `isSendingAllowed` 必填、没有默认值：放行与否必须由调用方明说，
    /// 不能因为漏传一个参数就悄悄放行（App 里传同意状态，eval 传 `{ true }`）。
    /// 其余参数有默认值，能注入是为了测试：指向本地假服务器、带通行证。
    init(isSendingAllowed: @escaping () -> Bool,
         baseURL: String = AIConfig.baseURL,
         installID: String = AIConfig.installID,
         devToken: String? = nil) {
        self.isSendingAllowed = isSendingAllowed
        self.baseURL = baseURL
        self.installID = installID
        self.devToken = devToken
    }

    // MARK: - 三种调用

    /// 要一个 JSON 对象回来（`response_format = json_object`），解成 `T`。
    /// - Returns: 解好的值，连同模型原样写的那段 JSON —— 关怀和检索要把它原样记进日志 / debug 页。
    func requestJSON<T: Decodable>(_ type: T.Type,
                                   messages: [AIChatMessage],
                                   temperature: Double,
                                   patience: Patience = .standard) async throws -> (value: T, raw: String) {
        let raw = try await complete(messages, format: "json_object",
                                     temperature: temperature, patience: patience)
        let value = try JSONDecoder().decode(T.self, from: Data(raw.utf8))
        return (value, raw)
    }

    /// 要一段纯文本回来。原样返回，要不要去空白由调用方决定。
    func requestText(messages: [AIChatMessage],
                     temperature: Double,
                     patience: Patience = .standard) async throws -> String {
        try await complete(messages, format: "text", temperature: temperature, patience: patience)
    }

    /// 流式要纯文本（SSE）：模型写一小段就吐一小段。
    /// 用空闲超时 —— 流本来就是字节陆续在到，总时限会把一段长回复从中间掐断。
    func streamText(messages: [AIChatMessage], temperature: Double) -> AsyncThrowingStream<String, Error> {
        // 请求先在外面拼好，下面的 Task 只管收，不用捕获 self
        let request: URLRequest
        do {
            request = try makeRequest(messages, format: "text", temperature: temperature,
                                      stream: true, patience: .standard)
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    // bytes(for:) 不等下载完，拿到的是持续到来的字节流
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse,
                          (200..<300).contains(http.statusCode)
                    else { throw AIError.badStatus }
                    // 「连接关了」不等于「话说完了」。只有模型自己报 finish_reason == "stop" 才算说完 ——
                    // 没发 [DONE] 就断开、上游资源不足中断（insufficient_system_resource）、
                    // 写到长度上限（length），循环都会正常退出，但手上拿的是半句。
                    var finishReason: String?
                    // lines 负责把「网络包不一定是整句」拼成一行一行
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = line.dropFirst(6)              // 去掉 "data: "
                        if payload == "[DONE]" { break }             // 结束
                        guard let data = payload.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data),
                              let choice = chunk.choices.first else { continue }
                        // 最后一片通常内容为空、只带 finish_reason，所以不能先按「内容为空」跳过
                        if let reason = choice.finish_reason { finishReason = reason }
                        if let piece = choice.delta?.content, !piece.isEmpty {
                            continuation.yield(piece)
                        }
                    }
                    guard finishReason == "stop" else { throw AIError.incompleteStream }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            // 那头不收了（聊天页关了）就停掉请求
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - 私有

    private func complete(_ messages: [AIChatMessage],
                          format: String,
                          temperature: Double,
                          patience: Patience) async throws -> String {
        let request = try makeRequest(messages, format: format, temperature: temperature,
                                      stream: false, patience: patience)
        let (data, response) = try await session(for: patience).data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AIError.badStatus
        }
        // 外层信封 {"choices":[{"message":{"content":"…"}}]}，content 才是模型写的东西
        let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = completion.choices.first?.message.content else {
            throw AIError.emptyContent
        }
        return content
    }

    /// 拼一个发给中转的请求。跟直连 DeepSeek 时比只差两处：
    /// ① 没有 `Authorization: Bearer <key>`，换成 `X-Install-ID`（给限流用，不是凭证）
    /// ② 请求体里没有 `model` —— 中转决定用哪个模型，换模型不用发新版
    private func makeRequest(_ messages: [AIChatMessage],
                             format: String,
                             temperature: Double,
                             stream: Bool,
                             patience: Patience) throws -> URLRequest {
        // 同意这道闸放在这里：三种调用（JSON / 文本 / 流式）都要经过 makeRequest，
        // 所以不管哪个页面、哪条流程出了 bug，没同意时一个字节都出不了手机
        guard isSendingAllowed() else { throw AIError.notAllowed }

        // 路径跟 DeepSeek 的一样，中转只认这一个
        var request = URLRequest(url: URL(string: baseURL + "/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(installID, forHTTPHeaderField: "X-Install-ID")
        if let devToken {
            request.setValue(devToken, forHTTPHeaderField: "X-Dev-Token")
        }
        if stream {
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")   // 告诉服务器要 SSE
        }
        if case .idle(let seconds) = patience {
            request.timeoutInterval = seconds
        }
        request.httpBody = try JSONEncoder().encode(ChatRequest(
            messages: messages.map { .init(role: $0.role, content: $0.content) },
            response_format: .init(type: format),
            temperature: temperature,
            stream: stream))
        return request
    }

    /// 带总时限的 session，按秒数缓存 —— URLSession 要复用，别每次请求新建一个。
    private var totalSessions: [TimeInterval: URLSession] = [:]

    private func session(for patience: Patience) -> URLSession {
        // 空闲超时靠 request.timeoutInterval 就够了，用共享的那个
        guard case .total(let seconds) = patience else { return .shared }
        if let cached = totalSessions[seconds] { return cached }
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = seconds
        // waitsForConnectivity 保持默认 false：开了的话没网也要干等满时限，而现在没网是秒失败。
        let session = URLSession(configuration: config)
        totalSessions[seconds] = session
        return session
    }

    // MARK: - 线上格式（OpenAI 兼容的 /chat/completions）

    /// 发给中转的请求体。中转**只认这四个字段**，多塞的会被丢掉（见 relay/src/index.ts 的 rebuild）
    private struct ChatRequest: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }
        struct ResponseFormat: Encodable { let type: String }
        let messages: [Message]
        let response_format: ResponseFormat
        let temperature: Double
        let stream: Bool
    }

    private struct ChatCompletionResponse: Decodable {
        struct Choice: Decodable { let message: Message }
        struct Message: Decodable { let content: String }
        let choices: [Choice]
    }

    /// 流式返回的一片
    private struct StreamChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable { let content: String? }
            let delta: Delta?
            /// 只有最后一片有：stop = 说完了；length / insufficient_system_resource 等都是被掐断的
            let finish_reason: String?
        }
        let choices: [Choice]
    }
}
