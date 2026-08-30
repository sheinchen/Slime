//
//  DayEgg+CoreDataProperties.swift
//  Slime
//
//  Created by shiying on 2026/8/26.
//
//

public import Foundation
public import CoreData


public typealias DayEggCoreDataPropertiesSet = NSSet

extension DayEgg {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<DayEgg> {
        return NSFetchRequest<DayEgg>(entityName: "DayEgg")
    }

    @NSManaged public var date: Date
    @NSManaged public var text: String
    @NSManaged public var emotion: String
    @NSManaged public var createdAt: Date

}

extension DayEgg : Identifiable {

}
