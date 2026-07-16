//
//  Post+CoreDataProperties.swift
//  Slime
//
//  Created by shiying on 2026/7/4.
//
//

public import Foundation
public import CoreData


public typealias PostCoreDataPropertiesSet = NSSet

extension Post {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Post> {
        return NSFetchRequest<Post>(entityName: "Post")
    }

    @NSManaged public var content: String
    @NSManaged public var createdAt: Date
    @NSManaged public var id: UUID
    @NSManaged public var emotion: String
    @NSManaged public var reply: String?
}

extension Post : Identifiable {

}
