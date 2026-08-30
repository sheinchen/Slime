//
//  MainViewController.swift
//  Slime
//
//  Created by shiying on 2026/8/15.
//

import UIKit

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
    
    //注入组合根
    var makeComposeViewController: ((_ backdrop: UIImage?, _ onClose: @escaping () -> Void) -> UIViewController)?
    var makeChatViewController: (() -> UIViewController)?
    
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
            guard let self, let chatVC = self.makeChatViewController?() else { return }
            self.present(chatVC,animated: true)
        }
        
    }
        
        private func setupHeader() {
            dateLabel.numberOfLines = 1
            subLabel.numberOfLines = 1
            
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
                hintLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -96),
            ])
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
            dateLabel.attributedText = Kai.attributed(
                ChineseDate.title(), size: 38, color: Sky.ink, kern: 38 * 0.03, lineHeight: 38 * 1.15
            )
            subLabel.attributedText = Kai.attributed(
                laidToday ? "今天的蛋在巢里了" : "巢是空的", size: 16, color: Sky.ink(0.42)
            )
            hintLabel.attributedText = Kai.attributed(
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
            
        }
        
        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
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
            
            
        }
        
    }


extension HomeViewController: PagerPage {
    func pageVisibilityDidChange(isCurrent: Bool) {
        isCurrentPage = isCurrent
        syncRunningState()
    }
}
