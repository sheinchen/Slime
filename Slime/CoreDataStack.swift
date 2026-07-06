//
//  CoreDataStack.swift
//  Slime
//
//  Created by shiying on 2026/7/5.
//

import CoreData

import Foundation

final class CoreDataStack {
    static let shared = CoreDataStack()
    private init() {}
    
    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "Slime")
        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                fatalError("Core Data 加载失败 \(error), \(error.userInfo)")
            }
        }
        return container
    }()
    
    var viewContext: NSManagedObjectContext {
        persistentContainer.viewContext
    }
    
    func saveContext() {
        let context = viewContext
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            let nserror = error as NSError
            fatalError("保存失败: \(nserror), \(nserror.userInfo)")
        }
    }
}

