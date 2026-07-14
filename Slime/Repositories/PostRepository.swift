//
//  PostRepository.swift
//  Slime
//
//  Created by shiying on 2026/7/6.
//

import CoreData

protocol PostRepository {
    @discardableResult
    func create(content: String, emotion: SlimeEmotion) -> Post
    func fetchAll() -> [Post]
    func delete(id: UUID)
}

final class CoreDataPostRepository: PostRepository {
    
    private let context: NSManagedObjectContext
    
    //依赖注入 默认用共享栈的主context
    init(context: NSManagedObjectContext = CoreDataStack.shared.viewContext) {
        self.context = context
    }
    
    @discardableResult
    func create(content: String, emotion: SlimeEmotion) -> Post {
        let post = Post(context: context)
        post.id = UUID()
        post.content = content
        post.createdAt = Date()
        post.emotion = emotion.rawValue
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


