//
//  ComposeViewModel.swift
//  Slime
//
//  Created by shiying on 2026/7/6.
//

import Foundation

final class ComposeViewModel {
    
    //依赖协议，可以测试
    private let repository: PostRepository
    private let aiService: AIService
    
    init(repository: PostRepository = CoreDataPostRepository(),
         aiService: AIService = DeepSeekAIService()) {
        self.repository = repository
        self.aiService = aiService
    }
    
 
    
    //生成Slime 错误往上抛
    func generate(content: String) async throws -> SlimeItem {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        //调ai
        let analysis = try await aiService.analyze(content: trimmed)
       //成功即存库
        let post = repository.create(content: trimmed, emotion: analysis.emotion, reply: analysis.reply)
        return SlimeItem(id: post.id, content: post.content, createdAt: post.createdAt, emotion: analysis.emotion)
    }
}

