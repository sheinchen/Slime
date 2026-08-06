//
//  ChatRepository.swift
//  Slime
//
//  Created by shiying on 2026/8/1.
//

import CoreData

//聊天会话的存取
protocol ChatRepository {
    //会话匹配关心
    func findOrCreatedSession(careMessageId: UUID, now: Date) -> ChatSessionInfo
    //一个会话的全部消息
    func messages(sessionId: UUID) -> [ChatMessageItem]
    //新消息并且落库
    @discardableResult
    func append(sessionId: UUID, role: ChatRole, content: String, at date: Date) -> ChatMessageItem
    
}

final class CoreDataChatRepository: ChatRepository {
    
    private let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext = CoreDataStack.shared.viewContext) {
        self.context = context
    }
    
    func findOrCreatedSession(careMessageId: UUID, now: Date) -> ChatSessionInfo {
        if let existing = fetchSession(careMessageId: careMessageId) {
            return ChatSessionInfo(id: existing.id, careMessageId: existing.careMessageId, createdAt: existing.createdAt)
        }
        let s = ChatSession(context: context)
        s.id = UUID()
        s.careMessageId = careMessageId
        s.createdAt = now
        saveIfNeeded()
        return ChatSessionInfo(id: s.id, careMessageId: s.careMessageId, createdAt: s.createdAt)
        
    }
    
    func messages(sessionId: UUID) -> [ChatMessageItem] {
        guard let session = fetchSession(id: sessionId) else { return [] }
        let request = ChatMessage.fetchRequest()
        request.predicate = NSPredicate(format: "session == %@", session)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ChatMessage.createdAt, ascending: true)]
        let entities = (try? context.fetch(request)) ?? []
        return entities.map {
            ChatMessageItem(id: $0.id, role: ChatRole(rawValue: $0.role) ?? .slime, content: $0.content, createdAt: $0.createdAt)
        }
    }
    
    @discardableResult
    func append(sessionId: UUID, role: ChatRole, content: String, at date: Date) -> ChatMessageItem {
        let m = ChatMessage(context: context)
        m.id = UUID()
        m.role = role.rawValue
        m.content = content
        m.createdAt = date
        m.session = fetchSession(id: sessionId)
        saveIfNeeded()
        return ChatMessageItem(id: m.id, role: role, content: content, createdAt: date)
    }
    
    //MARK: - 私有
    private func fetchSession(id: UUID) -> ChatSession? {
        let request = ChatSession.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }
    
    private func fetchSession(careMessageId: UUID) -> ChatSession? {
        let request = ChatSession.fetchRequest()
        request.predicate = NSPredicate(format: "careMessageId == %@", careMessageId as CVarArg)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }
    
    private func saveIfNeeded() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            print("聊天记录保存失败\(error)")
        }
    }
}
