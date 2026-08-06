//
//  ChatSession+CoreDataProperties.swift
//  Slime
//
//  Created by shiying on 2026/8/1.
//
//

public import Foundation
public import CoreData


public typealias ChatSessionCoreDataPropertiesSet = NSSet

extension ChatSession {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<ChatSession> {
        return NSFetchRequest<ChatSession>(entityName: "ChatSession")
    }

    @NSManaged public var id: UUID
    @NSManaged public var createdAt: Date
    @NSManaged public var careMessageId: UUID
    @NSManaged public var messages: NSSet?

}

// MARK: Generated accessors for messages
extension ChatSession {

    @objc(addMessagesObject:)
    @NSManaged public func addToMessages(_ value: ChatMessage)

    @objc(removeMessagesObject:)
    @NSManaged public func removeFromMessages(_ value: ChatMessage)

    @objc(addMessages:)
    @NSManaged public func addToMessages(_ values: NSSet)

    @objc(removeMessages:)
    @NSManaged public func removeFromMessages(_ values: NSSet)

}

extension ChatSession : Identifiable {

}
