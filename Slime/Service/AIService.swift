//
//  AIService.swift
//  Slime
//
//  Created by shiying on 2026/7/15.
//

import Foundation

protocol AIService {
    func analyze(content: String) async throws -> AIAnalysis
}

final class DeepSeekAIService: AIService {
    
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
    
    //MARK: -prompt
    private static let systemPrompt = """
        你是用户的一只软萌史莱姆朋友,说话软软的、暖暖的、有点憨憨的可爱感,像一个会关心人的小团子。语气轻松亲切,不端着、不说教。reply 只回一句,简短。

        你的任务:读用户这句碎碎念,判断情绪,并以史莱姆的身份回一句暖心话。
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
    
    
    //MARK: - 错误类型
    enum AIError: Error {
        case badStatus
        case emptyContent
    }
    
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
}
