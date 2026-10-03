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

    /// 用户同不同意把内容交给 AI。没同意 = 用不了 App，根页面是同意页
    private var consent: AIConsentStore?
    /// 主界面（tab 那一套）。同意之后才挂到窗口上；撤回时换下来，但对象留着 ——
    /// 重新同意时直接换回来，不用把所有页面重建一遍
    private var mainUI: UIViewController?
    /// 示范看过没有。没看过：同意之后先进示范，走完（或跳过）才换上主界面
    private var tutorial: TutorialStore?
    /// 向量模型。存着是为了窗口亮出来之后再在后台预热（见 `warmUpEmbedder`）
    private var embedder: TextEmbedder?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // scene 是一个 UIWindowScene(带屏幕的场景),转型失败就不往下走
        guard let windowScene = (scene as? UIWindowScene) else { return }

        // 用这个 scene 创建一块 window(App 的画布,所有界面都画在它上面)
        let window = UIWindow(windowScene: windowScene)
        // 持有 window（存到属性里，不然会被释放）。要在挂根页面之前：setRoot 读的是 self.window
        self.window = window

        // 第一件事：库打开了没有。没打开（迁移失败、手机空间满了…）就只挂一页「日记本打不开了」，
        // 仓库、页面、补蛋一样都不建 —— 建了也是对着一个空库读写。
        // 以前这里根本走不到：CoreDataStack 里是 fatalError，每次打开都崩（10-02 改）
        if CoreDataStack.shared.isLoaded {
            assemble()
            showFirstPage(animated: false)
        } else {
            showStoreError()
        }
        window.makeKeyAndVisible()
        warmUpEmbedder()

        // 系统在零点（以及运营商校时、夏令时切换这类时间突变）时发这个通知，
        // 在主线程上发。用 selector 版本：闭包版本的回调不带主线程隔离，
        // 在里面碰 rootVC 编译器会拦。SceneDelegate 跟 App 同寿，不用手动移除观察者。
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(significantTimeChange),
                                               name: UIApplication.significantTimeChangeNotification,
                                               object: nil)
    }

    /// 组装：全 App 只有这里 new 具体类型、把依赖接起来。**库打开之后才调**，只调一次
    private func assemble() {
        // MARK: 仓库

        let postRepo = CoreDataPostRepository()
        let eggStore = CoreDataDayEggStore()
        let careMessages = CoreDataCareMessageStore()
        let careChecks = CoreDataCareCheckStore()
        let consent = UserDefaultsAIConsentStore()
        self.consent = consent
        let tutorial = UserDefaultsTutorialStore()
        self.tutorial = tutorial

        // MARK: AI

        // 五个能力各一个实现，共用同一个 AIClient（唯一发请求的地方，接后端中转只改它）
        // 闸门每次发请求都现问一遍同意状态 —— 撤回之后，已经建好的这些能力也立刻发不出去
        let aiClient = AIClient(isSendingAllowed: { consent.hasConsented })
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

        // 向量模型两个 Service 共用一个。这里只建个空壳、不加载：加载等首页出来后在后台做（见下面 warmUp）。
        // 加载失败的话向量那一路拿不到东西，检索退回关键词 + 情绪两路，聊天照常
        let embedder = TextEmbedder()
        self.embedder = embedder
        let recallIndex = RecallIndexService(posts: postRepo, embedder: embedder)
        let recallService = RecallService(posts: postRepo, embedder: embedder, ai: intentAI, reranker: rerankAI)

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

        // 聊天的入口：tab 条右边那个圆（首页点母鸡 10-02 起不再进聊天）
        let makeChat: () -> UIViewController = {
            // 每次都是新的一段对话，只在内存里：关掉聊天页就没了（不存库，见 ChatViewModel.messages）
            ChatViewController(viewModel: ChatViewModel(aiService: chatAI, recall: recallService))
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
                                        makeSettings: { [weak self] in
                                            SettingsViewController(onWithdraw: { self?.withdrawConsent() })
                                        })
        let squareVM = SquareViewModel(repository: postRepo, eggStore: eggStore, eggService: eggService)

        // 右边那个圆不是 tab，是动作入口，去哪由这里决定。
        let rootVC = RootTabBarController(
            pages: [homeVC, SquareViewController(viewModel: squareVM)],
            icons: RootTabBarController.pageIcons,
            accessoryIcon: RootTabBarController.accessoryIcon
        )
        rootVC.onAccessoryTap = { [weak rootVC] in
            rootVC?.present(makeChat(), animated: true)
        }
        self.rootVC = rootVC

        // MARK: 回到 App 的流程

        openFlow = AppOpenFlow(
            hatchPending: { await eggService.hatchAllPending() },
            evaluateCare: { await careEngine.handle(.appOpened) },
            backfillIndex: { _ = await recallIndex.backfill() },
            refreshPages: refreshAllPages)

        mainUI = UINavigationController(rootViewController: rootVC)

        #if DEBUG
        // 按启动参数播种（每一幕是干什么的见 LaunchOptions.Seed）。只在测试库上生效，正式库会被挡掉
        if let seed = options.seed {
            DebugSeeder.run(seed)
        }
        if options.resetTutorial {
            tutorial.reset()
        }
        #endif
    }

    /// 在后台把向量模型加载好。装完 / 更新后第一次要 2 秒 —— 窗口亮出来之后在后台做，用户看不见；
    /// 拖到第一次聊天才加载就要让人干等。utility = 不急的后台活，不跟界面抢
    private func warmUpEmbedder() {
        guard let embedder else { return }
        Task.detached(priority: .utility) {
            embedder.warmUp()
        }
    }

    // MARK: - 库打不开

    private func showStoreError() {
        let error = CoreDataStack.shared.loadError ?? CocoaError(.fileReadUnknown)
        setRoot(StoreErrorViewController(error: error, onRetry: { [weak self] in
            self?.retryOpeningStore() ?? false
        }), animated: false)
    }

    /// 「再试一次」。打开了就照冷启动的路子把 App 建起来，换掉错误页
    private func retryOpeningStore() -> Bool {
        guard CoreDataStack.shared.retryLoad() else { return false }
        assemble()
        showFirstPage(animated: true)
        warmUpEmbedder()
        // 冷启动那一轮回前台被跳过了（那时 consent 还是 nil），现在补跑：欠的蛋孵上、关怀评估一次
        if consent?.hasConsented == true {
            openFlow?.enterForeground()
        }
        return true
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
        // 没同意之前整条流程都不跑 —— 补蛋、关怀都要把日记发给 AI。
        // AIClient 那道闸也挡得住，但被挡下的补蛋会记一次失败、30 秒内不重试：
        // 用户读完同意页点「同意」时，那几天正卡在冷却里，要等下次回前台才孵得出来。
        guard consent?.hasConsented == true else { return }
        openFlow?.enterForeground()
    }

    // MARK: - 同意页 ⇄ 主界面

    /// 换整个根页面。同意页不是盖在主界面上的弹窗 —— 没同意时主界面根本不在窗口上，没有路能绕过去
    ///
    /// 淡入淡出是「新页面先放好，旧页面的截图盖在上面淡掉」，不用 `UIView.transition(with: window…)`。
    /// 那种写法是系统对整个窗口做交叉淡化，Metal 画的内容（首页的 Rive 母鸡）在里面怎么显示不归我们管；
    /// 这样写首页从第一帧起就是真画面，母鸡画出来就透过淡掉的截图显出来。
    /// 09-28 真机不挂调试器：同意后母鸡跟着岛一起出来，不闪。
    /// ⚠️ 从 Xcode 挂着调试器跑、又是全新安装时，第一次编译着色器会把主线程卡住近 1 秒，
    ///    淡出来不及播、母鸡晚一拍 —— 那是调试器的问题，哪种写法都一样，真实用户不会遇到（CLAUDE.md「首次打开」一节）
    private func setRoot(_ viewController: UIViewController, animated: Bool) {
        guard let window else { return }
        // 旧页面此刻的样子。afterScreenUpdates: false = 就要屏幕上现在这一帧，不等重画
        guard animated, let oldScreen = window.snapshotView(afterScreenUpdates: false) else {
            window.rootViewController = viewController
            return
        }
        window.rootViewController = viewController
        // 盖在新页面上面。淡出的这 0.35 秒里它也挡着点击 —— 同意按钮连点两次的问题照样挡得住
        window.addSubview(oldScreen)
        UIView.animate(withDuration: 0.35, animations: {
            oldScreen.alpha = 0
        }, completion: { _ in
            oldScreen.removeFromSuperview()
        })
    }

    /// 组装完之后挂哪一页。没同意就先见同意页，主界面这时候根本不在窗口上
    private func showFirstPage(animated: Bool) {
        if consent?.hasConsented == true {
            enterApp(animated: animated)
        } else {
            showConsentPage(animated: animated)
        }
    }

    private func showConsentPage(animated: Bool) {
        setRoot(AIConsentViewController(onAgree: { [weak self] in self?.didAgree() }), animated: animated)
        // 国行 iPhone 的「使用数据」弹窗趁这时候弹，别等到同意之后（见 NetworkAccessPrompt）。
        // 撤回后回到这一页会再发一次 —— 系统只问一次，之后这个请求什么都不触发，无害
        NetworkAccessPrompt.trigger()
    }

    /// 同意之后进 App：没看过示范先进示范，看过了直接上主界面。
    ///
    /// 示范走到一半 App 被杀、下次打开：同意还在、示范没记上 → 从这里重新进示范，从头走
    private func enterApp(animated: Bool) {
        guard let mainUI else { return }
        if tutorial?.hasFinished == true {
            setRoot(mainUI, animated: animated)
        } else {
            setRoot(TutorialAssembly.make(onFinish: { [weak self] in self?.finishTutorial() }),
                    animated: animated)
        }
    }

    /// 示范走完或被跳过。示范那一整套（假仓库、页面、导演）随着被换下窗口一起释放 ——
    /// 示范里写的、孵的、删的，从来没进过数据库，这里不用清理任何东西
    private func finishTutorial() {
        tutorial?.markFinished()
        if let mainUI {
            setRoot(mainUI, animated: true)
        }
    }

    private func didAgree() {
        consent?.grant()
        enterApp(animated: true)
        // 冷启动那一轮被 sceneWillEnterForeground 的守卫跳过了（那时还没同意），现在补跑：
        // 欠的蛋孵上、关怀评估一次、向量补上
        openFlow?.enterForeground()
    }

    /// 设置页已经先把自己收掉了才调到这里，所以主界面上面没有盖着东西，可以直接换
    private func withdrawConsent() {
        consent?.withdraw()
        showConsentPage(animated: true)
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

        // 保底存一次（正常没东西可存，见 saveContext）。库没打开时不碰它
        guard CoreDataStack.shared.isLoaded else { return }
        CoreDataStack.shared.saveContext()
    }
}
