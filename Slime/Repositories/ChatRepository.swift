//
//  ChatRepository.swift
//  Slime
//
//  Created by shiying on 2026/8/1.
//

import CoreData

//聊天会话的存取
protocol ChatRepository {
    //一个会话的全部消息
    func messages(sessionId: UUID) -> [ChatMessageItem]
    //新消息并且落库
    @discardableResult
    func append(sessionId: UUID, role: ChatRole, content: String, at date: Date) -> ChatMessageItem
    //对话开始
    func createSession(careMessageId: UUID?, now: Date) -> ChatSessionInfo
    //会话列表活跃排序
    func recentSessions(limit: Int) -> [ChatSessionInfo]
    func updateTitle(sessionId: UUID, title: String)
}

final class CoreDataChatRepository: ChatRepository {
    
    private let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext = CoreDataStack.shared.viewContext) {
        self.context = context
    }
    
    func createSession(careMessageId: UUID?, now: Date) -> ChatSessionInfo {
        let s = ChatSession(context: context)
        s.id = UUID()
        s.careMessageId = careMessageId
        s.createdAt = now
        s.updatedAt = now
        saveIfNeeded()
        return ChatSessionInfo(s)
    }
    
    func recentSessions(limit: Int) -> [ChatSessionInfo] {
        let request = ChatSession.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \ChatSession.updatedAt, ascending: false)
        ]
        request.fetchLimit = limit
        return ((try? context.fetch(request)) ?? []).map {
            ChatSessionInfo($0)
        }
    }
    
    func updateTitle(sessionId: UUID, title: String) {
        guard let s = fetchSession(id: sessionId) else { return }
        s.title = title
        saveIfNeeded()
        
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
        let session = fetchSession(id: sessionId)
        m.session = session
        session?.updatedAt = date
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
    
    
    private func saveIfNeeded() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            print("聊天记录保存失败\(error)")
        }
    }
}

private extension ChatSessionInfo {
    init(_ s: ChatSession) {
        self.id = s.id
        self.careMessageId = s.careMessageId
        self.title = s.title
        self.createdAt = s.createdAt
        self.updatedAt = s.updatedAt
    }
}
