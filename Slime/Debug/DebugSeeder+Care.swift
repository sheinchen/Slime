//
//  DebugSeeder+Care.swift
//  Slime
//
//  关怀系统专用的时钟钩子。
//

#if DEBUG
import CoreData

extension DebugSeeder {

    /// 把当前挂着的那条关怀「变老」—— `createdAt` 往前推 `days` 天。
    ///
    /// 用来验 `CareEngine.retireIfNeeded` 里唯一剩下的那条本地规则：**满 3 天必退**。
    /// 那条规则是断网兜底（AI 不可达时关怀不能永远挂在那儿），
    /// 正常路径下要等三个自然日才碰得到 —— 手工验不了，只能把时钟往回拨。
    ///
    /// **它不加新蛋**，这是有意的。所以退场之后闸门①（自上次检查后没有新蛋）会挡下，
    /// 这一幕的正确结果是「卡片消失 + 不立刻冒出新的一条」。
    ///
    /// 接着上第三幕 `-CareFlat` 补一颗新蛋，**闸门会放行、会调 AI**（09-23 实测）——
    /// 这时 `recentlySaid` 里是一条「已经撤下了」的旧话，正好是 eval #37~#40 那个状态。
    /// ⚠️ 原来这里写的是「那时该被闸门③挡住」，那是**冷却还是 3 天时候的话**；
    ///    现在是 1 天，推老 4 天后退场时刻正好落在昨天，`daysSinceRetire = 1` 直接过关。
    ///
    /// 只改 `createdAt`，不碰 `status` / `retiredAt` —— 退场是 `CareEngine` 的活，
    /// 这里只负责把它推到该退场的位置上，让引擎自己去判。
    static func ageActiveCare(byDays days: Int = 4,
                              calendar: Calendar = .current,
                              context: NSManagedObjectContext = CoreDataStack.shared.viewContext) {
        guard guardTestStore() else { return }

        let request = CareMessage.fetchRequest()
        request.predicate = NSPredicate(format: "status == %@", CareStatus.shown.rawValue)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CareMessage.createdAt, ascending: false)]
        request.fetchLimit = 1

        guard let care = try? context.fetch(request).first else {
            print("⏰ 没有挂着的关怀可以变老 —— 先跑一次 -SeedLife 让它说出第一句")
            return
        }

        guard let aged = calendar.date(byAdding: .day, value: -days, to: care.createdAt) else { return }
        care.createdAt = aged
        saveIfNeeded(context)
        print("⏰ 关怀往前推了 \(days) 天 → 生成于 \(aged)，这次打开应该被判退场")
    }
}
#endif
