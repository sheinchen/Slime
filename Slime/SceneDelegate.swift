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
    private var careEngine: CareEngine?
    private var careChecks: CareCheckStore?
    private weak var rootVC: RootPagerViewController?

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
        
        let careChecks = CoreDataCareCheckStore()
        let careGate = CareGate(eggs: eggStore,
                                messages: careMessages,
                                checks: careChecks)
        let careEngine = CareEngine(gate: careGate,
                                    eggs: eggStore,
                                    messages: careMessages,
                                    checks: careChecks,
                                    ai: aiService)


        let composeVM = ComposeViewModel(repository: postRepo, aiService: aiService)
        let squareVM = SquareViewModel(repository: postRepo, eggService: eggService)
        let homeVC = HomeViewController()
        homeVC.careViewModel = CareViewModel(messages: careMessages)
        let rootVC = RootPagerViewController(pages: [homeVC,SquareViewController(viewModel: squareVM)])
        homeVC.makeComposeViewController = { [weak rootVC] backdrop ,onClose in
            let vc =  ComposeViewController(viewModel: composeVM)
            vc.onClose = {
                onClose()
                rootVC?.broadcastDataChange()
            }
            vc.backdropImage = backdrop
            return vc
        }
        homeVC.makeChatViewController = {
            let vm = ChatViewModel(origin: .direct, chatRepo: chatRepo, posts: postRepo, aiService: aiService)
            return ChatViewController(viewModel: vm)
        }
        
      
        let navigationController = UINavigationController(rootViewController: rootVC)
        window.rootViewController = navigationController
        //测试seed
        #if DEBUG
        // 只在测试库上生效；正式库会被 DebugSeeder 自己挡掉，不用加判断。
        DebugSeeder.reset(to: [.sad, .sad, .sad, .calm, .happy], withEggs: true)
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

