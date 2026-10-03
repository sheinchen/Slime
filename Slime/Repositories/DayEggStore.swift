//
//  DayEggStore.swift
//  Slime
//
//  Created by shiying on 2026/8/26.
//

import Foundation
import CoreData

nonisolated struct DayEggRecord: Hashable {
    /// 当前时区那一天的零点（库里存的是日历日期，仓库读出来时换算好，见 `DayStamp`）
    let date: Date
    let text: String
    let emotion: SlimeEmotion
    let createdAt: Date
}



protocol DayEggStore {
    func egg(for day: Date) -> DayEggRecord?
    func eggs(from start: Date, before end: Date) -> [Date:DayEggRecord]
    /// 存不进去会抛错，这颗蛋不留在库里。孵蛋那两条路（补蛋、按母鸡）本来就有「没孵出来」的处理，抛给它们就行
    func save(text: String, emotion: SlimeEmotion, for day: Date) throws
    func delete(for day: Date)
}

/// 进出这个类的「哪一天」都是**当前时区的零点**；库里的 `DayEgg.date` 是日历日期的新存法。
/// 换算只在这里做 —— 每个查询先 `stored(...)`、每条结果再 `local(...)`。漏一处，换了时区那处就对不上（10-02 修）。
final class CoreDataDayEggStore: DayEggStore {

    private let context: NSManagedObjectContext
    /// 「哪一天」按哪个时区换算。默认 `.current`，跟各页面、各 Service 用的同一个
    private let calendar: Calendar

    init(context: NSManagedObjectContext = CoreDataStack.shared.viewContext,
         calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }



    func egg(for day: Date) -> DayEggRecord? {
        fetchObject(for: day).map(record)
    }

    func eggs(from start: Date, before end: Date) -> [Date : DayEggRecord] {
        let request = NSFetchRequest<DayEgg>(entityName: "DayEgg")
        request.predicate = NSPredicate(format: "date >= %@ AND date < %@",
                                        stored(start) as NSDate, stored(end) as NSDate)
        let objects = (try? context.fetch(request)) ?? []
        // 同一天按理只有一颗（save 是先查后建），但库里没有唯一约束。万一有两颗，
        // 留孵得晚的那颗，跟 egg(for:) 挑的是同一颗。
        // 不能用 uniqueKeysWithValues：撞 key 直接崩，而打开 App 的补蛋每次都读这里 = 一开就崩
        return Dictionary(objects.map { egg in let r = record(egg); return (r.date, r) },
                          uniquingKeysWith: { a, b in a.createdAt >= b.createdAt ? a : b })
    }

    func save(text: String, emotion: SlimeEmotion, for day: Date) throws {
        let egg = fetchObject(for: day) ?? DayEgg(context: context)
        egg.date = stored(day)
        egg.text = text
        egg.emotion = emotion.rawValue
        egg.createdAt = Date()
        // 以前存失败只 print、照样返回 —— 按母鸡那边以为孵出来了，鸟巢刷新却还是空的，母鸡一句话不说
        try context.saveOrRollback()
    }

    /// 删掉某天的蛋。
    /// 两个用途：① 那天的日记被删光了，蛋成了孤儿 ② 测试时造「欠蛋」状态。
    func delete(for day: Date) {
        let request = NSFetchRequest<DayEgg>(entityName: "DayEgg")
        request.predicate = NSPredicate(format: "date == %@", stored(day) as NSDate)
        let objects = (try? context.fetch(request)) ?? []
        // 删这一天的全部，不是一颗。万一有重复，只删一颗的话剩下那颗会「复活」成那天的蛋
        for egg in objects { context.delete(egg) }
        saveIfNeeded()
    }

    /// 删蛋失败不往上抛：撤回之后那颗蛋还在，下次删日记 / 补蛋时会再处理
    private func saveIfNeeded() {
        do { try context.saveOrRollback() } catch { print("蛋保存失败，已撤回: \(error)") }
    }
    //MARK: -

    private func fetchObject(for day: Date) -> DayEgg? {
        let request = NSFetchRequest<DayEgg>(entityName: "DayEgg")
        request.predicate = NSPredicate(format: "date == %@", stored(day) as NSDate)
        // 万一同一天有两颗，固定取孵得最晚的，跟 eggs(from:before:) 取舍一致。
        // 不排序的话 fetchLimit = 1 取到哪颗是不确定的
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    /// 当前时区的某一天 → 库里的存法
    private func stored(_ day: Date) -> Date {
        DayStamp.stored(day, in: calendar.timeZone)
    }

    /// 托管对象变成值类型的唯一出口。日期在这里换回当前时区的零点
    private func record(_ egg: DayEgg) -> DayEggRecord {
        DayEggRecord(date: DayStamp.local(egg.date, in: calendar.timeZone),
                     text: egg.text,
                     emotion: SlimeEmotion(rawValue: egg.emotion) ?? .calm,
                     createdAt: egg.createdAt)
    }
}
