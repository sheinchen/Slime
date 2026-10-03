//
//  DayStampMigration.swift
//  Slime
//

import CoreData

/// 把老库里两列「哪一天」（`Post.dayKey`、`DayEgg.date`）换成新存法（见 `DayStamp`）。
///
/// 不是 Core Data 的模型迁移 —— 列的类型没变，只是值的含义变了，所以是打开库之后自己跑一遍数据。
/// 在 `CoreDataStack` 打开库之后、任何仓库读数据之前跑。
///
/// **跑多少遍都不会改坏**：`DayStamp.fromLegacy` 遇到已经是新存法的值原样返回。
/// 下面那个标记只是为了「迁过就别每次启动都扫一遍全表」，标记丢了顶多重扫一次。
enum DayStampMigration {

    /// 标记记在**库文件自己的 metadata** 里，不记在 UserDefaults：
    /// 正式库和测试库（`-UseTestStore`）共用一份 UserDefaults，记在那里的话迁了一个库，另一个会被当成迁过了
    static let metadataKey = "DayStampVersion"
    static let currentVersion = 1

    static func runIfNeeded(in context: NSManagedObjectContext, timeZone: TimeZone = .current) {
        guard let coordinator = context.persistentStoreCoordinator,
              let store = coordinator.persistentStores.first else { return }
        let originalMetadata = coordinator.metadata(for: store)
        guard (originalMetadata[metadataKey] as? Int ?? 0) < currentVersion else { return }
        var metadata = originalMetadata

        var changed = 0

        for post in (try? context.fetch(Post.fetchRequest())) ?? [] {
            // 更老的日记连 dayKey 都没有（以前靠「写下的时刻在当前时区算哪天」兜底）—— 顺手补上
            let newValue = post.dayKey.map { DayStamp.fromLegacy($0, currentTimeZone: timeZone) }
                ?? DayStamp.stored(post.createdAt, in: timeZone)
            if post.dayKey != newValue {
                post.dayKey = newValue
                changed += 1
            }
        }

        for egg in (try? context.fetch(NSFetchRequest<DayEgg>(entityName: "DayEgg"))) ?? [] {
            let newValue = DayStamp.fromLegacy(egg.date, currentTimeZone: timeZone)
            if egg.date != newValue {
                egg.date = newValue
                changed += 1
            }
        }

        // 标记跟数据一起写进库：metadata 会在下一次保存时落盘
        metadata[metadataKey] = currentVersion
        coordinator.setMetadata(metadata, for: store)

        do {
            try context.save()
            if changed > 0 { print("📅 「哪一天」换成新存法：改了 \(changed) 行") }
        } catch {
            // 存不进去就全部撤回、下次启动再来。不崩 —— 这时候最多是这次打开日历对不上，数据都还在。
            // **标记也要撤回**：metadata 是挂在内存里、等下一次保存才落盘的。不撤的话，
            // 用户接着写一篇日记、保存成功，「迁过了」就跟着写进库，老数据却没换 —— 以后再也不迁了
            context.rollback()
            coordinator.setMetadata(originalMetadata, for: store)
            print("📅 「哪一天」迁移没存进去，下次启动再试: \(error)")
        }
    }
}
