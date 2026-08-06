//
//  ChatBubbleCell.swift
//  Slime
//
//  Created by shiying on 2026/8/4.
//

import UIKit
import SnapKit

final class ChatBubbleCell: UICollectionViewCell {
    
    private let bubble: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 16
        return v
    }()
    
    private let label: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 16)
        l.numberOfLines = 0
        return l
    }()
    
    //设左右两套约束，按角色启用
    private var leadingConstraint: Constraint?
    private var trailingConstraint: Constraint?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(bubble)
        bubble.addSubview(label)
        
        bubble.snp.makeConstraints { make in
            make.top.bottom.equalToSuperview().inset(4)
            make.width.lessThanOrEqualToSuperview().multipliedBy(0.75)
            leadingConstraint = make.leading.equalToSuperview().inset(16).constraint
            trailingConstraint = make.trailing.equalToSuperview().inset(16).constraint
        }
        label.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12))
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configure(with item: ChatMessageItem) {
        label.text = item.content
        let isUser = item.role == .user
        //激活一边，松开另一边
        if isUser {
            leadingConstraint?.deactivate()
            trailingConstraint?.activate()
            bubble.backgroundColor = .systemGreen.withAlphaComponent(0.25)
        } else {
            trailingConstraint?.deactivate()
            leadingConstraint?.activate()
            bubble.backgroundColor = .secondarySystemBackground
        }
    }
}
