//
//  CareMessage+CoreDataProperties.swift
//  Slime
//
//  Created by shiying on 2026/7/23.
//
//

public import Foundation
public import CoreData


public typealias CareMessageCoreDataPropertiesSet = NSSet

extension CareMessage {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CareMessage> {
        return NSFetchRequest<CareMessage>(entityName: "CareMessage")
    }

    @NSManaged public var id: UUID
    @NSManaged public var ruleId: String
    @NSManaged public var text: String
    @NSManaged public var status: String
    @NSManaged public var createdAt: Date
    @NSManaged public var retiredAt: Date?
    @NSManaged public var referencedDates: String?
    /// 这条话第一次真正被看到的时刻。nil = 还没被看到过 → 下次露面仍是「她刚开口」。
    /// 可选：老库里的行迁移过来就是 nil，正好等于「都还没看过」，语义天然正确。
    @NSManaged public var firstSeenAt: Date?

}

extension CareMessage : Identifiable {

}
