//
//  ChatBubbleCell.swift
//  Slime
//

import UIKit
import SnapKit

/// 一条消息。参考图里它不是「聊天气泡」——
/// 没有尾巴、没有头像、没有时间戳，就是一块飘在母鸡身上的圆角色块。
///
/// 你我的区别**不靠左右分边**，靠颜色：她是奶黄，你是更实的橙黄。
/// 左右只错开一点点，保持那种「往上飘」而不是「两方对话」的感觉。
final class ChatBubbleCell: UICollectionViewCell {

    private let bubble = UIView()
    private let label = UILabel()

    /// 左右两套约束，按角色启用一边
    private var leadingConstraint: Constraint?
    private var trailingConstraint: Constraint?

    override init(frame: CGRect) {
        super.init(frame: frame)

        bubble.layer.cornerRadius = 21
        bubble.layer.cornerCurve = .continuous   // 比默认圆角更顺，和素材那种圆润感一致
        contentView.addSubview(bubble)

        label.numberOfLines = 0
        label.textColor = ChatPalette.text
        // 圆体，配这套素材
        if let d = UIFont.systemFont(ofSize: 16, weight: .medium).fontDescriptor.withDesign(.rounded) {
            label.font = UIFont(descriptor: d, size: 16)
        } else {
            label.font = .systemFont(ofSize: 16, weight: .medium)
        }
        bubble.addSubview(label)

        bubble.snp.makeConstraints { make in
            make.top.bottom.equalToSuperview().inset(5)
            make.width.lessThanOrEqualToSuperview().multipliedBy(0.86)
            leadingConstraint = make.leading.equalToSuperview().inset(22).constraint
            trailingConstraint = make.trailing.equalToSuperview().inset(22).constraint
        }
        label.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 13, left: 20, bottom: 13, right: 20))
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// - Parameter depth: 离最新那条有多远。0 = 最新。决定这块色有多实。
    func configure(text: String, role: ChatRole, depth: Int) {
        label.text = text
        bubble.backgroundColor = ChatPalette.bubble(role: role, depth: depth)

        if role == .user {
            leadingConstraint?.deactivate()
            trailingConstraint?.activate()
        } else {
            trailingConstraint?.deactivate()
            leadingConstraint?.activate()
        }
    }
}
