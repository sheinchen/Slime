//
//  StoreLoadTests.swift
//  SlimeTests
//
//  库打不开时（10-02）：不崩、不碰库文件、修好之后同一个 container 能再开一次。
//  以前 CoreDataStack 里是 fatalError —— 打不开就每次启动都崩。
//

import XCTest
import CoreData
@testable import Slime

@MainActor
final class StoreLoadTests: XCTestCase {

    func test_库文件坏了_报错不崩_文件原样留着_修好之后能重试() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Broken.sqlite")
        let garbage = Data("这不是一个数据库".utf8) + Data(repeating: 7, count: 4096)
        try garbage.write(to: url)

        let model = CoreDataStack.shared.persistentContainer.managedObjectModel
        let container = NSPersistentContainer(name: "Slime", managedObjectModel: model)
        container.persistentStoreDescriptions.first!.url = url

        XCTAssertNotNil(CoreDataStack.open(container), "打不开要报错，不是崩")
        XCTAssertTrue(container.persistentStoreCoordinator.persistentStores.isEmpty)
        XCTAssertEqual(try Data(contentsOf: url), garbage,
                       "打不开也不许动库文件 —— 真机上那里面是用户全部的日记")

        // 「修好了」：这里用挪走坏文件代替（真机上是用户清出了空间）。同一个 container 再开一次 ——
        // 「再试一次」按钮靠的就是这个，不用杀掉 App 重开
        try FileManager.default.removeItem(at: url)
        XCTAssertNil(CoreDataStack.open(container))
        XCTAssertFalse(container.persistentStoreCoordinator.persistentStores.isEmpty)
    }
}
