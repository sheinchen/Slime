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
        // 启动参数统一在 LaunchOptions 里解析（上面那条 XCTest 是环境变量，不是用户开关，留在这）
        if LaunchOptions.current.useTestStore {
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

    /// 上一次打开库失败的原因。nil = 打开了。
    ///
    /// 库打不开时**不崩**（10-02 改）：以前这里是 `fatalError` —— 一旦打不开（迁移失败、手机空间满了、文件坏了），
    /// **每次打开 App 都崩**，用户连自己的日记都看不到，也不知道发生了什么。
    /// 现在记下错误，由 SceneDelegate 换成一页「日记本打不开了」，可以再试一次。
    private(set) var loadError: Error?

    /// 库打开了没有。SceneDelegate 第一件事就问它：没打开，仓库、页面、补蛋一样都不建
    var isLoaded: Bool {
        !persistentContainer.persistentStoreCoordinator.persistentStores.isEmpty
    }
    
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
        loadError = Self.open(container)
        if let loadError {
            print("📦 库打不开: \(loadError)")
        } else {
            print("📦 store = \(mode)  →  \(container.persistentStoreDescriptions.first?.url?.lastPathComponent ?? "?")")
        }
        return container
    }()

    /// 再试一次打开库（「日记本打不开了」那一页的按钮）。用户清出空间之类的之后，不用杀掉 App 重开
    /// - Returns: 这次打开了没有
    func retryLoad() -> Bool {
        guard !isLoaded else { return true }
        loadError = Self.open(persistentContainer)
        return isLoaded
    }

    /// 打开库 + 把老数据迁好。失败返回错误，**不碰库文件** ——
    /// 网上常见的「打不开就删掉重建」在这里绝对不能用：删掉的是用户全部的日记。
    /// 打不开的原因（空间不够、迁移失败）多半是能修好的，文件留着，修好了再打开就都在
    ///
    /// 拆成静态函数是为了能测：拿一个坏文件喂给它，看它不崩、不改文件、能重试（`StoreLoadTests`）
    static func open(_ container: NSPersistentContainer) -> Error? {
        var failure: Error?
        // 默认是同步加载（shouldAddStoreAsynchronously = false），回调在这一行返回之前就跑完了
        container.loadPersistentStores { _, error in
            if let error { failure = error }
        }
        if let failure { return failure }
        // 库打开之后、任何仓库读数据之前：把老库的「哪一天」换成新存法（见 DayStamp）。
        // 迁过的库只读一下 metadata 就返回，不拖冷启动
        DayStampMigration.runIfNeeded(in: container.viewContext)
        return nil
    }
    
    var viewContext: NSManagedObjectContext {
        persistentContainer.viewContext
    }
    
    /// 切到后台时的保底。正常情况下各个仓库改完当场就存了，这里没东西可存。
    ///
    /// 存不进去**不崩**，撤回、记一笔（10-02 改）。以前这里是 `fatalError`：仓库存失败只 print、
    /// 坏掉的改动留在 context 里，切后台时在这里再存一次、再失败 —— 一次没存上，变成每次切后台都崩
    func saveContext() {
        do {
            try viewContext.saveOrRollback()
        } catch {
            print("切后台保存失败，已撤回: \(error)")
        }
    }
}
