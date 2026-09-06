//
//  CareMessageStore.swift
//  Slime
//
//  Created by shiying on 2026/7/24.
//

import CoreData

protocol CareMessageStore {
    /// 当前挂着的那条。**纯查 status，不做时间判断** ——
    /// 该不该退场是引擎的事：两条退场规则要跨表看蛋，仓库的谓词表达不了。
    func active() -> PendingCare?

    /// 落库一条新关怀。生成即展示，所以叫 show 不叫 save。
    /// referencedDates 只进库（第 8 步靠它沉淀回那几天的蛋），**不给 UI**。
    func show(text: String, referencedDates: [Date], now: Date)

    /// 让当前挂着的那条退场在 `date` 这一刻。没有挂着的就什么都不做。
    func retire(at date: Date)

    /// 冷却期的锚点：最新一条已退场关怀的退场时刻。
    func lastRetiredAt() -> Date?
}



final class CoreDataCareMessageStore: CareMessageStore {
    /// 关怀挂 3 天。这个数同时是「内容保质期」和「露面次数上限」，不要放大。
      private static let validity: TimeInterval = 3 * 24 * 60 * 60

      private let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext = CoreDataStack.shared.viewContext) {
        self.context = context
    }
    
    func active() -> PendingCare? {
          let request = CareMessage.fetchRequest()
          request.predicate = NSPredicate(format: "status == %@", CareStatus.shown.rawValue)
          request.sortDescriptors = [NSSortDescriptor(keyPath: \CareMessage.createdAt, ascending: false)]
          request.fetchLimit = 1
          guard let e = try? context.fetch(request).first else { return nil }
          return PendingCare(id: e.id, text: e.text, createdAt: e.createdAt)
      }
    
    func show(text: String, referencedDates: [Date], now: Date) {
            // 仲裁：先把还挂着的收掉，保证同时只有一条 shown。
            // 正常走不到这儿（闸门第 0 条已经挡了），是防御。
            shownEntities().forEach { retire($0, at: now) }

            let e = CareMessage(context: context)
            e.id = UUID()
            e.ruleId = ""                       // v2 没有规则了；字段留着不迁移，写空
            e.text = text
            e.createdAt = now
            e.status = CareStatus.shown.rawValue
            e.referencedDates = Self.encode(referencedDates)
            saveIfNeeded()
        }
    
    func retire(at date: Date) {
          shownEntities().forEach { retire($0, at: date) }
          saveIfNeeded()
      }
    
    func lastRetiredAt() -> Date? {
         let request = CareMessage.fetchRequest()
         request.predicate = NSPredicate(format: "retiredAt != nil")
         request.sortDescriptors = [NSSortDescriptor(keyPath: \CareMessage.retiredAt, ascending: false)]
         request.fetchLimit = 1
         return (try? context.fetch(request))?.first?.retiredAt
     }
    
 
    
     
    //MARK: - 私有
    private func shownEntities() -> [CareMessage] {
          let request = CareMessage.fetchRequest()
          request.predicate = NSPredicate(format: "status == %@", CareStatus.shown.rawValue)
          return (try? context.fetch(request)) ?? []
      }
    
    private func retire(_ e: CareMessage, at date: Date) {
          e.status = CareStatus.retired.rawValue
          e.retiredAt = date
      }
    
    private static func encode(_ dates: [Date]) -> String {
          let f = ISO8601DateFormatter()
          f.formatOptions = [.withFullDate]
          return dates.map { f.string(from: $0) }.joined(separator: ",")
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

    
    
