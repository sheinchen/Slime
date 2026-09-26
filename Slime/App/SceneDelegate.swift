//
//  SceneDelegate.swift
//  Slime
//
//  Created by shiying on 2026/7/4.
//

import UIKit

/// 组合根 + App 生命周期的入口。
///
/// 09-25 拆过一次，现在只剩两件事：
/// ① **组装**：全 App 只有这里 new 具体类型、把依赖接起来（规则见 CLAUDE.md §5「依赖只从组合根来」）
/// ② **转发生命周期**：回到前台交给 `AppOpenFlow`，跨零点让各页重读
///
/// 搬走的：「补蛋 → 关怀」流程（→ `AppOpenFlow`，可以测了）、
/// 启动参数的解析和说明（→ `LaunchOptions`）、按参数播种（→ `DebugSeeder.run`）。
class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    /// 回到 App 时要跑的那条流程。它自己持有补蛋服务、关怀引擎这些，SceneDelegate 不用再一个个存着
    private var openFlow: AppOpenFlow?
    private weak var rootVC: RootTabBarController?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // scene 是一个 UIWindowScene(带屏幕的场景),转型失败就不往下走
        guard let windowScene = (scene as? UIWindowScene) else { return }

        // 用这个 scene 创建一块 window(App 的画布,所有界面都画在它上面)
        let window = UIWindow(windowScene: windowScene)

        // MARK: 仓库

        let postRepo = CoreDataPostRepository()
        let eggStore = CoreDataDayEggStore()
        let careMessages = CoreDataCareMessageStore()
        let careChecks = CoreDataCareCheckStore()
        let chatRepo = CoreDataChatRepository()

        // MARK: AI

        // 五个能力各一个实现，共用同一个 AIClient（唯一发请求的地方，接后端中转只改它）
        let aiClient = AIClient()
        let realCare   = CareDecider(client: aiClient)
        let realEgg    = DayEggSummarizer(client: aiClient)
        let realChat   = HenChatService(client: aiClient)
        let realIntent = RecallIntentExtractor(client: aiClient)
        let realRerank = MemoryReranker(client: aiClient)

        // 打桩：每一路各自能换成桩，靠的是 AI 能力拆成了窄协议、每个消费者只认自己那一个。
        // 哪个开关换哪一路、桩怎么演，都写在 LaunchOptions 里。Release 里根本没有桩这个符号。
        #if DEBUG
        let options = LaunchOptions.current
        let stubAI = StubAIService(stubs: options.stubs)
        let careAI:   any CareDeciding           = options.stubs.care   ? stubAI : realCare
        let eggAI:    any DayEggSummarizing      = options.stubs.egg    ? stubAI : realEgg
        let chatAI:   any AIService              = options.stubs.chat   ? stubAI : realChat
        let intentAI: any RecallIntentExtracting = options.stubs.recall ? stubAI : realIntent
        let rerankAI: any RecallReranking        = options.stubs.recall ? stubAI : realRerank
        #else
        let careAI:   any CareDeciding           = realCare
        let eggAI:    any DayEggSummarizing      = realEgg
        let chatAI:   any AIService              = realChat
        let intentAI: any RecallIntentExtracting = realIntent
        let rerankAI: any RecallReranking        = realRerank
        #endif

        // MARK: 服务

        let eggService = DayEggService(posts: postRepo, eggs: eggStore, summarizer: eggAI)

        // 模型只加载一次,两个 Service 共用。45MB 的 Core ML 模型建两遍既慢又白占内存。
        // 加载失败就是 nil,聊天照常跑,只是母鸡不会提起旧事。
        let embedder = try? TextEmbedder()
        let recallIndex = embedder.map { RecallIndexService(posts: postRepo, embedder: $0) }
        let recallService = embedder.map {
            RecallService(posts: postRepo, embedder: $0, ai: intentAI, reranker: rerankAI)
        }

        let careEngine = CareEngine(gate: CareGate(eggs: eggStore, messages: careMessages, checks: careChecks),
                                    messages: careMessages,
                                    checks: careChecks,
                                    ai: careAI)

        // MARK: 页面

        // 「让所有页面重读一遍」要用到 rootVC，可 rootVC 得等页面都建好才能建（页面就是它的参数）。
        // 所以闭包里不直接抓 rootVC，而是弱引用 self、到时候再读 self.rootVC ——
        // 闭包在这里只是被定义，要等写完日记关页面、回到前台时才会被调用，那时 rootVC 早就填好了。
        let refreshAllPages: @MainActor () -> Void = { [weak self] in
            self?.rootVC?.broadcastDataChange()
        }

        // 聊天有两个入口：首页点母鸡、tab 条右边那个圆。共用一份构造
        let makeChat: () -> UIViewController = {
            ChatViewController(viewModel: ChatViewModel(origin: .direct,
                                                        chatRepo: chatRepo,
                                                        aiService: chatAI,
                                                        recall: recallService))
        }

        let composeVM = ComposeViewModel(repository: postRepo, aiService: chatAI)
        let makeCompose: (UIImage?, @escaping () -> Void) -> UIViewController = { backdrop, onClose in
            let vc = ComposeViewController(viewModel: composeVM)
            vc.backdropImage = backdrop
            vc.onClose = {
                onClose()
                refreshAllPages()
            }
            return vc
        }

        let homeVC = HomeViewController(viewModel: HomeViewModel(messages: careMessages, eggs: eggStore),
                                        makeCompose: makeCompose,
                                        makeChat: makeChat)
        let squareVM = SquareViewModel(repository: postRepo, eggStore: eggStore, eggService: eggService)

        // 图标先用 SF Symbols 占位 —— 换成自己的 icon 时只改这三个名字。
        // 右边那个圆不是 tab，是动作入口，去哪由这里决定。
        let rootVC = RootTabBarController(
            pages: [homeVC, SquareViewController(viewModel: squareVM)],
            icons: ["house.fill", "calendar"],
            accessoryIcon: "bubble.left.fill"
        )
        rootVC.onAccessoryTap = { [weak rootVC] in
            rootVC?.present(makeChat(), animated: true)
        }
        self.rootVC = rootVC

        // MARK: 回到 App 的流程

        // 补向量：向量模型没加载起来（recallIndex 是 nil）就没有这一步。
        // 写成 if let 而不是 recallIndex.map { … }：闭包从 map 里返回出来，编译器推不出它是主线程隔离的
        var backfill: (@MainActor () async -> Void)?
        if let recallIndex {
            backfill = { _ = await recallIndex.backfill() }
        }
        openFlow = AppOpenFlow(
            hatchPending: { await eggService.hatchAllPending() },
            evaluateCare: { await careEngine.handle(.appOpened) },
            backfillIndex: backfill,
            refreshPages: refreshAllPages)

        window.rootViewController = UINavigationController(rootViewController: rootVC)

        #if DEBUG
        // 按启动参数播种（每一幕是干什么的见 LaunchOptions.Seed）。只在测试库上生效，正式库会被挡掉
        if let seed = options.seed {
            DebugSeeder.run(seed)
        }
        #endif

        // 让 window 显示出来,并持有它(存到属性里,不然会被释放)
        window.makeKeyAndVisible()
        self.window = window

        // 系统在零点（以及运营商校时、夏令时切换这类时间突变）时发这个通知，
        // 在主线程上发。用 selector 版本：闭包版本的回调不带主线程隔离，
        // 在里面碰 rootVC 编译器会拦。SceneDelegate 跟 App 同寿，不用手动移除观察者。
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(significantTimeChange),
                                               name: UIApplication.significantTimeChangeNotification,
                                               object: nil)
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // 故意什么都不放。「回到 App」的入口在 sceneWillEnterForeground，原因见那边。
    }

    /// 「用户回到 App」的唯一入口。要做什么、按什么顺序、怎么防重入，全在 `AppOpenFlow` 里。
    ///
    /// 为什么是这里、不是 sceneDidBecomeActive（09-24 模拟器实测）：
    ///
    ///   | 操作               | willEnterForeground | didBecomeActive |
    ///   | 冷启动             | ✅                  | ✅              |
    ///   | 下拉通知中心再收起 |                     | ✅              |
    ///   | 回主屏再点回来     | ✅                  | ✅              |
    ///
    /// 两个维度：前台/后台 = 用户在不在这个 App 里；活跃/非活跃 = 此刻摸不摸得到。
    /// 拉通知中心时用户没离开，只是暂时摸不到 —— 那不是「回来了」。
    /// 放在 didBecomeActive 的话，每拉一次通知中心就跑一遍闸门、往 CareCheck 写一条
    /// 「没有新蛋」，debug 页的统计被这种噪声撑大。冷启动这里也会走，不用另外补。
    func sceneWillEnterForeground(_ scene: UIScene) {
        openFlow?.enterForeground()
    }

    /// 开着 App 跨过零点。
    ///
    /// 回前台那一下管的是「隔夜回来」；这个管的是「App 一直开在眼前、日子换了」。
    /// 只让各页对一下「今天」，**不跑补蛋和关怀** —— 规格里那条流程只认「回到 App」一个事件，
    /// 零点那一刻用户没做任何事，昨天的蛋留到下次回前台再补。
    @objc private func significantTimeChange() {
        rootVC?.broadcastDataChange()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        // This may occur due to temporary interruptions (ex. an incoming phone call).
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        // Use this method to save data, release shared resources, and store enough scene-specific state information
        // to restore the scene back to its current state.

        // Save changes in the application's managed object context when the application transitions to the background.
        CoreDataStack.shared.saveContext()
    }
}
