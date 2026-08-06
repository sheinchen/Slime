//
//  CareBubbleView.swift
//  Slime
//
//  Created by shiying on 2026/7/31.
//

import UIKit
import SnapKit

final class CareBubbleView: UIView {
    
    var onFirstExpand: (() -> Void)? //第一次点开 状态变read
    var onDismiss: (() -> Void)? //气泡消失
    var onChat: (() -> Void)? //进入聊天
    
    
    private let fullText: String
    private var isExpanded = false
    
    private let slime = SlimeView()
    
    private let bubbleLabel: UILabel = {
        let label = UILabel()
        label.text = "..."
        label.font = .systemFont(ofSize: 15)
        label.textColor = .label
        label.numberOfLines = 0
        return label
    }()
    
    private let bubbleBackground: UIView = {
        let v = UIView()
        v.backgroundColor = .secondarySystemBackground
        v.layer.cornerRadius = 14
        return v
    }()
    
    private let chatButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("聊聊`", for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        b.isHidden = true
        return b
    }()
    
    init(text: String) {
        self.fullText = text
        super.init(frame: .zero)
        setupUI()
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        chatButton.addTarget(self, action: #selector(chatTapped), for: .touchUpInside)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        addSubview(slime)
        addSubview(bubbleBackground)
        bubbleBackground.addSubview(bubbleLabel)
        bubbleBackground.addSubview(chatButton)
        
        slime.snp.makeConstraints { make in
            make.leading.bottom.equalToSuperview()
            make.width.height.equalTo(48)
        }
        bubbleBackground.snp.makeConstraints { make in
            make.leading.equalTo(slime.snp.trailing).offset(6)
            make.top.trailing.equalToSuperview()
            make.bottom.lessThanOrEqualToSuperview()
        }
        bubbleLabel.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview().inset(10)
        }
        chatButton.snp.makeConstraints { make in
            make.top.equalTo(bubbleLabel.snp.bottom).offset(2)
            make.trailing.equalToSuperview().inset(10)
            make.bottom.equalToSuperview().inset(4)
        }
        
        
    
    }
    
    //MARK: 演出
    func playEntrance() {
        alpha = 0
        transform = CGAffineTransform(translationX: 0, y: 12)
        UIView.animate(withDuration: 0.6, delay: 0/15,
                       usingSpringWithDamping: 0.8, initialSpringVelocity: 0) {
            self.alpha = 1
            self.transform = .identity
        }
    }
    
    private func playExit() {
        UIView.animate(withDuration: 0.35, animations: {
            self.alpha = 0
            self.transform = CGAffineTransform(translationX: 0, y: 8)
        }, completion: { _ in
            self.onDismiss?()
        })
    
        
    }
    
    //点开气泡
    private func expand() {
        isExpanded = true
        chatButton.isHidden = false
        onFirstExpand?()
        bubbleLabel.text = fullText
        UIView.animate(withDuration: 0.45, delay: 0,
                       usingSpringWithDamping: 0.85, initialSpringVelocity: 0) {
            self.superview?.layoutIfNeeded()
        }
    }
    
    @objc private func tapped() {
        if isExpanded {
            playExit()
        } else {
            expand()
        }
    }
    
    @objc private func chatTapped() {
        onChat?()
    }
    
    
}
