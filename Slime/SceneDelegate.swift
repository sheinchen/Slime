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
        let realAI = DeepSeekAIService()

        // —— AI 打桩开关。只在 Debug 生效，Release 分支里根本没有 stub 这个符号 ——
        //
        // 每个位置**各自**选实现，靠的是 AI 能力一开始就拆成了窄协议
        // （CareDeciding / DayEggSummarizing / AIService / RecallIntentExtracting /
        // RecallReranking），每个消费者只认自己那一个。
        // 于是「测关怀」和「测检索」可以互不干扰：
        //   -StubCare  关怀决策固定（配 -StubQuiet 翻成固定不说）
        //   -StubEgg   孵蛋总结固定，省掉等待和 API 调用
        //   -StubChat  聊天回复固定
        //   -StubAI    全部打桩，**包括检索那两路** —— 只用来验管道，验不了检索质量
        #if DEBUG
        let stubAI = StubAIService()
        let args = CommandLine.arguments
        let stubAll = args.contains("-StubAI")
        let careAI:   any CareDeciding           = (stubAll || args.contains("-StubCare")) ? stubAI : realAI
        let eggAI:    any DayEggSummarizing      = (stubAll || args.contains("-StubEgg"))  ? stubAI : realAI
        let chatAI:   any AIService              = (stubAll || args.contains("-StubChat")) ? stubAI : realAI
        let intentAI: any RecallIntentExtracting = stubAll ? stubAI : realAI
        let rerankAI: any RecallReranking        = stubAll ? stubAI : realAI
        #else
        let careAI:   any CareDeciding           = realAI
        let eggAI:    any DayEggSummarizing      = realAI
        let chatAI:   any AIService              = realAI
        let intentAI: any RecallIntentExtracting = realAI
        let rerankAI: any RecallReranking        = realAI
        #endif
        let eggService = DayEggService(posts: postRepo, eggs: eggStore, summarizer: eggAI)
        
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
                          ai: intentAI,
                          reranker: rerankAI)
        }
        
        let careChecks = CoreDataCareCheckStore()
        let careGate = CareGate(eggs: eggStore,
                                messages: careMessages,
                                checks: careChecks)
        let careEngine = CareEngine(gate: careGate,
                                    messages: careMessages,
                                    checks: careChecks,
                                    ai: careAI)


        let composeVM = ComposeViewModel(repository: postRepo, aiService: chatAI)
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
                                   aiService: chatAI,
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
        // 参数在 Edit Scheme → Run → Arguments → Arguments Passed On Launch 里配。
        //
        // ⚠️ **不带参数 = 什么都不播**，直接用上次留下的库。
        //    这一档是必需的：关怀「下次进首页还在吗」、聊天记录还在吗、蛋有没有落库，
        //    都得能重启 App 而**不清库**才验得了。
        //    （以前默认档是 reset，一重启数据就全没了，那两项根本没法手点验证。）
        //
        // —— 造数据，**会清库**（连关怀和检查日志一起清，所以启动时会重新评估一次）——
        //  -SeedLife     半年生活：近 14 天连着低落 + 往前半年埋了检索用例。**主力语料**
        //  -SeedFlat     14 天全平稳 → 闸门会放行，但 AI 该否决（验一票否决权）
        //  -SeedThin     只有 2 天   → 闸门②天数不足，**根本不调 AI**
        //  -SeedDiaries  20 天具体日记，给删除 / 卡片堆 / 周条 / 月历用
        //  -SeedLegacy   老的 5 天 sad，留着对照
        //
        // —— 在上次留下的库上动一点，**不清库、不清关怀**（接着上一幕演）——
        //  -CareTurn   把昨天重孵成 happy    → 有新证据且是转折，看 AI 换不换新话
        //  -CareFlat   补一颗平淡的蛋        → 能过闸门但没实质变化，看 AI 保不保持
        //  -CareLate   补一颗 5 天前的蛋     → 日期早于关怀那天，isNew 该是 false
        //  -CareAge    把挂着的关怀推老 4 天 → 验「满 3 天必退」这条本地兜底
        //
        // args 是上面 AI 打桩那段声明的，这里复用。
        if args.contains("-SeedLife") {
            DebugSeeder.seedLife()
        } else if args.contains("-SeedFlat") {
            DebugSeeder.seedFlat()
        } else if args.contains("-SeedThin") {
            DebugSeeder.seedThin()
        } else if args.contains("-SeedDiaries") {
            DebugSeeder.seedDiaries()
        } else if args.contains("-SeedLegacy") {
            DebugSeeder.reset(to: [.sad, .sad, .tired, .sad, .sad], withEggs: true)
        } else if args.contains("-CareTurn") || args.contains("-CareStep2") {
            DebugSeeder.hatchNow(daysAgo: 1, emotion: .happy,
                                 text: "过了！晚上和朋友吃了顿好的")
        } else if args.contains("-CareFlat") || args.contains("-CareStep3") {
            DebugSeeder.hatchNow(daysAgo: 2, emotion: .calm,
                                 text: "普通的一天，把手边的事做完了")
        } else if args.contains("-CareLate") {
            // 日期早于关怀那天、但孵出时刻是现在 —— `PastCare.isNewEvidence` 该判 false。
            // 「跨天看日期」那条判据就是为这种迟补的旧蛋写的：
            // 孵出时刻很新，内容却很旧，按时刻比会被误标成新证据。
            DebugSeeder.hatchNow(daysAgo: 5, emotion: .sad,
                                 text: "那天其实也不太好过，只是当时没写")
        } else if args.contains("-CareAge") {
            DebugSeeder.ageActiveCare()
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
