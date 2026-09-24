//
//  CareMessageStore.swift
//  Slime
//
//  Created by shiying on 2026/7/24.
//

import CoreData

#if DEBUG
/// debug 页要看的完整一行 —— 比 `PendingCare` 多了退场时刻和引用日期。
nonisolated struct CareMessageDebugRow {
    let text: String
    let status: String
    let createdAt: Date
    let firstSeenAt: Date?
    let retiredAt: Date?
    let referencedDates: [Date]
}
#endif

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
    
    /// 最近几条关怀，带「是否仍挂着」。给 AI 判断该保持还是该换。
    func recentCares(limit: Int) -> [PastCare]

#if DEBUG
    /// 全部关怀,给 debug 页看。**只在 Debug 构建里存在。**
    ///
    /// 为什么不让正式路径拿到它:`CareCardView` 的注释里写着 ——
    /// UI 拿到的 `PendingCare` 故意不带 `referencedDates`,
    /// 「绝不暴露判断依据」这条铁律是**在数据结构上锁死的**,view 想漏也漏不出来。
    /// 这个方法把锁打开了,所以它必须留在 `#if DEBUG` 里面。
    func allForDebug(limit: Int) -> [CareMessageDebugRow]
#endif

    /// 记下这条话**第一次真正被看到**的时刻。
    ///
    /// 「真正被看到」不等于「播过动画」：用户一开 App 就点鸟巢，卡片刚滑出就被
    /// `dismissCare()` 收掉了 —— 那次不算。判定在 UI 层（滑出后活满几秒才调这里）。
    ///
    /// **幂等**：已经有值就不覆盖。记的是第一次，不是最近一次。
    func markFirstSeen(id: UUID, at date: Date)
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
          return PendingCare(id: e.id, text: e.text, createdAt: e.createdAt, firstSeenAt: e.firstSeenAt)
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
    
#if DEBUG
    func allForDebug(limit: Int) -> [CareMessageDebugRow] {
        let request = CareMessage.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CareMessage.createdAt, ascending: false)]
        request.fetchLimit = limit
        return ((try? context.fetch(request)) ?? []).map {
            CareMessageDebugRow(text: $0.text,
                                status: $0.status,
                                createdAt: $0.createdAt,
                                firstSeenAt: $0.firstSeenAt,
                                retiredAt: $0.retiredAt,
                                referencedDates: Self.decode($0.referencedDates))
        }
    }
#endif

    func markFirstSeen(id: UUID, at date: Date) {
        let request = CareMessage.fetchRequest()
        // 按 id 查，不按 status —— 卡片露面到写这一笔之间隔着几秒，
        // 这中间引擎完全可能已经把它换掉了。那时候要写的仍是**它**，不是新上任的那条。
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        guard let e = try? context.fetch(request).first else { return }
        guard e.firstSeenAt == nil else { return }   // 幂等：只记第一次
        e.firstSeenAt = date
        saveIfNeeded()
    }

    func recentCares(limit: Int) -> [PastCare] {
            let request = CareMessage.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(keyPath: \CareMessage.createdAt, ascending: false)]
            request.fetchLimit = limit
            return ((try? context.fetch(request)) ?? []).map {
                PastCare(text: $0.text, stillShowing: $0.status == CareStatus.shown.rawValue, saidAt: $0.createdAt, about: Self.decode($0.referencedDates))
            }
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
           dates.map { dayFormatter.string(from: $0) }.joined(separator: ",")
       }
    
    private static func decode(_ raw: String?) -> [Date] {
        guard let raw, !raw.isEmpty else { return [] }
        return raw.split(separator: ",").compactMap {
            dayFormatter.date(from: String($0))
        }
    }

       /// 和 AIService 里那个是同一个约定：yyyy-MM-dd、锁 en_US_POSIX、**跟随本地时区**。
       /// 蛋的 date 是 Calendar.current.startOfDay（本地零点），格式化必须用同一个时区，
       /// 否则 UTC+8 会整体往前差一天。
       /// （原来用的 ISO8601DateFormatter 默认时区是 GMT —— 这是它和 DateFormatter 最坑的区别。）
    private static let dayFormatter: DateFormatter = {
       let f = DateFormatter()
       f.dateFormat = "yyyy-MM-dd"
       f.locale = Locale(identifier: "en_US_POSIX")
       return f
    }()
    

    
    private func saveIfNeeded() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            print("待送出关心保存失败\(error)")
        }
    }
    
}

    
    
