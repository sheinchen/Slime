//
//  AIService.swift
//  Slime
//
//  Created by shiying on 2026/7/15.
//

import Foundation

//MARK: - AI消息
struct AIChatMessage {
    let role:String
    let content: String
}
//MARK: - 错误类型
enum AIError: Error {
    case badStatus
    case emptyContent
}

protocol AIService {
    func analyze(content: String) async throws -> AIAnalysis
    //多轮聊天，组装上下文，返回回复
    func chat(messages: [AIChatMessage]) async throws -> String
    //流式聊天
    func chatstream(messages: [AIChatMessage]) -> AsyncThrowingStream<String, Error>
    
    
}

//总结一天
protocol DayEggSummarizing {
    func summarizeDay(_ entries: [SlimeItem]) async throws -> DayEggSummary
}

final class DeepSeekAIService: AIService, CareOpeningProvider,DayEggSummarizing {
    
    //共享人设
    private static let persona = """
    你是用户的一只呆萌的母鸡朋友,你喜欢说咕咕，说话软软的、暖暖的、有点憨憨的可爱感,像一个会关心人会感同身受的母鸡。语气轻松亲切,不端着、不说教。
"""
    
    //MARK: -关心prompt
    private static let carePrompt = persona + """
        我会告诉你"你为什么想关心ta"(这是内部原因,用户看不到),你把它化成一句自然、温柔的开场白。

        铁律(必须遵守):
        1. 探询不断言:说"最近好像…""感觉你…",不说"你一定""你肯定"。
        2. 绝不暴露你是怎么知道的:不许出现"连续几篇""检测到""记录显示""数据"这类词,一个都不行。
        3. 不说教、不给建议,只表达陪伴和在意。
        4. 只说一句话,简短口语化,像朋友凑过来轻声说的那种。
        5. 原因是低落时语气放轻放柔;原因是开心时可以活泼一点。

        只返回这句话本身,不要引号、不要 JSON、不要任何解释。
        """
    
    //MARK: - 主动关心服务
    func opening(for reason: CareReason) async throws -> String {
        let reasonText: String
        switch reason {
        case .lowMoodStreak:
            reasonText = "用户最近的几篇记录情绪都比较低落(难过/焦虑/疲惫),你想去轻轻陪一下ta。"
        case .moodRecovered:
            reasonText = "用户之前低落了一阵子,最新的记录情绪回暖了,你想表达你看见了、很高兴。"
        case .happyStreak:
            reasonText = "用户最近接连几篇都很开心,你想凑过去一起高兴。"
        }
        
        //组请求
        let url = URL(string: AIConfig.baseURL + "/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(AIConfig.apiKey)", forHTTPHeaderField: "Authorization")
        
        let body = ChatRequest(model: AIConfig.model,
                               messages: [
                                .init(role: "system", content: DeepSeekAIService.carePrompt ),
                                .init(role: "user", content: reasonText)
                               ],
                               response_format: .init(type: "text"),
                               temperature: 0.8,
                               stream: false)
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
        else {
            throw AIError.badStatus
        }
        
        let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let text = completion.choices.first?.message.content,
              !text.isEmpty else {
            throw AIError.emptyContent
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    
    func analyze(content: String) async throws -> AIAnalysis {
        //组请求
        let url = URL(string: AIConfig.baseURL + "/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(AIConfig.apiKey)", forHTTPHeaderField: "Authorization")
        
        let body = ChatRequest(
            model: AIConfig.model,
            messages: [
                .init(role: "system", content: Self.systemPrompt),
                .init(role: "user", content: content)
            ],
            response_format: .init(type: "json_object"),
            temperature: 0.7,
            stream: false
        )
        request.httpBody = try JSONEncoder().encode(body)
        
        //发请求
        let (data, response) = try await URLSession.shared.data(for: request)
        
        //检查状态码
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AIError.badStatus
        }
        
        let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard
            let contentJSON = completion.choices.first?.message.content,
            let innerData = contentJSON.data(using: .utf8)
        else {
            throw AIError.emptyContent
        }
        
        //解析内层
        let parsed = try JSONDecoder().decode(EmotionReplyDTO.self, from: innerData)
        let emotion = SlimeEmotion(rawValue: parsed.emotion) ?? .calm
        return AIAnalysis(emotion: emotion, reply: parsed.reply)
    }
    
    func summarizeDay(_ entries: [SlimeItem]) async throws -> DayEggSummary {
        guard !entries.isEmpty else { throw AIError.emptyContent }
        
        let url = URL(string: AIConfig.baseURL + "/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(AIConfig.apiKey)", forHTTPHeaderField: "Authorization")
        
        let body = ChatRequest(model: AIConfig.model,
                               messages: [.init(role: "system", content: Self.dayEggPrompt),
                                          .init(role: "user", content: Self.transcript(entries))],
                               response_format: .init(type: "json_object"),
                               temperature: 0.8,
                               stream: false)
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data,response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AIError.badStatus
        }
        
        let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let contentJson = completion.choices.first?.message.content,
              let innerData = contentJson.data(using: .utf8) else {
            throw AIError.emptyContent
        }
        
        let parsed = try JSONDecoder().decode(DayEggDTO.self, from: innerData)
        return DayEggSummary(text: parsed.text, emotion: SlimeEmotion(rawValue: parsed.emotion) ?? .calm)
    }
    
    /// 把一天的几篇日记排成给模型看的样子:时间 + 情绪 + 原文。
    private static func transcript(_ entries: [SlimeItem]) -> String {
        entries.map {
            "\(timeFormatter.string(from: $0.createdAt)) [\($0.emotion.rawValue)] \($0.content)"
        }.joined(separator: "\n")
    }
    
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
    
    //MARK: - 多轮聊天
    func chat(messages: [AIChatMessage]) async throws -> String {
        let url = URL(string: AIConfig.baseURL + "/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(AIConfig.apiKey)", forHTTPHeaderField: "Authorization")
        
        let body = ChatRequest(model: AIConfig.model,
                               messages: messages.map {
            .init(role: $0.role, content: $0.content)
        },
                               response_format: .init(type: "text"),
                               temperature: 1.0,
                               stream: false)
        
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data,response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw AIError.badStatus}
        let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let raw = completion.choices.first?.message.content else { throw AIError.emptyContent }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AIError.emptyContent }
        return text
    }
    
    //MARK: - 流式聊天
    func chatstream(messages: [AIChatMessage]) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let url = URL(string: AIConfig.baseURL + "/chat/completions")!
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Bearer \(AIConfig.apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept") //告诉服务器要SSE
                    
                    let body = ChatRequest(
                        model: AIConfig.model,
                        messages: messages.map {.init(role: $0.role, content: $0.content)},
                        response_format: .init(type: "text"),
                        temperature: 1.0,
                        stream: true
                    )
                    request.httpBody = try JSONEncoder().encode(body)
                    
                    //byte(for:)不等下载完，拿到持续字节流
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse,
                          (200..<300).contains(http.statusCode)
                    else { throw AIError.badStatus }
                    //lines自动处理网络包不一定是整句
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = line.dropFirst(6) //去掉data:
                        if payload == "[DONE]" { break } //结束
                        guard let data = payload.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data),
                              let piece = chunk.choices.first?.delta.content,
                              !piece.isEmpty else { continue }
                        continuation.yield(piece)
                        
                        
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
                
            }
        }
    }
    
    //流式返回的一片
    private struct StreamChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable { let content: String? }
            let delta: Delta
        }
        let choices: [Choice]
    }
    
    //MARK: -prompt
    static let chatSystemPrompt = persona + """
    你是一直母鸡朋友，内在朋友，内在自我，你想是一个人他自己自己看见的一个存在，你了解它，你治愈，你和他对话，对话规则(必须全部遵守):
    1. 安全底线最高:如果用户表达出严重低落、绝望或自我伤害的倾向,收起可爱腔,真诚温柔地回应,并温柔建议 ta 找信任的人或专业帮助聊聊。
    2. 短口语:符合人设发消息,一次只回一小段(一两句),绝不长篇大论。
    3. 禁止任何 Markdown 格式(不用 *、#、列表、编号),就是纯纯的聊天文字。
    4. 不说教、不给建议清单、不分析对错,陪伴优先:多听、多接住、少指导。
    5. 温柔收尾:如果用户表达想结束、或回复明显变少变短,自然地收尾(比如"嗯嗯,说出来一点点也很好啦~"),不追问、不挽留。
    6. 永远不暴露你的判断依据(不出现"连续几篇""记录"这类词)。
    """
    
    private static let systemPrompt = persona + """
        你的任务:读用户这句碎碎念,判断情绪,并以内在自我的身份回一句暖心话。reply 只回一句,简短。
        情绪 emotion 只能从这六个里选一个:happy / calm / sad / angry / anxious / tired。

        示例:
        用户:今天上班好累啊什么都不想干 → {"emotion":"tired","reply":"累累的一天辛苦啦,快靠过来歇一歇~"}
        用户:我今天吃到了超好吃的蛋糕! → {"emotion":"happy","reply":"哇是甜甜的一天!我也好想尝一口呀~"}
        用户:考试没考好有点难过 → {"emotion":"sad","reply":"没关系的呀,这次的小挫折我陪你一起消化掉~"}
        用户:明天要交东西还没做完好慌 → {"emotion":"anxious","reply":"别急别急,一件一件慢慢来,我陪着你~"}
        用户:今天什么事都没有,挺平静的 → {"emotion":"calm","reply":"平平淡淡也很好呀,这样的一天我很喜欢~"}
        用户:排队被人插队气死我了 → {"emotion":"angry","reply":"气鼓鼓的!换我也会生气的,拍拍你~"}

        安全底线(优先级高于软萌风格):如果用户表达出严重低落、绝望或自我伤害的倾向,不要用可爱语气,要真诚、温柔地回应,并温柔地建议 ta 找信任的人或专业帮助聊一聊。

        严格要求:只返回一个 JSON 对象,包含 emotion 和 reply 两个字段,不要任何多余文字,不要用 markdown 代码块包裹。
        """
    
    private static let dayEggPrompt = persona + """
        你的任务:读用户这一整天写的几篇碎碎念,把这一天收成一句话,并判断这一天整体的情绪。

        text 的要求:
        1. 一句话,不超过 25 个字。这是这一天的封面,不是流水账。
        2. 提炼这一天的"气质",不要罗列发生了什么,更不要逐条复述。但是总结要有帖子的影子
        3. 如果一天里情绪有起伏,写出那个走向(比如从忙乱到安静),不要只说最后一条。
        4. 用旁观的语气,温柔平和,像给这一天写的一句注脚。不要出现"你",不要对用户说话。
        5. 不说教、不给建议、不评价这一天好不好。

        emotion 是这一天的整体情绪,只能从这六个里选一个:happy / calm / sad / angry / anxious / tired。
        不是取最后一条,也不是取最强烈的那条,是这一天合起来的样子。

        示例:
        输入:
        08:30 [happy] 早上买到了想要的面包
        15:40 [tired] 会开了三个小时头很晕
        21:10 [calm] 晚上散步风很舒服
        输出:{"emotion":"calm","text":"咕咕，今天吃了好吃的又忙碌了一天，好想你，咕咕..我也想和你一起散步咕咕"}

        安全底线(优先级高于一切):如果这一天的内容里有严重低落、绝望或自我伤害的倾向,
        text 要真诚温和,不要把它轻盈化处理,emotion 如实标注。

        严格要求:只返回一个 JSON 对象,包含 emotion 和 text 两个字段,
        不要任何多余文字,不要用 markdown 代码块包裹。
        """

    
    

    
    //MARK: - 请求响应的数据结构
    private struct ChatRequest: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }
        struct ResponseFormat: Encodable { let type: String }
        let model: String
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
    
    private struct EmotionReplyDTO: Decodable {
        let emotion: String
        let reply: String
    }
    
    private struct DayEggDTO: Decodable {
        let emotion: String
        let text: String
    }
    
   

    
}

