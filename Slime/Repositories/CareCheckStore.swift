//
//  CareCheckStore.swift
//  Slime
//
//  Created by shiying on 2026/9/4.
//

import Foundation
import CoreData

nonisolated struct CareCheckRecord {
    let id: UUID
    let checkedAt: Date

    var gatePassed: Bool = false
    var gateReason: String?        // 被闸门哪一条挡下的
    var aiCalled: Bool = false
    var aiRaw: String?             // AI 原始返回，调试用
    var latencyMs: Int = 0
    var finalShown: Bool = false
    var dropReason: String?        // 过了 AI 却被产品边界丢掉的原因

    init(id: UUID = UUID(), checkedAt: Date = Date()) {
        self.id = id
        self.checkedAt = checkedAt
    }
}

protocol CareCheckStore {
    func record(_ check: CareCheckRecord)
    /// 闸门条件①要的「上次检查时间」—— 派生自日志，不单独存状态
    func lastCheckedAt() -> Date?
    /// debug 页用
    func recent(limit: Int) -> [CareCheckRecord]
}

final class CoreDataCareCheckStore: CareCheckStore {

    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext = CoreDataStack.shared.viewContext) {
        self.context = context
    }

    func record(_ check: CareCheckRecord) {
        let e = CareCheck(context: context)
        e.id = check.id
        e.checkedAt = check.checkedAt
        e.gatePassed = check.gatePassed
        e.gateReason = check.gateReason
        e.aiCalled = check.aiCalled
        e.aiRaw = check.aiRaw
        e.latencyMs = Int32(check.latencyMs)
        e.finalShown = check.finalShown
        e.dropReason = check.dropReason
        saveIfNeeded()
    }

    func lastCheckedAt() -> Date? {
        let request = CareCheck.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CareCheck.checkedAt, ascending: false)]
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first?.checkedAt
    }

    func recent(limit: Int) -> [CareCheckRecord] {
        let request = CareCheck.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CareCheck.checkedAt, ascending: false)]
        request.fetchLimit = limit
        return ((try? context.fetch(request)) ?? []).map { CareCheckRecord($0)}
    }

    private func saveIfNeeded() {
        guard context.hasChanges else { return }
        do { try context.save() } catch { print("检查日志保存失败: \(error)") }
    }
}

private extension CareCheckRecord {
    init(_ e: CareCheck) {
        self.init(id: e.id, checkedAt: e.checkedAt)
        self.gatePassed = e.gatePassed
        self.gateReason = e.gateReason
        self.aiCalled = e.aiCalled
        self.aiRaw = e.aiRaw
        self.latencyMs = Int(e.latencyMs)
        self.finalShown = e.finalShown
        self.dropReason = e.dropReason
    }
}
