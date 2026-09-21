//
//  SceneDelegate.swift
//  Slime
//
//  Created by shiying on 2026/7/4.
//

import UIKit
import CoreData

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    private var eggService: DayEggService?
    private var recallIndex: RecallIndexService?
    private var careEngine: CareEngine?
    private var careChecks: CareCheckStore?
    private weak var rootVC: RootTabBarController?
    

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // scene 是一个 UIWindowScene(带屏幕的场景),转型失败就不往下走
        guard let windowScene = (scene as? UIWindowScene) else { return }

        // 1. 用这个 scene 创建一块 window(App 的画布,所有界面都画在它上面)
        let window = UIWindow(windowScene: windowScene)

        // 组合根
        let postRepo = CoreDataPostRepository()
        let careMessages = CoreDataCareMessageStore()
        let eggStore = CoreDataDayEggStore()
        let aiService = DeepSeekAIService()
        let eggService = DayEggService(posts: postRepo, eggs: eggStore)
        
        let chatRepo = CoreDataChatRepository()
        
        // 模型只加载一次,两个 Service 共用。
        // 45MB 的 Core ML 模型建两遍既慢又白占内存。
        let embedder = try? TextEmbedder()
        let recallIndex = embedder.map { RecallIndexService(posts: postRepo, embedder: $0) }
        self.recallIndex = recallIndex
        // 加载失败就是 nil,聊天照常跑,只是母鸡不会提起旧事。
        let recallService = embedder.map {
            RecallService(posts: postRepo,
                          embedder: $0,
                          ai: aiService,
                          reranker: aiService)
        }
        
        let careChecks = CoreDataCareCheckStore()
        let careGate = CareGate(eggs: eggStore,
                                messages: careMessages,
                                checks: careChecks)
        let careEngine = CareEngine(gate: careGate,
                                    messages: careMessages,
                                    checks: careChecks,
                                    ai: aiService)


        let composeVM = ComposeViewModel(repository: postRepo, aiService: aiService)
        let squareVM = SquareViewModel(repository: postRepo, eggService: eggService)
        let homeVC = HomeViewController()
        homeVC.careViewModel = CareViewModel(messages: careMessages)

        // 图标先用 SF Symbols 占位 —— 换成自己的 icon 时只改这三个名字。
        // 右边那个圆不是 tab，是动作入口，去哪由这里决定。
        let rootVC = RootTabBarController(
            pages: [homeVC, SquareViewController(viewModel: squareVM)],
            icons: ["house.fill", "calendar"],
            accessoryIcon: "bubble.left.fill"
        )

        // 聊天现在有两个入口：首页点母鸡、tab 条右边那个圆。共用一份构造。
        let makeChat: () -> UIViewController = {
            let vm = ChatViewModel(origin: .direct,
                                   chatRepo: chatRepo,
                                   posts: postRepo,
                                   aiService: aiService,
                                   recall: recallService)
            return ChatViewController(viewModel: vm)
        }
        homeVC.makeChatViewController = makeChat
        rootVC.onAccessoryTap = { [weak rootVC] in
            rootVC?.present(makeChat(), animated: true)
        }

        homeVC.makeComposeViewController = { [weak rootVC] backdrop ,onClose in
            let vc =  ComposeViewController(viewModel: composeVM)
            vc.onClose = {
                onClose()
                rootVC?.broadcastDataChange()
            }
            vc.backdropImage = backdrop
            return vc
        }
        let navigationController = UINavigationController(rootViewController: rootVC)
        window.rootViewController = navigationController
        //测试seed
        #if DEBUG
        // 只在测试库上生效；正式库会被 DebugSeeder 自己挡掉，不用加判断。
        //
        // 两幕场景，用启动参数切（Edit Scheme → Run → Arguments）：
        //  第一幕（不加参数）：清库 + 播 5 天低落 → 闸门放行 → AI 生成关怀 A
        //  第二幕（加 -CareStep2）：保留 A，只把「昨天」重孵成 happy
        //      → 上次的关怀还挂着 + 今天有新蛋 → 看 AI 是保持 A 还是换成新的
        //  第三幕（加 -CareStep3）：保留上一幕的关怀，补一颗平淡的蛋
        //      → 有新蛋能过闸门，但没有实质变化 → 看 AI 是否保持、本地是否不误退场
        //
        // 另有一套跟关怀无关的（加 -SeedDiaries）：21 天里 14 天有记录、每篇一件具体的事，
        //  给验删除、卡片堆、周条、月历用。详见 DebugSeeder+Diaries.swift
        if CommandLine.arguments.contains("-SeedDiaries") {
            DebugSeeder.seedDiaries()
        } else if CommandLine.arguments.contains("-CareStep3") {
            DebugSeeder.hatchNow(daysAgo: 2, emotion: .calm,
                                 text: "普通的一天，把手边的事做完了")
        } else if CommandLine.arguments.contains("-CareStep2") {
            DebugSeeder.hatchNow(daysAgo: 1, emotion: .happy,
                                 text: "过了！晚上和朋友吃了顿好的")
        } else {
            DebugSeeder.reset(to: [.sad, .sad, .tired, .sad, .sad], withEggs: true)
        }
        #endif
        // 3. 让 window 显示出来,并持有它(存到属性里,不然会被释放)
        window.makeKeyAndVisible()
        self.window = window
        self.eggService = eggService
        self.careEngine = careEngine
        self.careChecks = careChecks
        self.rootVC = rootVC
        
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        Task { await onAppActive() }
    }
    
    private func onAppActive() async {
        if let eggService {
            let hatched = await eggService.hatchAllPending()
            if hatched > 0 { rootVC?.broadcastDataChange() }
        }
        // ② 再跑关怀
        await careEngine?.handle(.appOpened)
        // 关怀可能刚落库，通知首页看一眼 ——
        // 这个 Task 跑完时 viewDidAppear 早就过去了，不广播卡片就不会出现。
        rootVC?.broadcastDataChange()

        #if DEBUG
        if let c = careChecks?.recent(limit: 1).first {
            print("""

            ========== 🔍 关怀检查 ==========
            闸门: \(c.gatePassed ? "过" : "挡") \(c.gateReason ?? "")
            调AI: \(c.aiCalled)   耗时: \(c.latencyMs)ms
            展示: \(c.finalShown)  \(c.dropReason ?? "")
            原始: \(c.aiRaw ?? "-")
            ================================

            """)
        }
        #endif
        
        if let recallIndex {
            Task { await recallIndex.backfill() }
        }
    }


    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        // This may occur due to temporary interruptions (ex. an incoming phone call).
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
        // Use this method to undo the changes made on entering the background.
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        // Use this method to save data, release shared resources, and store enough scene-specific state information
        // to restore the scene back to its current state.

        // Save changes in the application's managed object context when the application transitions to the background.
        CoreDataStack.shared.saveContext()
    }


}
