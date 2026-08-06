//
//  ChatMessage+CoreDataProperties.swift
//  Slime
//
//  Created by shiying on 2026/8/1.
//
//

public import Foundation
public import CoreData


public typealias ChatMessageCoreDataPropertiesSet = NSSet

extension ChatMessage {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<ChatMessage> {
        return NSFetchRequest<ChatMessage>(entityName: "ChatMessage")
    }

    @NSManaged public var id: UUID
    @NSManaged public var role: String
    @NSManaged public var content: String
    @NSManaged public var createdAt: Date
    @NSManaged public var session: ChatSession?

}

extension ChatMessage : Identifiable {

}
