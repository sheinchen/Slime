//
//  PostRepository.swift
//  Slime
//
//  Created by shiying on 2026/7/6.
//

import CoreData

protocol PostRepository {
    @discardableResult
    func create(content: String, emotion: SlimeEmotion, reply: String) -> Post
    func fetchAll() -> [Post]
    func delete(id: UUID)
    
    func recallCandidates(since: Date) -> [RecallCandidate]
    func postsMissingEmbedding(limit: Int) -> [(id: UUID, content: String)]
    func saveEmbeddings(_ vectors: [UUID: [Float]])
}

final class CoreDataPostRepository: PostRepository {
    
    private let context: NSManagedObjectContext
    
    //依赖注入 默认用共享栈的主context
    init(context: NSManagedObjectContext = CoreDataStack.shared.viewContext) {
        self.context = context
    }
    
    @discardableResult
    func create(content: String, emotion: SlimeEmotion, reply: String) -> Post {
        let post = Post(context: context)
        post.id = UUID()
        post.content = content
        post.createdAt = Date()
        post.dayKey = Calendar.current.startOfDay(for: post.createdAt)
        post.emotion = emotion.rawValue
        post.reply = reply
        saveIfNeeded() //落盘
        return post
    }
    
    func fetchAll() -> [Post] {
        let request = Post.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Post.createdAt, ascending: false)
        ]
        do {
            return try context.fetch(request)
        } catch {
            print("查询失败： \(error)")
            return []
        }
    }
    
    func delete(id: UUID) {
        let request = Post.fetchRequest()
        
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        
        if let post = try? context.fetch(request).first {
            context.delete(post)
            saveIfNeeded()
        }
    }
    
    func recallCandidates(since: Date) -> [RecallCandidate] {
        let request = Post.fetchRequest()
        request.predicate = NSPredicate(format: "createdAt >= %@", since as NSDate)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Post.createdAt, ascending: false)]

        return ((try? context.fetch(request)) ?? []).map { post in
            RecallCandidate(
                document: RecallDocument(
                    id: post.id,
                    // 用 dayKey 而不是 createdAt：命中之后要按「哪一天」取回整天的内容
                    date: post.dayKey ?? Calendar.current.startOfDay(for: post.createdAt),
                    text: post.content,
                    emotion: SlimeEmotion(rawValue: post.emotion) ?? .calm),
                vector: post.embedding?.vectorFloats)
        }
    }

    func postsMissingEmbedding(limit: Int) -> [(id: UUID, content: String)] {
        let request = Post.fetchRequest()
        request.predicate = NSPredicate(format: "embedding == nil")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Post.createdAt, ascending: false)]
        request.fetchLimit = limit
        return ((try? context.fetch(request)) ?? []).map { ($0.id, $0.content) }
    }

    func saveEmbeddings(_ vectors: [UUID: [Float]]) {
        guard !vectors.isEmpty else { return }
        let request = Post.fetchRequest()
        // 一次把这批全查回来。**别在循环里一篇一篇查** —— 两百篇就是两百次查询。
        request.predicate = NSPredicate(format: "id IN %@", Array(vectors.keys))
        for post in (try? context.fetch(request)) ?? [] {
            post.embedding = vectors[post.id]?.vectorData
        }
        saveIfNeeded()
    }
    
    //有改动，把内容写进磁盘
    private func saveIfNeeded() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            print("保存失败: \(error)")
        }
    }
}


