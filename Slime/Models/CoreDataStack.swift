//
//  CoreDataStack.swift
//  Slime
//
//  Created by shiying on 2026/7/5.
//

import CoreData
import Foundation


nonisolated enum StoreMode {
    /// 正式库：Application Support/Slime.sqlite —— 用户真数据
    case persistent
    /// 测试库：Application Support/Slime-Test.sqlite —— 独立文件，跨启动保留
    case testFile
    /// 内存库：写到 /dev/null，进程一结束就没了
    case inMemory
    
    static func detect() -> StoreMode {
        #if DEBUG
        // 跑单元测试时 XCTest 会注入这个环境变量 → 一律用内存库，
        // 保证测试之间互不污染，也绝不碰你的真数据。
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return .inMemory
        }
        if ProcessInfo.processInfo.arguments.contains("-UseTestStore")
        {
            return .testFile
        }
        #endif
        return .persistent
    }
}

final class CoreDataStack {
    static let shared = CoreDataStack(mode: StoreMode.detect())
    
    let mode: StoreMode
    
    private init(mode: StoreMode) {
        self.mode = mode
    }
    
    static let testStoreURL = NSPersistentContainer.defaultDirectoryURL.appendingPathComponent("Slime-Test.sqlite")
    
    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "Slime")
        
        if let description = container.persistentStoreDescriptions.first {
            switch mode {
            case . persistent:
                break
            case .testFile:
                description.url = Self.testStoreURL
            case .inMemory:
                description.url = URL(fileURLWithPath: "/dev/null")
            }
        }
        
        container.loadPersistentStores { description, error in
            if let error = error as NSError? {
                fatalError("Core Data 加载失败 \(error), \(error.userInfo)")
            }
            print("📦 store = \(self.mode)  →  \(description.url?.lastPathComponent ?? "?")")
        }
        return container
    }()
    
    var viewContext: NSManagedObjectContext {
        persistentContainer.viewContext
    }
    
    func saveContext() {
        let context = viewContext
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            let nserror = error as NSError
            fatalError("保存失败: \(nserror), \(nserror.userInfo)")
        }
    }
}

