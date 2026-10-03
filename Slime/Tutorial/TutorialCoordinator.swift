//
//  TutorialCoordinator.swift
//  Slime
//

import UIKit

/// 示范的导演：收页面上报的事件 → 照剧本（`TutorialFlow`）换步 → 让蒙层演这一步。
///
/// 它自己**不做任何判断**，判断全在 `TutorialFlow` 里（有单测）。这里只管三件有副作用的事：
/// · 换步之后等几秒再露出下一步的画面（给动画留时间）
/// · 每一帧去窗口里找「要露出来的那个东西」在哪，把洞挪过去 —— 岛在浮、月历在展开，位置一直在变
/// · 演完（或被跳过）收掉蒙层，告诉外面「可以进 App 了」
@MainActor
final class TutorialCoordinator {

    /// 走完或跳过。外面（组合根）据此记下「看过了」、换上真的主界面
    var onFinish: (() -> Void)?
    /// 换到了哪一步（开演时也报一次）。外面据此拨页面上的手势开关 —— 教什么就只放行什么，
    /// 见 `TutorialFlow.allowsMonthToggle` / `allowsCardEditing`
    var onStepChange: ((TutorialStep) -> Void)?

    private(set) var step: TutorialStep = .intro

    private var overlayWindow: TutorialOverlayWindow?
    /// 真页面所在的窗口。找锚点就在它里面找 —— present 出来的写日记页也在它里面
    private weak var hostWindow: UIWindow?
    private var displayLink: CADisplayLink?

    /// 现在台上的画面。换步后有一段「等」，那段时间这里是 `.waiting`，不是新那步的画面
    private var scene: TutorialScene = .waiting
    /// 排着队、等几秒再露出的下一步画面。又换了一步就作废
    private var pendingScene: DispatchWorkItem?

    /// 找到过的锚点。每帧都要算洞在哪，不能每帧都把整棵 view 树翻一遍
    private var anchorCache: [TutorialAnchor: WeakView] = [:]

    // MARK: - 开演 / 收场

    /// 页面挂上窗口之后才能开演：蒙层要跟它在同一个 scene 里开一个新窗口
    func start(in hostWindow: UIWindow) {
        guard overlayWindow == nil, step != .finished,
              let windowScene = hostWindow.windowScene else { return }
        self.hostWindow = hostWindow

        let window = TutorialOverlayWindow(windowScene: windowScene)
        window.overlay.onContinue = { [weak self] in self?.handle(.continueTapped) }
        window.overlay.onSkip = { [weak self] in self?.handle(.skipTapped) }
        // 只是显示出来，**不 makeKey**：键盘、按钮的焦点都还归下面的真页面
        window.isHidden = false
        overlayWindow = window

        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link

        onStepChange?(step)
        present(currentScene)
    }

    private var currentScene: TutorialScene {
        TutorialFlow.scene(for: step)
    }

    /// 停下来：收掉帧循环和蒙层窗口。收场会调；页面被整个换掉时（`TutorialHostViewController`）也会调，
    /// 不然 CADisplayLink 强持有着 self，协调者永远不会释放
    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        pendingScene?.cancel()
        pendingScene = nil
        guard let window = overlayWindow else { return }
        overlayWindow = nil
        UIView.animate(withDuration: 0.25) {
            window.alpha = 0
        } completion: { _ in
            window.isHidden = true
        }
    }

    // MARK: - 事件

    func handle(_ event: TutorialEvent) {
        guard let transition = TutorialFlow.next(from: step, on: event) else { return }
        let (next, delay) = transition
        // 状态立刻换过去，只有画面等一会儿 —— 等的这段时间里再来事件，按新的一步算。
        // 手势开关也立刻拨：等的那段蒙层挡着所有点击，早拨晚拨都碰不到手
        step = next
        onStepChange?(next)
        pendingScene?.cancel()
        pendingScene = nil

        if next == .finished {
            stop()
            onFinish?()
            return
        }

        guard delay > 0 else { return present(currentScene) }
        // 等的这段：不说话、挡住所有点击，别让人在两步之间乱点
        present(.waiting)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingScene = nil
            self.present(self.currentScene)
        }
        pendingScene = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func present(_ scene: TutorialScene) {
        self.scene = scene
        overlayWindow?.overlay.show(scene)
        updateHole()
    }

    // MARK: - 洞跟着东西走

    @objc private func tick() {
        updateHole()
    }

    private func updateHole() {
        guard let overlay = overlayWindow?.overlay else { return }
        var hole: CGRect?
        var touchable: CGRect?
        for anchor in scene.spotlight {
            guard let view = visibleView(for: anchor) else { continue }
            // 转成窗口坐标。蒙层窗口和主窗口一样大、都铺满屏幕，所以两边的坐标是同一套
            let frame = view.convert(view.bounds, to: nil)
            let drawn = frame.inset(by: anchor.holePadding)
            hole = hole?.union(drawn) ?? drawn
            touchable = touchable?.union(frame) ?? frame
        }
        overlay.setHole(hole, touchable: touchable)
    }

    /// 这个锚点现在在屏幕上的那个 view。不在窗口上（切到别的 tab 了）、藏着、透明的都算没有
    private func visibleView(for anchor: TutorialAnchor) -> UIView? {
        let view: UIView?
        if let cached = anchorCache[anchor]?.view, cached.window != nil {
            view = cached
        } else {
            view = hostWindow?.descendant(identifiedBy: anchor.rawValue)
            anchorCache[anchor] = view.map(WeakView.init)
        }
        guard let view, !view.isHidden, view.alpha > 0.01 else { return nil }
        return view
    }
}

// MARK: - 小工具

/// 字典里存 view 的弱引用：页面换掉了，缓存不该把旧 view 留着
private struct WeakView {
    weak var view: UIView?
    init(_ view: UIView) { self.view = view }
}

private extension TutorialAnchor {
    /// 画出来的洞比东西本身大多少（负数 = 往外扩）。只管好看，**点击范围不跟着扩**，见 `TutorialOverlayView.touchable`
    var holePadding: UIEdgeInsets {
        switch self {
        case .nest:
            // 整座岛一直在上下浮（最高浮起 13pt），洞按岛不动时的位置算，
            // 上沿多留一截，浮起来的时候鸟巢也不会顶出洞外
            return UIEdgeInsets(top: -18, left: -8, bottom: -8, right: -8)
        case .calendarTab:
            return UIEdgeInsets(top: -4, left: -4, bottom: -4, right: -4)
        default:
            return UIEdgeInsets(top: -8, left: -8, bottom: -8, right: -8)
        }
    }
}

private extension UIView {
    /// 按 accessibilityIdentifier 找子孙 view。一层一层往下找（广度优先），找到第一个就停
    func descendant(identifiedBy identifier: String) -> UIView? {
        var queue: [UIView] = [self]
        while !queue.isEmpty {
            let view = queue.removeFirst()
            if view.accessibilityIdentifier == identifier { return view }
            queue.append(contentsOf: view.subviews)
        }
        return nil
    }
}
