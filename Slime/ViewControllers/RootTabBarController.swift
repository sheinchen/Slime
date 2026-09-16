//
//  RootTabBarController.swift
//  Slime
//
//  根容器。取代了原来左右滑的 RootPagerViewController ——
//  切页、子 VC 生命周期这些全交给系统的 UITabBarController，
//  系统那条 tabBar 藏掉，底下浮一条自己画的 FloatingTabBar。
//

import UIKit
import SnapKit

/// 根容器的一页，负责知道自己是不是当前页
protocol RootPage: UIViewController {
    func pageVisibilityDidChange(isCurrent: Bool)
    func dataDidChange()
}

extension RootPage {
    func dataDidChange() {
    }
}

final class RootTabBarController: UITabBarController {

    /// 右边那个圆点了做什么。它**不是 tab**，是个动作入口，去哪由组合根决定
    var onAccessoryTap: (() -> Void)?

    private let floatingBar: FloatingTabBar

    init(pages: [UIViewController], icons: [String], accessoryIcon: String) {
        floatingBar = FloatingTabBar(icons: icons, accessoryIcon: accessoryIcon)
        super.init(nibName: nil, bundle: nil)
        viewControllers = pages
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // 系统那条 tabBar 不要，但 UITabBarController 的切页和子 VC 生命周期照用 ——
        // 自己写容器就得自己管 addChild / 生命周期回调，没必要。
        tabBar.isHidden = true

        view.addSubview(floatingBar)
        floatingBar.snp.makeConstraints { make in
            // 横跨整个宽度：胶囊靠左端、圆靠右端，中间空开。
            // 22 是和广场页的周条、卡片同一个左右缩进，三者竖着看是对齐的
            make.leading.trailing.equalToSuperview().inset(22)
            make.bottom.equalTo(view.safeAreaLayoutGuide).offset(-FloatingTabBar.bottomInset)
        }

        floatingBar.onSelect = { [weak self] index in
            guard let self else { return }
            self.selectedIndex = index
            self.notifyPageVisibility()
        }
        floatingBar.onAccessoryTap = { [weak self] in
            self?.onAccessoryTap?()
        }

        floatingBar.select(0)
        notifyPageVisibility()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    /// 让每一页的内容自动避开浮动条。
    ///
    /// additionalSafeAreaInsets 是「在系统算出的安全区上再加一圈」——
    /// 页面里贴 safeAreaLayoutGuide 的约束会自己让开，布局代码一行都不用改。
    ///
    /// 但**不能只在 viewDidLoad 里设一次**：UITabBarController 自己也用这个属性
    /// 给系统 tabBar 让位，每次布局都会把子 VC 的值重写一遍，早设的会被抹掉。
    /// 所以放在这里、每次布局后补写；加个相等判断，免得改 inset 又触发布局来回震荡。
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let inset = FloatingTabBar.height + FloatingTabBar.bottomInset
        for page in viewControllers ?? []
        where abs(page.additionalSafeAreaInsets.bottom - inset) > 0.5 {
            page.additionalSafeAreaInsets.bottom = inset
        }
    }

    // MARK: - 广播

    /// **只广播给已经加载过 view 的页**。
    ///
    /// 这是从 RootPagerViewController 换过来时最容易踩的一个坑：
    /// 老的 pager 把每一页的 view 都塞进 stack，等于强制所有子 VC 立刻 viewDidLoad；
    /// UITabBarController 是**懒加载**的，没切过去的页 view 根本没建，
    /// 这时候调它的 dataDidChange，里面碰 dataSource 之类的隐式解包属性就是直接崩。
    ///
    /// 跳过也不会漏数据 —— 没加载的页第一次出现时 viewWillAppear 会自己读一遍最新的。
    private func forEachLoadedPage(_ body: (RootPage, Int) -> Void) {
        for (index, page) in (viewControllers ?? []).enumerated() {
            guard page.isViewLoaded, let page = page as? RootPage else { continue }
            body(page, index)
        }
    }

    private func notifyPageVisibility() {
        forEachLoadedPage { page, index in
            page.pageVisibilityDidChange(isCurrent: index == selectedIndex)
        }
    }

    /// 数据在别处变了（补蛋、关怀落库），通知每一页重读。
    /// SceneDelegate 的 onAppActive 里用。
    func broadcastDataChange() {
        forEachLoadedPage { page, _ in
            page.dataDidChange()
        }
    }
}
