//
//  TutorialOverlay.swift
//  Slime
//
//  示范的蒙层：压暗整屏，只在这一步要碰的地方开一个洞；旁边一个母鸡说话的气泡。
//

import UIKit
import SnapKit

// MARK: - 窗口

/// 蒙层放在**自己的窗口**里，盖在 App 的主窗口上面。
///
/// 为什么不直接 addSubview 到主窗口：写日记页是 present 出来的（overFullScreen），
/// 系统会把它插在主窗口的最上层 —— 蒙层就被压到它底下去了。
/// 单独一个 windowLevel 更高的窗口，不管下面 present 了什么，它永远在最上面。
///
/// **点击怎么穿过去**：UIKit 从最上层的窗口开始问「这个点归谁」，
/// 一个窗口的 hitTest 返回 nil，就接着问下面那个窗口。所以洞里的点返回 nil，
/// 就落到下面的真页面上；其余的点被蒙层自己接住（= 挡掉）。
final class TutorialOverlayWindow: UIWindow {

    let overlay = TutorialOverlayView()

    override init(windowScene: UIWindowScene) {
        super.init(windowScene: windowScene)
        windowLevel = .normal + 1
        backgroundColor = .clear
        let root = UIViewController()
        root.view = overlay
        rootViewController = root
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event) else { return nil }
        return overlay.letsThrough(point) ? nil : hit
    }
}

// MARK: - 蒙层

final class TutorialOverlayView: UIView {

    var onContinue: (() -> Void)?
    var onSkip: (() -> Void)?

    private let dim = CAShapeLayer()
    private let bubble = TutorialBubbleView()

    /// 画出来的洞（比要点的东西大一圈，看着松快）
    private var hole: CGRect?
    /// 真正放行点击的范围。**比画出来的洞小**：只放要点的那个东西本身。
    /// 首页的鸟巢旁边站着母鸡，洞的边上点到的应该是鸟巢、不是她（以前点她会打开聊天，10-02 起不会了，但范围照旧收紧）
    private var touchable: CGRect?
    /// 这一步是「等」：不说话、不压暗，但所有点击都挡掉
    private var isWaiting = true
    /// 第几次换步。气泡淡出的收尾是异步的，连着换两步时，前一步的收尾可能晚到 ——
    /// 对不上号的收尾直接作废，不然会把旧台词写回气泡上
    private var generation = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        dim.fillRule = .evenOdd              // 外框和洞各画一遍，重叠的部分（洞）就空出来
        dim.fillColor = Sky.ink(0.62).cgColor
        dim.opacity = 0
        layer.addSublayer(dim)

        bubble.alpha = 0
        addSubview(bubble)
        bubble.onContinue = { [weak self] in self?.onContinue?() }
        bubble.onSkip = { [weak self] in self?.onSkip?() }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 这个点要不要让给下面的真页面
    func letsThrough(_ point: CGPoint) -> Bool {
        guard !isWaiting, let touchable else { return false }
        return touchable.contains(point) && !bubble.frame.contains(point)
    }

    /// 换一步。气泡先淡掉、换字、再淡回来；「等」的那几步整个淡掉。
    func show(_ scene: TutorialScene) {
        isWaiting = scene.line == nil
        generation += 1
        let current = generation
        UIView.animate(withDuration: 0.18) {
            self.bubble.alpha = 0
        } completion: { _ in
            guard current == self.generation, let line = scene.line else { return }
            self.bubble.configure(line: line, continueTitle: scene.continueTitle, canSkip: scene.canSkip)
            self.setNeedsLayout()
            self.layoutIfNeeded()
            UIView.animate(withDuration: 0.25) { self.bubble.alpha = 1 }
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = dim.presentation()?.opacity ?? dim.opacity
        fade.duration = 0.25
        dim.opacity = isWaiting ? 0 : 1
        dim.add(fade, forKey: "fade")
    }

    /// 协调者每一帧都会调（要点的东西可能在动：岛在浮、月历在展开）。没变就什么都不做。
    func setHole(_ hole: CGRect?, touchable: CGRect?) {
        self.touchable = touchable
        // 洞不出屏幕，左右各留一点边：日历页的鸟巢舞台是通栏的，照原样开洞会顶到屏幕边、像被截断了
        // （还没排版、bounds 是空的时候先照原样用 —— 跟空矩形求交集得到的是 null，不是 nil）
        var hole = hole
        if let raw = hole, !bounds.isEmpty {
            let clipped = raw.intersection(bounds.insetBy(dx: 12, dy: 0))
            hole = clipped.isNull ? nil : clipped
        }
        guard hole != self.hole else { return }
        self.hole = hole
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let path = UIBezierPath(rect: bounds)
        if let hole {
            path.append(UIBezierPath(roundedRect: hole, cornerRadius: min(22, hole.height / 2)))
        }
        // 独立的 CALayer 改属性默认带 0.25 秒隐式动画；洞要跟手，关掉
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dim.frame = bounds
        dim.path = path.cgPath
        CATransaction.commit()

        layoutBubble()
    }

    /// 气泡放在洞的另一边：洞在下半屏就放上面，在上半屏就放下面；没有洞就放中间。
    private func layoutBubble() {
        let width = bounds.width - 44
        let size = bubble.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        let top = safeAreaInsets.top + 12
        let bottom = bounds.height - safeAreaInsets.bottom - 12 - size.height

        var y: CGFloat
        if let hole {
            y = hole.midY > bounds.midY ? hole.minY - 16 - size.height : hole.maxY + 16
        } else {
            y = (bounds.height - size.height) / 2
        }
        y = min(max(y, top), bottom)
        bubble.frame = CGRect(x: 22, y: y, width: width, height: size.height)
    }
}

// MARK: - 气泡

/// 母鸡头像 + 她说的话 + 底下一行按钮（跳过 / 继续）。
private final class TutorialBubbleView: UIView {

    var onContinue: (() -> Void)?
    var onSkip: (() -> Void)?

    private let hen = UIImageView(image: UIImage(named: "hen_idle"))
    private let label = UILabel()
    private let skipButton = UIButton(type: .system)
    private let continueButton = UIButton(type: .custom)
    private let buttonRow = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Sky.bubble
        layer.cornerRadius = 22
        layer.cornerCurve = .continuous
        layer.shadowColor = Sky.bubbleShadow.cgColor
        layer.shadowOpacity = 0.22
        layer.shadowRadius = 18
        layer.shadowOffset = CGSize(width: 0, height: 8)

        hen.contentMode = .scaleAspectFit
        label.numberOfLines = 0

        skipButton.setAttributedTitle(AppFont.attributed("跳过示范", size: 14, color: Sky.ink(0.4)), for: .normal)
        skipButton.addTarget(self, action: #selector(skipTapped), for: .touchUpInside)

        continueButton.backgroundColor = Palette.beak
        continueButton.layer.cornerRadius = 17
        continueButton.layer.cornerCurve = .continuous
        continueButton.addTarget(self, action: #selector(continueTapped), for: .touchUpInside)

        // 弹簧：跳过靠左，继续靠右。按钮顶到 required 不许被拉宽，多出来的宽度全给弹簧
        let spring = UIView()
        spring.setContentHuggingPriority(.init(1), for: .horizontal)
        for button in [skipButton, continueButton] {
            button.setContentHuggingPriority(.required, for: .horizontal)
        }
        buttonRow.axis = .horizontal
        buttonRow.alignment = .center
        buttonRow.addArrangedSubview(skipButton)
        buttonRow.addArrangedSubview(spring)
        buttonRow.addArrangedSubview(continueButton)

        // 字和按钮行竖着叠进一个 stack：按钮行藏起来时，stack 会把它从排版里整个拿掉，
        // 气泡底下不会空出一截（普通约束做不到 —— 藏起来的 view 照样占着位置）
        let column = UIStackView(arrangedSubviews: [label, buttonRow])
        column.axis = .vertical
        column.spacing = 10

        addSubview(hen)
        addSubview(column)

        hen.snp.makeConstraints { make in
            make.top.leading.equalToSuperview().inset(14)
            make.size.equalTo(44)
            // 话只有一行时，气泡也得包得住母鸡
            make.bottom.lessThanOrEqualToSuperview().inset(14)
        }
        column.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(18)
            make.leading.equalTo(hen.snp.trailing).offset(10)
            make.trailing.equalToSuperview().inset(16)
            make.bottom.equalToSuperview().inset(14)
        }
        continueButton.snp.makeConstraints { make in
            make.height.equalTo(34)
            // 按钮上的字都很短（好 / 嗯 / 知道了 / 开始），给个最小宽度就够，不用算内边距
            make.width.greaterThanOrEqualTo(76)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(line: String, continueTitle: String?, canSkip: Bool) {
        label.attributedText = AppFont.attributed(line, size: 16, color: Sky.ink, lineHeight: 16 * 1.5)
        if let continueTitle {
            continueButton.setAttributedTitle(AppFont.attributed(continueTitle, size: 15, color: .white), for: .normal)
        }
        continueButton.isHidden = continueTitle == nil
        skipButton.isHidden = !canSkip
        buttonRow.isHidden = continueTitle == nil && !canSkip
    }

    @objc private func skipTapped() {
        onSkip?()
    }

    @objc private func continueTapped() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        onContinue?()
    }
}
