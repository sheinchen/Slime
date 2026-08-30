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


    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // scene 是一个 UIWindowScene(带屏幕的场景),转型失败就不往下走
        guard let windowScene = (scene as? UIWindowScene) else { return }

        // 1. 用这个 scene 创建一块 window(App 的画布,所有界面都画在它上面)
        let window = UIWindow(windowScene: windowScene)

        // 组合根
        let postRepo = CoreDataPostRepository()
        let cooldowns = CoreDataCooldownStore()
        let careMessages = CoreDataCareMessageStore()
        let aiService = DeepSeekAIService()
        let chatRepo = CoreDataChatRepository()
        
        let careEngine = CareEngine(rules: [MoodRecoverRule(), LowMoodStreakRule(), HappyStreakRule()],
                                    posts: postRepo,
                                    cooldowns: cooldowns,
                                    messages: careMessages,
                                    openingProvider: aiService)
        
        let composeVM = ComposeViewModel(repository: postRepo, aiService: aiService, careEngine: careEngine)
        let homeVC = HomeViewController()
        homeVC.makeComposeViewController = {  backdrop ,onClose in
            let vc =  ComposeViewController(viewModel: composeVM, careViewModel: CareViewModel(messages: careMessages, cooldowns: cooldowns))
            vc.onClose = onClose
            vc.backdropImage = backdrop
            return vc
        }
        homeVC.makeChatViewController = {
            let vm = ChatViewModel(origin: .direct, chatRepo: chatRepo, posts: postRepo, aiService: aiService)
            return ChatViewController(viewModel: vm)
        }
        
        let rootVC = RootPagerViewController(pages: [homeVC,SquareViewController()])
        let navigationController = UINavigationController(rootViewController: rootVC)
        window.rootViewController = navigationController

        // 3. 让 window 显示出来,并持有它(存到属性里,不然会被释放)
        window.makeKeyAndVisible()
        self.window = window
        
        Task { await careEngine.handle(.appOpened)}
        
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene has moved from an inactive state to an active state.
        // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
        //MARK: test
//        Task {
//            let vm = SquareViewModel()
//            vm.loadPosts()
//            let entries = vm.entries
//            let summary = try await DeepSeekAIService().summarizeDay(entries)
//            print("蛋", summary.emotion.rawValue, summary.text)
//        }
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

