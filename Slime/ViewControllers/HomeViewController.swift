//
//  MainViewController.swift
//  Slime
//
//  Created by shiying on 2026/8/15.
//

import UIKit
import SnapKit

final class HomeViewController: UIViewController {
    
    //判断当前页
    private var isOnScreen = false
    private var isCurrentPage = true
    private var isRunning = false
    
    //写日记 首页被挡住
    private var isCoverd = false
    
    
    private let sky = SkyView()
    private let dateLabel = UILabel()
    private let subLabel = UILabel()
    private let island = IslandView()
    private let islandShadow = CAGradientLayer()
    private let hintLabel = UILabel()
    
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0

    // MARK: - 关怀卡片
    private let careCard = CareCardView()
    /// 正挂在屏幕上的那条。nil = 现在没露面。
    private var showingCareId: UUID?
    /// 「真的被看到了」的定时器：滑出后活满这么久才把 firstSeenAt 落库。
    private var careFirstSeen: DispatchWorkItem?

    /// 滑出后活满几秒，才算这条话**真的被看到了**。
    ///
    /// 不能在 `slideIn()` 那一刻就记 —— 那记的是「播过动画」。
    /// 用户一开 App 就点鸟巢，卡片刚冒头就被 `dismissCare()` 收掉了，
    /// 那次要是算数，这条关怀从此就只剩安静形态，等于白说。
    /// 被打断的那次不算，下次进首页它仍然享受完整的首次待遇。
    private static let firstSeenDelay: TimeInterval = 3

    //注入组合根
    var makeComposeViewController: ((_ backdrop: UIImage?, _ onClose: @escaping () -> Void) -> UIViewController)?
    var makeChatViewController: (() -> UIViewController)?
    var careViewModel: CareViewModel?
    
    /// 今天下过蛋没有。日记流程还没接上，先留着驱动文案和提示圈。
    private var laidToday = false {
        didSet { updateCopy() }
    }
    
    // MARK: -
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        sky.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sky)
        
        setupHeader()
        setupIsland()
        setupChrome()
        setupCareCard()
        
        NSLayoutConstraint.activate([
            sky.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sky.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sky.topAnchor.constraint(equalTo: view.topAnchor),
            sky.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        
        
        
        updateCopy()
        
        island.onNestTap = { [weak self] in
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            guard let self else { return }
            self.dismissCare()          // 用户去写日记了，卡片让路
            let backdrop = self.view.blurredSnapshot(radius: 5)
            
            guard let composeVC = self.makeComposeViewController?(backdrop, { [weak self] in
                self?.setCovered(false)
                
            }) else { return }
            composeVC.modalPresentationStyle = .overFullScreen
            composeVC.modalTransitionStyle = .crossDissolve
            self.setCovered(true)
            self.present(composeVC, animated: true)

        }
      
        island.onHenTap = { [weak self] in
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            guard let self else { return }
            self.dismissCare()
            guard let chatVC = self.makeChatViewController?() else { return }
            self.present(chatVC,animated: true)
        }
        
    }
        
        private func setupHeader() {
            dateLabel.numberOfLines = 1
            subLabel.numberOfLines = 1
            // 关怀卡片的 lingering 形态就挤在这行右边，两个都想要宽度。
            // 不把这行的抗压优先级顶到 required，Auto Layout 会选择压缩它 ——
            // 「巢是空的」当场变成「···」，而卡片自己一行铺过去。
            // 卡片那边是可以换行的，所以该让的是卡片。
            subLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

            #if DEBUG
            // 关怀 debug 页的入口:长按日期。
            // **不加任何可见 UI** —— 它是开发工具,不该在产品界面上留痕迹。
            // UILabel 默认不收触摸,要显式打开。
            dateLabel.isUserInteractionEnabled = true
            dateLabel.addGestureRecognizer(
                UILongPressGestureRecognizer(target: self, action: #selector(openCareDebug)))
            #endif
            
            let stack = UIStackView(arrangedSubviews: [dateLabel, subLabel])
            stack.axis = .vertical
            stack.spacing = 14
            stack.alignment = .leading
            stack.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(stack)
            
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 34),
                stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -34),
                // 设计稿是距屏幕顶 104，安全区顶大约 59，剩下的差额补在这里
                stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 45),
            ])
        }
        
        #if DEBUG
        @objc private func openCareDebug(_ g: UILongPressGestureRecognizer) {
            guard g.state == .began else { return }   // 长按会连发多次，只认第一下
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            present(UINavigationController(rootViewController: CareDebugViewController()),
                    animated: true)
        }
        #endif

        private func setupIsland() {
            // 影子不跟着岛一起浮 —— 它贴在地上，只做缩放和明暗的呼吸
            islandShadow.type = .radial
            islandShadow.colors = [
                Sky.islandShadow.cgColor,
                Sky.islandShadow.withAlphaComponent(0).cgColor,
                Sky.islandShadow.withAlphaComponent(0).cgColor,
            ]
            islandShadow.locations = [0, 0.72, 1]
            islandShadow.startPoint = CGPoint(x: 0.5, y: 0.5)
            islandShadow.endPoint = CGPoint(x: 1, y: 1)
            islandShadow.opacity = 0.34
            view.layer.addSublayer(islandShadow)
            
            island.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(island)
            
            NSLayoutConstraint.activate([
                island.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                island.widthAnchor.constraint(equalToConstant: IslandView.size.width),
                island.heightAnchor.constraint(equalToConstant: IslandView.size.height),
                island.topAnchor.constraint(equalTo: view.topAnchor, constant: 352),
            ])
        }
        
        private func setupChrome() {
            hintLabel.textAlignment = .center
            hintLabel.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(hintLabel)
            
            NSLayoutConstraint.activate([
                hintLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                hintLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                // 贴安全区而不是 view 底：根容器给每一页加了 additionalSafeAreaInsets，
                // 贴安全区的东西会自动让开底下那条浮动 tab
                hintLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            ])
        }
        
        private func setupCareCard() {
            careCard.isHidden = true
            view.addSubview(careCard)
            setCareForm(.speaking)
        }

        /// 换形态。**位置和形态必须一起改**，所以只留这一个口子 ——
        /// 两种形态在屏幕上待的不是同一个地方。
        private func setCareForm(_ form: CareCardView.Form) {
            careCard.form = form
            careCard.snp.remakeConstraints {
                switch form {
                case .speaking:
                    // 贴着头部那行小字下面，左边和它对齐；岛在 y=352，中间这块空着正好。
                    // 右边是「最多到」不是「等于」：气泡宽度跟着字走，一句短话就是个小泡泡
                    $0.top.equalTo(subLabel.snp.bottom).offset(26)
                    $0.leading.equalToSuperview().inset(34)
                    $0.trailing.lessThanOrEqualToSuperview().inset(34)

                case .lingering:
                    // 缩到「巢是空的」那行的右边，和它齐平。
                    //
                    // 往上提 lingeringTopInset：卡片的上沿不是文字的上沿，
                    // 中间隔着气泡的内缩，不减掉的话这行字会比左边那行矮一截。
                    $0.top.equalTo(subLabel.snp.top).offset(-CareCardView.lingeringTopInset)
                    $0.trailing.equalToSuperview().inset(34)
                    // 左边只给下限，不给等号：宽度仍然跟着字走，短话就是个小块。
                    // 贴着 subLabel 的右侧，**日期那行有多长都不会撞上** ——
                    // 撞车的风险在「巢是空的 / 今天的蛋在巢里了」这两种长度之间，
                    // 所以参照物只能是它，不能是写死的数。
                    $0.leading.greaterThanOrEqualTo(subLabel.snp.trailing).offset(16)
                }
            }
        }

        /// 气泡的尾巴跟着母鸡走 —— 她在岛上溜达，话得是从她那儿冒出来的。
        private func aimCareTail(dt: CFTimeInterval) {
            // hen.center 就是她身体的中线（锚点 x = 0.5）。
            // Rive 没加载出来就对准岛心，至少指着「那一片」
            let henCenter = island.hen?.center ?? CGPoint(x: island.bounds.midX, y: 0)
            // 母鸡的坐标是岛里的，要换算成气泡自己的坐标系
            let x = island.convert(henCenter, to: careCard).x
            careCard.aimTail(atX: x, dt: dt)
        }

        // MARK: - 关怀卡片的露面
        //
        // ⚠️ 这一整块只管**露面**，不碰关怀的 status。
        //    卡片淡出后 CareMessage 仍是 shown，下次进首页还会再来。
        //    真正的退场由 CareEngine 说了算（AI 判替换 / 满 3 天兜底）。
        //
        // 唯一写进库的是 firstSeenAt —— 它属于「露面的生命」，不是「内容的生命」：
        // 记的是「这句话被看到过了」，不是「这句话该不该继续挂着」。

        private func presentCareIfNeeded() {
            // 不在眼前就别演。
            //
            // 挡的不是「白演一场」，是**会把这条关怀标记成看过了**：
            // 从后台回来时用户可能停在广场页，`dataDidChange` 照样打到这儿，
            // 卡片在没人看的首页上滑出、3 秒后落库 —— 这条关怀就这么白说了。
            // 回到首页时 viewDidAppear / pageVisibilityDidChange 会再来一次。
            guard isCurrentPage, !isCoverd else { return }

            guard let care = careViewModel?.activeCare() else {
                // 挂着的那条退场了（AI 换掉了、或满 3 天）—— 卡片跟着收掉。
                // 卡片不会自己走（没有兜底定时器），**没有这一条它会一直挂着一句已经作废的话**。
                dismissCare()
                return
            }

            // 正演着的就是它，别重放
            guard showingCareId != care.id else { return }

            // 换了一条：旧的先淡出，走完再让新的开口。
            // 不能直接盖上去 —— slideIn 会把 alpha 归零再弹回来，旧话新话会闪一下。
            guard showingCareId == nil else {
                dismissCare { [weak self] in self?.presentCareIfNeeded() }
                return
            }

            showingCareId = care.id
            careCard.setText(care.text)

            // 「说」还是「在」—— 整个分叉就在这一行。
            // 一条关怀会在这里露面很多次（每次进首页、每次切 tab 回来都算），
            // 但她**只说了一次**。第一次才配得上滑出和尾巴跟随。
            if care.firstSeenAt == nil {
                setCareForm(.speaking)
                careCard.slideIn()
                scheduleFirstSeen(for: care.id)
                // **不设任何定时器**：第一次就从头清晰到尾。
                // 中途自己淡掉会让人以为看漏了什么 —— 浅下去是下一次进首页的事。
            } else {
                setCareForm(.lingering)
                careCard.appearQuietly()
                // 它不是一次露面，是那句话还在。什么时候消失由关怀引擎说了算
                // （AI 判替换 / 满 3 天兜底），UI 这边只在用户离开首页时收掉它。
            }
        }

        /// 排一个「活满 3 秒就算被看到」。中途被 `dismissCare()` 取消就不算数。
        private func scheduleFirstSeen(for id: UUID) {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.careFirstSeen = nil
                // 传 id 而不是读 showingCareId：这 3 秒里引擎完全可能换了一条，
                // 要记的仍然是**刚才滑出来的那条**。
                self.careViewModel?.markSeen(id)
            }
            careFirstSeen = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.firstSeenDelay, execute: work)
        }

        /// 真的把卡片收掉：用户要操作页面、离开首页，或者这条关怀已经作废。
        /// `completion` 给「换一条」用 —— 旧的淡完才轮到新的开口。
        private func dismissCare(completion: (() -> Void)? = nil) {
            // 没活满 3 秒就被收掉 —— 这次不算「被看到」，下次还是首次
            careFirstSeen?.cancel()
            careFirstSeen = nil
            guard showingCareId != nil else { completion?(); return }
            showingCareId = nil
            careCard.fadeOut(completion: completion)
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            // 212×20 的一摊，压在岛的下沿
            islandShadow.frame = CGRect(x: view.bounds.midX - 106,
                                        y: island.frame.maxY - 6,
                                        width: 212, height: 20)
            CATransaction.commit()
        }
        
        private func updateCopy() {
            dateLabel.attributedText = AppFont.attributed(
                ChineseDate.title(), size: 38, color: Sky.ink, kern: 38 * 0.03, lineHeight: 38 * 1.15
            )
            subLabel.attributedText = AppFont.attributed(
                laidToday ? "今天的蛋在巢里了" : "巢是空的", size: 16, color: Sky.ink(0.42)
            )
            hintLabel.attributedText = AppFont.attributed(
                laidToday ? "往左滑，看这一周" : "轻点鸟巢", size: 15, color: Sky.ink(0.4)
            )
            island.setNestHintVisible(!laidToday)
        }
        
        // MARK: - 帧循环
        
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            island.startBreathing()
            startShadowBreathing()
            island.hen?.resumeRendering()
            startLoop()
            isOnScreen = true
            presentCareIfNeeded()
        }
        
        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            dismissCare()
            stopLoop()
            island.stopBreathing()
            islandShadow.removeAnimation(forKey: "breathe")
            island.hen?.pauseRendering()
        }
        
        private func syncRunningState() {
            let shouldRun = isOnScreen && isCurrentPage && !isCoverd
            guard shouldRun != isRunning else { return }
            isRunning = shouldRun
            
            if shouldRun {
                island.startBreathing()
                startShadowBreathing()
                island.hen?.resumeRendering()
                startLoop()
            } else {
                stopLoop()
                island.stopBreathing()
                islandShadow.removeAnimation(forKey: "breathe")
                island.hen?.pauseRendering()
            }
        }
    
    private func setCovered(_ covered: Bool) {
        isCoverd = covered
        syncRunningState()
        // 写日记 / 聊天的浮层关了，关怀可以回来了。
        // 它们是 overFullScreen，关掉**不走 viewDidAppear** ——
        // 没有这一句，卡片要等到下次进首页才出现。
        if !covered { presentCareIfNeeded() }
        
//        UIView.animate(withDuration: 0.42, delay: 0, usingSpringWithDamping: 0.86, initialSpringVelocity: 0) {
//            self.view.transform = covered ? CGAffineTransform(scaleX: 0.94, y: 0.94) : .identity
//        }
    }
        
        
        
        
        /// 岛升起来的时候影子收窄变淡，两条动画同周期才对得上。
        private func startShadowBreathing() {
            guard islandShadow.animation(forKey: "breathe") == nil else { return }
            
            // 跟岛同周期，子动画各自写满时长（组里不写会退回 0.25s 默认值）
            let half: CFTimeInterval = 3.25
            
            let squeeze = CABasicAnimation(keyPath: "transform.scale.x")
            squeeze.fromValue = 1
            squeeze.toValue = 0.9
            squeeze.duration = half
            
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.34
            fade.toValue = 0.22
            fade.duration = half
            
            let breathe = CAAnimationGroup()
            breathe.animations = [squeeze, fade]
            breathe.duration = half
            breathe.autoreverses = true
            breathe.repeatCount = .infinity
            breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            islandShadow.add(breathe, forKey: "breathe")
        }
        
        private func startLoop() {
            guard displayLink == nil else { return }
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            link.add(to: .main, forMode: .common)
            displayLink = link
            lastTimestamp = 0
        }
        
        private func stopLoop() {
            displayLink?.invalidate()
            displayLink = nil
        }
        
        @objc private func tick(_ link: CADisplayLink) {
            if lastTimestamp == 0 {
                lastTimestamp = link.timestamp
                return
            }
            // 切后台再回来会攒出一个巨大的 dt，钳住，否则母鸡会瞬移
            let dt = min(link.timestamp - lastTimestamp, 1.0 / 20.0)
            lastTimestamp = link.timestamp
            island.tick(dt: dt)
            // 尾巴跟着母鸡走是「这话正从她嘴里出来」的语言，只属于首次那一次露面。
            // lingering 形态下尾巴定在中间不动 —— 那句话已经说完了。
            if showingCareId != nil, careCard.form == .speaking { aimCareTail(dt: dt) }

            
        }
        
    }


extension HomeViewController: RootPage {
    func pageVisibilityDidChange(isCurrent: Bool) {
        isCurrentPage = isCurrent
        syncRunningState()
        if isCurrent {
            // 回到首页。这个回调和 viewDidAppear 谁先谁后不好说，两边都调一次 ——
            // presentCareIfNeeded 是幂等的（正演着的那条不会重放）。
            presentCareIfNeeded()
        } else {
            // 去广场页了 —— 也算「开始操作」，卡片让路
            dismissCare()
        }
    }

    /// 两件事：
    /// ① 日期标题重画。它以前只在 viewDidLoad 画过一次，App 在后台挂一夜回来，
    ///    标题还写着昨天。进前台、跨零点时组合根都会广播到这儿。
    ///    重画是幂等的，同一天里多画几次无所谓，所以不用判断「日子变了没有」。
    /// ② 关怀卡片再看一眼。CareEngine 是在进前台那一轮流程里跑的，
    ///    跑完时 viewDidAppear 多半已经过去了 —— 不靠这个回调卡片就不会出现。
    func dataDidChange() {
        updateCopy()
        presentCareIfNeeded()
    }
}
