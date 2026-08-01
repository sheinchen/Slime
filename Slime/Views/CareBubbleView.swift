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
    
    init(text: String) {
        self.fullText = text
        super.init(frame: .zero)
        setupUI()
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        addSubview(slime)
        addSubview(bubbleBackground)
        bubbleBackground.addSubview(bubbleLabel)
        
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
            make.edges.equalToSuperview().inset(10)
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
    
    
}
