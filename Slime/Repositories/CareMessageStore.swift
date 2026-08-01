//
//  CareMessageStore.swift
//  Slime
//
//  Created by shiying on 2026/7/24.
//

import CoreData

protocol CareMessageStore {
    //当前该展示
    func active(now: Date) -> PendingCare?
    //存新的 返回被忽略的ruleId 交给引擎
    @discardableResult
    func save(ruleId: String, text: String, now: Date) -> [String]
    
    //清理超时未处理 返回被忽略的ruleId
    @discardableResult
    func sweepExpired(now: Date) -> [String]
    
    func updateStatus(id: UUID, to status: CareStatus)
}

final class CoreDataCareMessageStore: CareMessageStore {
    //关心时效
    private static let validity: TimeInterval = 3 * 24 * 60 * 60
    
    private let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext = CoreDataStack.shared.viewContext) {
        self.context = context
    }
    
    func active(now: Date) -> PendingCare? {
        let request = CareMessage.fetchRequest()
        let earliest = now.addingTimeInterval(-Self.validity)
        request.predicate = NSPredicate(
            format: "(status == %@ OR status == %@) AND createdAt >= %@", CareStatus.pending.rawValue,CareStatus.shown.rawValue, earliest as NSDate
        )
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CareMessage.createdAt, ascending: false)]
        request.fetchLimit = 1
        
        guard let e = try? context.fetch(request).first else { return nil}
        return PendingCare(id: e.id, ruleId: e.ruleId, text: e.text, createdAt: e.createdAt)
    }
    
    @discardableResult
    func save(ruleId: String, text: String, now: Date) -> [String] {
        //仲裁：先收尾旧记录，保证只有一条等着被看
        let ignoredRuleIds = closeOut(activeEntities(olderThan: nil))
        
        let e = CareMessage(context: context)
        e.id = UUID()
        e.ruleId = ruleId
        e.text = text
        e.createdAt = now
        e.status = CareStatus.pending.rawValue
        saveIfNeeded()
        return ignoredRuleIds
    }
    
    @discardableResult
    func sweepExpired(now: Date) -> [String] {
        let deadline = now.addingTimeInterval(-Self.validity)
        let ignoredRuleIds = closeOut(activeEntities(olderThan: deadline))
        saveIfNeeded()
        return ignoredRuleIds
    }
    
    func updateStatus(id: UUID, to status: CareStatus) {
        let request = CareMessage.fetchRequest()
        request.predicate = NSPredicate(format: "id = %@", id as CVarArg)
        request.fetchLimit = 1
        guard let e = try? context.fetch(request).first else { return }
        e.status = status.rawValue
        saveIfNeeded()
    }
    
     
    //MARK: - 私有
    private func activeEntities(olderThan date: Date?) -> [CareMessage] {
        let request = CareMessage.fetchRequest()
        if let date {
            request.predicate = NSPredicate(format: "(status == %@ OR status == %@) AND createdAt < %@", CareStatus.pending.rawValue, CareStatus.shown.rawValue, date as NSDate)
        } else {
            request.predicate = NSPredicate(format: "(status == %@ OR status == %@)", CareStatus.pending.rawValue, CareStatus.shown.rawValue)
        }
        return (try? context.fetch(request)) ?? []
    }
    
    
    // 给一批记录收尾:
    // - `shown`(露过面却没点开)→ 判为 ignored,返回它的 ruleId
    // - `pending`(用户压根没见过)→ 不算被忽略,直接删掉,不冤枉这条规则
    private func closeOut(_ entities: [CareMessage]) -> [String] {
        var ignoredRuleIds: [String] = []
        for e in entities {
            if e.status == CareStatus.shown.rawValue {
                e.status = CareStatus.ignored.rawValue
                ignoredRuleIds.append(e.ruleId)
            } else {
                context.delete(e)
            }
        }
        return ignoredRuleIds
    }
    
    private func saveIfNeeded() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            print("待送出关心保存失败\(error)")
        }
    }
    
    }

    
    
