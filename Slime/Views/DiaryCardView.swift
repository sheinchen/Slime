//
//  DiaryCardView.swift
//  Slime
//
//  广场页卡片堆里的一张 = 一篇日记的全文。
//  取代了原来「DiaryEntryCell 列表 → 点开 DiaryDetailView」两层 ——
//  一张就是全文，不用再往里走一层。
//

import UIKit
import SnapKit

final class DiaryCardView: UIView {

    static let cornerRadius: CGFloat = 26

    private(set) var item: SlimeItem

    /// 卡片里竖着滚全文的那个手势。堆叠视图要拿它设「等横滑先判定」
    var scrollPan: UIPanGestureRecognizer { scrollView.panGestureRecognizer }

    /// 真正白色、带圆角的那一层
    private let surface = UIView()
    private let timeLabel = UILabel()
    private let scrollView = ContentScrollView()
    private let contentLabel = UILabel()

    /// 卡片底部那层白色渐隐：下面还有没看到的内容时浮出来，滚到底就没了。
    /// 卡片里不显示滚动条，这是唯一一个「还有更多」的提示
    private let fade = FadeView()
    private static let fadeHeight: CGFloat = 44

    // MARK: - 编辑模式（像桌面删 App：长按 → 抖 + 出叉 → 点叉）

    /// 点了左上角的叉。真正删数据是 VC → VM 的事，这里只负责报上去
    var onDeleteTap: (() -> Void)?
    private(set) var isEditing = false

    /// 挂在自己身上而不是 surface 上：surface 按圆角裁剪，
    /// 叉正好压在圆角缺掉的那块上，挂在 surface 上会被裁掉一半。
    private let deleteBadge = UIButton(type: .custom)
    private static let badgeSide: CGFloat = 26
    private static let wiggleKey = "wiggle"

    init(item: SlimeItem) {
        self.item = item
        super.init(frame: .zero)

        // 影子挂在自己的 layer 上，圆角和裁剪放在 surface 上。
        // 两件事不能放同一层：clipsToBounds 会把影子一起裁掉。
        // 影子收得很紧：只够把卡片边缘和底下那几层分开，不要「悬在半空」的感觉
        backgroundColor = .clear
        layer.shadowColor = UIColor(hex: 0x6B5B45).cgColor
        layer.shadowOpacity = 0.07
        layer.shadowRadius = 6
        layer.shadowOffset = CGSize(width: 0, height: 2)

        surface.backgroundColor = .white
        surface.layer.cornerRadius = Self.cornerRadius
        surface.layer.cornerCurve = .continuous
        surface.clipsToBounds = true

        contentLabel.numberOfLines = 0
        scrollView.showsVerticalScrollIndicator = false
        scrollView.delegate = self
        // contentSize 是在 scrollView 自己的 layoutSubviews 里算出来的，
        // 而那一步发生在本类的 layoutSubviews **之后**（布局是自上而下跑的）。
        // 所以渐隐只能等它回报，不能在自己的 layoutSubviews 里读 —— 那时候读到的是 0
        scrollView.onLayout = { [weak self] in self?.updateFade() }

        addSubview(surface)
        surface.addSubview(timeLabel)
        surface.addSubview(scrollView)
        scrollView.addSubview(contentLabel)
        // 加在 scrollView 之后 = 盖在它上面。它不吃触摸，手指照样能滚到底下的正文
        surface.addSubview(fade)

        surface.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        timeLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(22)
            make.leading.equalToSuperview().offset(26)
        }
        scrollView.snp.makeConstraints { make in
            make.top.equalTo(timeLabel.snp.bottom).offset(12)
            make.leading.trailing.bottom.equalToSuperview()
        }
        // 四条边全挂 contentLayoutGuide —— 它的大小就是 contentSize，
        // 少挂一边那个方向就没人定，算出来是 0。
        // 宽度另外锁在 frameLayoutGuide 上：内容宽 == 卡片宽 = 横向没得滚，只能竖着滚
        contentLabel.snp.makeConstraints { make in
            make.top.equalTo(scrollView.contentLayoutGuide).offset(4)
            make.bottom.equalTo(scrollView.contentLayoutGuide).offset(-28)
            make.leading.trailing.equalTo(scrollView.contentLayoutGuide).inset(26)
            make.width.equalTo(scrollView.frameLayoutGuide).offset(-52)
        }
        // 贴着卡片底边，跟着 surface 的圆角一起被裁掉
        fade.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
            make.height.equalTo(Self.fadeHeight)
        }

        setupDeleteBadge()
        configure(item)
    }

    private func setupDeleteBadge() {
        let glyph = UIImage(systemName: "xmark",
                            withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .bold))
        deleteBadge.setImage(glyph, for: .normal)
        deleteBadge.tintColor = .white
        deleteBadge.backgroundColor = Sky.ink(0.55)
        deleteBadge.layer.cornerRadius = Self.badgeSide / 2
        deleteBadge.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        // 平时缩小藏着。alpha 为 0 的 view 不参与点击判定，所以不用另外关交互
        deleteBadge.alpha = 0
        deleteBadge.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
        addSubview(deleteBadge)
        deleteBadge.snp.makeConstraints { make in
            make.size.equalTo(Self.badgeSide)
            // 圆心落在左上圆角上，一半压着卡片、一半探出去 —— 桌面图标的叉也是这么挂的。
            // 不能再往外挪：超出卡片边界的部分点不到（UIKit 只把触摸派给落在父 view 范围内的子 view）
            make.centerX.equalTo(snp.leading).offset(11)
            make.centerY.equalTo(snp.top).offset(11)
        }
    }

    @objc private func deleteTapped() {
        onDeleteTap?()
    }

    /// 进出编辑模式：抖起来 + 叉弹出来，或者反过来。
    func setEditing(_ editing: Bool, animated: Bool) {
        guard editing != isEditing else { return }
        isEditing = editing
        if editing {
            startWiggle()
        } else {
            layer.removeAnimation(forKey: Self.wiggleKey)
        }

        let apply = {
            self.deleteBadge.alpha = editing ? 1 : 0
            self.deleteBadge.transform = editing ? .identity : CGAffineTransform(scaleX: 0.3, y: 0.3)
        }
        guard animated else { return apply() }
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.7,
                       initialSpringVelocity: 0, animations: apply)
    }

    /// 绕中心左右各转一点点。卡片比 App 图标大得多，角度要给小 ——
    /// 0.7° 在卡片四角已经是两三个点的位移，再大就像要掉下来。
    private func startWiggle() {
        // 系统设置里开了「减弱动态效果」就不抖，只出叉。叉本身已经说明了现在是什么模式
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        let angle = 0.7 * CGFloat.pi / 180
        let wiggle = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        wiggle.values = [-angle, angle, -angle]
        wiggle.duration = 0.28
        wiggle.repeatCount = .infinity
        // 叠加在当前 transform 上，而不是替换它：编辑模式下还能横拖翻卡，
        // 拖动时卡片自己有平移和倾斜，不叠加的话一抖就把拖动的位置抹掉了
        wiggle.isAdditive = true
        // 切到后台再回来，Core Animation 会把「已完成」的动画摘掉；无限循环的也会被算进去
        wiggle.isRemovedOnCompletion = false
        layer.add(wiggle, forKey: Self.wiggleKey)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 影子的形状显式给出来。不给的话 Core Animation 每帧都要按内容的像素
    /// 现算一遍轮廓 —— 拖动时卡片一直在转、在缩，会明显掉帧。
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: Self.cornerRadius).cgPath
    }

    func configure(_ item: SlimeItem) {
        self.item = item
        timeLabel.attributedText = AppFont.attributed(Self.timeFormatter.string(from: item.createdAt),
                                                  size: 14, color: Sky.ink(0.36))
        contentLabel.attributedText = AppFont.attributed(item.content, size: 18,
                                                     color: Sky.ink(0.86), lineHeight: 18 * 1.7)
    }

    /// 被抽走、塞回堆底时调：下次轮到它时从头看
    func scrollToTop() {
        scrollView.setContentOffset(.zero, animated: false)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}

// MARK: - 底部渐隐

extension DiaryCardView: UIScrollViewDelegate {

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateFade()
    }

    /// 下面还剩多少没露出来，就给多少不透明度。
    ///
    /// 用渐隐层自己的高度当换算尺度：剩的内容一旦短于这 44pt，它本来就落在渐隐区里，
    /// 这时候按比例把渐隐一起淡掉，正好「你快看完了」和「已经看完了」是连续的，
    /// 不会在最后一下啪地消失。
    ///
    /// 回弹过头时这个数会跑到 0 以下或 1 以上，夹住就行。
    fileprivate func updateFade() {
        let remaining = scrollView.contentSize.height
            - scrollView.bounds.height
            - scrollView.contentOffset.y
        fade.alpha = min(max(remaining / Self.fadeHeight, 0), 1)
    }
}

/// 一个会回报「我布局完了」的 scrollView。
///
/// 存在的唯一理由：`contentSize` 由 Auto Layout 在这个 `layoutSubviews` 里算出来，
/// 外层想按它决定渐隐浓淡，就得等这一刻 —— 外层自己的 `layoutSubviews` 跑在这之前。
private final class ContentScrollView: UIScrollView {

    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

/// 一块纯渐变。
///
/// `layerClass` 换成 `CAGradientLayer` 之后，这个 view 的**根 layer 本身**就是渐变层 ——
/// 于是它跟着 Auto Layout 自动改尺寸，不用在 layoutSubviews 里手动同步 frame
/// （单独挂一个子 layer 就得手动同步，而且每次改 frame 还会带一段隐式动画）。
private final class FadeView: UIView {

    override class var layerClass: AnyClass { CAGradientLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false

        let gradient = layer as! CAGradientLayer
        // 必须用「透明度为 0 的白」，不能用 .clear ——
        // .clear 是 (0,0,0,0)，是**黑色**的透明，往白色插值的路上会经过一片灰，
        // 看起来像卡片底下脏了一块
        let clearWhite = UIColor.white.withAlphaComponent(0)
        gradient.colors = [clearWhite.cgColor,
                           UIColor.white.withAlphaComponent(0.6).cgColor,
                           UIColor.white.cgColor]
        // 三个色标、上半段爬得慢：顶边不会留下一条看得见的起始线
        gradient.locations = [0, 0.55, 1]
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
