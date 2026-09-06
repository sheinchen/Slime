//
//  DayEggStore.swift
//  Slime
//
//  Created by shiying on 2026/8/26.
//

import Foundation
import CoreData

nonisolated struct DayEggRecord: Hashable {
    let date: Date
    let text: String
    let emotion: SlimeEmotion
    let createdAt: Date
}



protocol DayEggStore {
    func egg(for day: Date) -> DayEggRecord?
    func eggs(from start: Date, before end: Date) -> [Date:DayEggRecord]
    func save(text: String, emotion: SlimeEmotion, for day: Date)
    func delete(for day: Date)
    /// 关怀退场规则①：关怀之后诞生、且代表关怀那天或更晚的第一颗蛋。
    /// 补蛋也算 —— 只要它代表的日子没落在关怀之前。
    func firstEgg(bornAfter moment: Date, forDayOnOrAfter day: Date) -> DayEggRecord?
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
        saveIfNeeded()
    }
    
    /// 删掉某天的蛋。
    /// 两个用途：① 那天的日记被删光了，蛋成了孤儿 ② 测试时造「欠蛋」状态。
    func delete(for day: Date) {
        guard let egg = fetchObject(for: day) else { return }
        context.delete(egg)
        saveIfNeeded()
    }
    
    func firstEgg(bornAfter moment: Date, forDayOnOrAfter day: Date) -> DayEggRecord? {
        let request = NSFetchRequest<DayEgg>(entityName: "DayEgg")
        // 两个条件缺一不可：
        //   date >= day       —— 蛋代表的日子要在关怀之后（含当天），补旧账的蛋排除在外
        //   createdAt > moment —— 这颗蛋要是关怀之后才诞生的，否则关怀会被比它还老的蛋退掉
        request.predicate = NSPredicate(format: "date >= %@ AND createdAt > %@",
                                        day as NSDate, moment as NSDate)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first.map { DayEggRecord($0) }
    }
    
    private func saveIfNeeded() {
        guard context.hasChanges else { return }
        do { try context.save() } catch { print("蛋保存失败: \(error)") }
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

