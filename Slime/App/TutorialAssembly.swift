//
//  TutorialAssembly.swift
//  Slime
//

import UIKit

/// 示范教程的组合根：用**真页面 + 内存里的假数据**搭一整套 App，再把页面上的动作接到导演身上。
///
/// 跟 `SceneDelegate` 是同一件事的两份：那边接的是 Core Data 仓库和真 AI，
/// 这边接的是 `TutorialSandbox` 里的假仓库和照剧本念台词的 AI。页面本身一模一样 ——
/// 它们只认协议，分不出底下是哪一套。
///
/// 这里建出来的所有东西（仓库、服务、VM、页面、导演）都挂在返回的那个页面上，
/// 示范结束、组合根把它从窗口上换下来，这一整套就跟着释放了。
@MainActor
enum TutorialAssembly {

    static func make(onFinish: @escaping () -> Void) -> UIViewController {
        let coordinator = TutorialCoordinator()
        coordinator.onFinish = onFinish

        // MARK: 假底层

        let seed = TutorialScript.seed(now: Date(), calendar: .current)
        let posts = InMemoryPostRepository(items: seed.posts)
        let eggs = InMemoryDayEggStore(eggs: seed.eggs)
        let ai = TutorialAI()
        // 示范自己的一个，跟正式 App 那个互不相识（各管各的防重入，也不会有人去孵正式库）
        let eggService = DayEggService(posts: posts, eggs: eggs, summarizer: ai)

        // 点「收好」那一刻日记就存了（先存后分析），所以「存了一篇」就是「点了收好」
        posts.onCreate = { [weak coordinator] in coordinator?.handle(.diarySaved) }

        // MARK: 页面

        // 同 SceneDelegate：写完日记要让各页重读，得等 root 建好才有；闭包到时候再读它
        weak var root: RootTabBarController?

        let composeVM = ComposeViewModel(repository: posts, aiService: ai)
        let makeCompose: (UIImage?, @escaping () -> Void) -> UIViewController = { [weak coordinator] backdrop, onClose in
            let vc = ComposeViewController(viewModel: composeVM)
            vc.backdropImage = backdrop
            vc.presetText = TutorialScript.diary
            vc.onPresetTyped = { coordinator?.handle(.presetTyped) }
            vc.onClose = {
                onClose()
                root?.broadcastDataChange()
                coordinator?.handle(.composeClosed)
            }
            // 工厂被调用 = 用户点了鸟巢
            coordinator?.handle(.composeOpened)
            return vc
        }

        let homeVC = HomeViewController(
            viewModel: HomeViewModel(messages: EmptyCareMessageStore(), eggs: eggs),
            makeCompose: makeCompose,
            // 设置在示范里点不到：蒙层只放行这一步要碰的那个东西。
            // 页面要求必须给工厂，给个空页面占位 —— 万一真漏过去了，也只是一张下拉就能关掉的空白页
            makeSettings: { UIViewController() })

        let squareVC = SquareViewController(
            viewModel: SquareViewModel(repository: posts, eggStore: eggs, eggService: eggService))
        squareVC.onUserAction = { [weak coordinator] action in
            coordinator?.handle(TutorialEvent(action))
        }
        // 教什么就只放行什么：每换一步，照剧本拨日历页的两个手势开关
        coordinator.onStepChange = { [weak squareVC] step in
            squareVC?.allowsMonthToggle = TutorialFlow.allowsMonthToggle(at: step)
            squareVC?.allowsCardEditing = TutorialFlow.allowsCardEditing(at: step)
        }

        let tabs = RootTabBarController(pages: [homeVC, squareVC],
                                        icons: RootTabBarController.pageIcons,
                                        accessoryIcon: RootTabBarController.accessoryIcon)
        tabs.onPageChange = { [weak coordinator] index in
            coordinator?.handle(.pageChanged(index))
        }
        root = tabs

        return TutorialHostViewController(content: tabs, coordinator: coordinator)
    }
}

private extension TutorialEvent {
    /// 日历页报的动作 → 剧本认的事件，一一对应
    init(_ action: SquareViewController.UserAction) {
        switch action {
        case .laidEgg:                         self = .laidEgg
        case .hatchedToday(let success):       self = success ? .eggHatched : .hatchFailed
        case .flippedCard:                     self = .flippedCard
        case .swipedWeek:                      self = .swipedWeek
        case .swipedMonth:                     self = .swipedMonth
        case .pickedDay(let isToday, let count, let fromMonth):
            self = .pickedDay(isToday: isToday, entryCount: count, fromMonth: fromMonth)
        case .monthExpanded(let expanded):     self = .monthExpanded(expanded)
        case .editingChanged(let editing):     self = .editingChanged(editing)
        case .deletedEntry:                    self = .deletedEntry
        case .rehatched:                       self = .rehatched
        }
    }
}
