//
//  TutorialHostViewController.swift
//  Slime
//

import UIKit

/// 示范期间的根页面：里面嵌着一整套示范用的页面（首页 + 日历页 + tab 条），再持有导演。
///
/// 为什么要多套这一层，而不是直接把示范的 tab 页面放到窗口上：
/// 导演（`TutorialCoordinator`）得有人持有，而且得等页面**挂上窗口**才能开演 ——
/// 蒙层要在同一个 scene 里开新窗口，还要去这个窗口里找按钮在哪。
/// 「什么时候挂上窗口了」只有 `viewDidAppear` 知道，所以由这一层来喊开始。
///
/// 嵌子页面用的是 container view controller 那一套（addChild → addSubview → didMove）：
/// 子页面的生命周期回调（viewWillAppear 等）才会被正确转发下去，tab 页面照常工作。
final class TutorialHostViewController: UIViewController {

    private let content: UIViewController
    private let coordinator: TutorialCoordinator

    init(content: UIViewController, coordinator: TutorialCoordinator) {
        self.content = content
        self.coordinator = coordinator
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(content)
        view.addSubview(content.view)
        content.view.frame = view.bounds
        content.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        content.didMove(toParent: self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // 重复调用无害：start 里挡着「已经开演了」
        if let window = view.window {
            coordinator.start(in: window)
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // 整个示范被换下了窗口（走完 / 跳过之后组合根换上真的主界面）。
        // 只认「真的离开了窗口」：写日记页盖上来时这一层还在窗口上，不能停
        if view.window == nil {
            coordinator.stop()
        }
    }
}
