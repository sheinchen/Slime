//
//  RuleCooldown+CoreDataProperties.swift
//  Slime
//
//  Created by shiying on 2026/7/23.
//
//

public import Foundation
public import CoreData


public typealias RuleCooldownCoreDataPropertiesSet = NSSet

extension RuleCooldown {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<RuleCooldown> {
        return NSFetchRequest<RuleCooldown>(entityName: "RuleCooldown")
    }

    @NSManaged public var ruleId: String
    @NSManaged public var lastTriggeredAt: Date
    @NSManaged public var ignoredCount: Int16

}

extension RuleCooldown : Identifiable {

}
