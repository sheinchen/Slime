//
//  CareCheck+CoreDataProperties.swift
//  Slime
//
//  Created by shiying on 2026/9/4.
//
//

public import Foundation
public import CoreData


public typealias CareCheckCoreDataPropertiesSet = NSSet

extension CareCheck {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CareCheck> {
        return NSFetchRequest<CareCheck>(entityName: "CareCheck")
    }

    @NSManaged public var id: UUID
    @NSManaged public var checkedAt: Date
    @NSManaged public var gatePassed: Bool
    @NSManaged public var gateReason: String?
    @NSManaged public var aiCalled: Bool
    @NSManaged public var aiRaw: String?
    @NSManaged public var latencyMs: Int32
    @NSManaged public var finalShown: Bool
    @NSManaged public var dropReason: String?

}

extension CareCheck : Identifiable {

}
