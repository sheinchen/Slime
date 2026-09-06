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

}

extension CareMessage : Identifiable {

}
