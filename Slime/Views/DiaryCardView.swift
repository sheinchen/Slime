//
//  DiaryCardView.swift
//  Slime
//
//  广场页卡片堆里的一张 = 一篇日记的全文 + 母鸡那句回应。
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
    private let scrollView = UIScrollView()
    private let contentLabel = UILabel()
    private let divider = UIView()
    private let replyLabel = UILabel()

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
        replyLabel.numberOfLines = 0
        divider.backgroundColor = UIColor(hex: 0xEAE4D6)
        scrollView.showsVerticalScrollIndicator = false

        addSubview(surface)
        surface.addSubview(timeLabel)
        surface.addSubview(scrollView)
        scrollView.addSubview(contentLabel)
        scrollView.addSubview(divider)
        scrollView.addSubview(replyLabel)

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
        // 竖直方向挂 contentLayoutGuide（撑出滚动高度），
        // 水平方向挂 frameLayoutGuide（宽度锁死在卡片内，只能竖着滚）
        contentLabel.snp.makeConstraints { make in
            make.top.equalTo(scrollView.contentLayoutGuide).offset(4)
            make.leading.trailing.equalTo(scrollView.frameLayoutGuide).inset(26)
        }
        divider.snp.makeConstraints { make in
            make.top.equalTo(contentLabel.snp.bottom).offset(22)
            make.leading.trailing.equalTo(scrollView.frameLayoutGuide).inset(26)
            make.height.equalTo(1)
        }
        replyLabel.snp.makeConstraints { make in
            make.top.equalTo(divider.snp.bottom).offset(18)
            make.leading.trailing.equalTo(scrollView.frameLayoutGuide).inset(26)
            make.bottom.equalTo(scrollView.contentLayoutGuide).offset(-28)
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

        let reply = item.reply?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        replyLabel.attributedText = reply.isEmpty ? nil
            : AppFont.attributed(reply, size: 15, color: Sky.ink(0.5), lineHeight: 15 * 1.6)
        divider.isHidden = reply.isEmpty
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
