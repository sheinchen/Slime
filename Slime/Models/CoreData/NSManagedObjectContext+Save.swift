//
//  NSManagedObjectContext+Save.swift
//  Slime
//

import CoreData

extension NSManagedObjectContext {

    /// 有改动就存；**存不进去就把这次的改动全部撤回**，再把错误交给调用方。
    ///
    /// 为什么要撤回（10-02）：以前各个仓库存失败只 print，没存上的改动还留在 context 里 ——
    /// · 写日记：页面上看着存上了，其实只在内存里，App 一被杀就没了
    /// · 下一次随便哪个仓库保存，都会带着这笔坏账一起存、一起失败 —— 一笔失败变成之后每一笔都失败
    /// · 切到后台时 `CoreDataStack.saveContext()` 也带着它再存一次，那里以前是 `fatalError`，App 直接崩
    ///
    /// 撤回只会撤掉「这一次」的：所有仓库都在主线程上、改完当场就存，
    /// context 里不会有别处攒着、还没来得及存的改动。
    ///
    /// ⚠️ **撤回之后，这次新插入的对象就废了**：属性读出来全是 nil，读非可选属性（比如 `id: UUID`）当场崩。
    /// 所以要返回的值得在调这个之前从对象上取好（10-02 聊天仓库「存完再读 id」就是这么崩过的，那个仓库 10-03 已删）
    func saveOrRollback() throws {
        guard hasChanges else { return }
        do {
            try save()
        } catch {
            rollback()
            throw error
        }
    }
}
