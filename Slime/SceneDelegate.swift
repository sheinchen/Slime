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

        // 2. 指定第一个界面:输入页,外面套一层导航控制器(以后能 push 到广场)
        let composeVC = ComposeViewController()
        let navigationController = UINavigationController(rootViewController: composeVC)
        window.rootViewController = navigationController

        // 3. 让 window 显示出来,并持有它(存到属性里,不然会被释放)
        window.makeKeyAndVisible()
        self.window = window
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
//        let post = try? CoreDataStack.shared.viewContext.fetch(Post.fetchRequest())
//        print("there are\(post?.count)")
//        post?.forEach {
//            print("\($0.content)")
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

