//
//  DayEggStore.swift
//  Slime
//
//  Created by shiying on 2026/8/26.
//

import Foundation
import CoreData

struct DayEggRecord: Hashable {
    let date: Date
    let text: String
    let emotion: SlimeEmotion
    let createdAt: Date
}



protocol DayEggStore {
    func egg(for day: Date) -> DayEggRecord?
    func eggs(from start: Date, before end: Date) -> [Date:DayEggRecord]
    func save(text: String, emotion: SlimeEmotion, for day: Date)
}

final class CoreDataDayEggStore: DayEggStore {
    
    private let context: NSManagedObjectContext
    
    
    init(context: NSManagedObjectContext = CoreDataStack.shared.viewContext) {
        self.context = context
    }
    
    func egg(for day: Date) -> DayEggRecord? {
        fetchObject(for: day).map{ DayEggRecord($0) }
    }
    
    func eggs(from start: Date, before end: Date) -> [Date : DayEggRecord] {
        let request = NSFetchRequest<DayEgg>(entityName: "DayEgg")
        request.predicate = NSPredicate(format: "date >= %@ AND date < %@", start as NSDate, end as NSDate)
        let objects = (try? context.fetch(request)) ?? []
        return Dictionary(uniqueKeysWithValues: objects.map({
            ($0.date, DayEggRecord($0))
        }))
    }
    
    func save(text: String, emotion: SlimeEmotion, for day: Date) {
        let egg = fetchObject(for: day) ?? DayEgg(context: context)
        egg.date = day
        egg.text = text
        egg.emotion = emotion.rawValue
        egg.createdAt = Date()
        CoreDataStack.shared.saveContext()
    }
    //MARK: -
    
    private func fetchObject(for day: Date) -> DayEgg? {
        let request = NSFetchRequest<DayEgg>(entityName: "DayEgg")
        request.predicate = NSPredicate(format: "date == %@", day as NSDate)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }
}

private extension DayEggRecord {
    init(_ egg: DayEgg) {
        self.date = egg.date
        self.text = egg.text
        self.emotion = SlimeEmotion(rawValue: egg.emotion) ?? .calm
        self.createdAt = egg.createdAt
    }
}

