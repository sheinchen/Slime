//
//  CooldownStore.swift
//  Slime
//
//  Created by shiying on 2026/7/24.
//

import CoreData

//一条冷却值记录
struct CooldownRecord {
    let ruleId: String
    let lastTriggeredAt: Date
    let ignoredCount: Int
}

//冷却记录的读写
protocol CooldownStore {
    func lastTrigger(ruleId: String) -> CooldownRecord?
    func recordTrigger(ruleId: String, at date: Date)
    func markEngaged(ruleId: String) //用户点开 -> 归零
    func markIgnored(ruleId: String) // 忽略气泡
}

final class CoreDataCooldownStore: CooldownStore {
    
    private let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext = CoreDataStack.shared.viewContext) {
        self.context = context
    }
    
    func lastTrigger(ruleId: String) -> CooldownRecord? {
        guard let entity = fetchEntity(ruleId: ruleId) else { return  nil }
        return CooldownRecord (
            ruleId: entity.ruleId,
            lastTriggeredAt: entity.lastTriggeredAt,
            ignoredCount: Int(entity.ignoredCount))
    }
    
    //记一次触发
    func recordTrigger(ruleId: String, at date: Date) {
        let entity = fetchEntity(ruleId: ruleId) ?? RuleCooldown(context: context)
        entity.ruleId = ruleId
        entity.lastTriggeredAt = date
        saveIfNeeded()
    }
    
    func markEngaged(ruleId: String) {
        guard let entity = fetchEntity(ruleId: ruleId) else { return }
        entity.ignoredCount = 0
        saveIfNeeded()
    }
    
    func markIgnored(ruleId: String) {
        guard let entity = fetchEntity(ruleId: ruleId) else { return }
        entity.ignoredCount += 1
        saveIfNeeded()
    }
    
    // MARK: - 私有
    private func fetchEntity(ruleId: String) -> RuleCooldown? {
        let request = RuleCooldown.fetchRequest()
        request.predicate = NSPredicate(format: "ruleId == %@", ruleId)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }
    
    private func saveIfNeeded() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            print("冷却记录保存失败\(error)")
        }
    }
}
