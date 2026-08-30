//
//  DiaryDetailView.swift
//  Slime
//
//  Created by shiying on 2026/8/24.
//

import Foundation
import SnapKit
import UIKit

final class DiaryDetailView: UIView {
    
    var onBack: (() -> Void)?
    
    private let timeLabel = UILabel()
    private let scrollView = UIScrollView()
    private let contentLabel = UILabel()
    private let divider = UIView()
    private let replyLabel = UILabel()
    
    override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear


            contentLabel.numberOfLines = 0
            replyLabel.numberOfLines = 0
            divider.backgroundColor = UIColor(hex: 0xEAE4D6)
            scrollView.showsVerticalScrollIndicator = false

            addSubview(timeLabel)
            addSubview(scrollView)
            scrollView.addSubview(contentLabel)
            scrollView.addSubview(divider)
            scrollView.addSubview(replyLabel)

            timeLabel.snp.makeConstraints { make in
                make.bottom.equalToSuperview().offset(-8)
                make.trailing.equalToSuperview().offset(-8)
            }
            scrollView.snp.makeConstraints { make in
                make.top.leading.trailing.bottom.equalToSuperview()
            }

            // 竖直方向挂 contentLayoutGuide,水平方向挂 frameLayoutGuide —— 见下面的说明
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
                make.bottom.equalTo(scrollView.contentLayoutGuide).offset(-24)
            }
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(Tapped))
        addGestureRecognizer(tap)
        }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configure(_ item: SlimeItem) {
           timeLabel.attributedText = Kai.attributed(Self.timeFormatter.string(from: item.createdAt),
                                                     size: 14, color: Sky.ink(0.4))
           contentLabel.attributedText = Kai.attributed(item.content, size: 18,
                                                        color: Sky.ink(0.86), lineHeight: 18 * 1.7)

           // AI 那句回应,数据早就存好了,这里终于有地方放
           let reply = item.reply?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
           replyLabel.attributedText = reply.isEmpty ? nil
               : Kai.attributed(reply, size: 15, color: Sky.ink(0.5), lineHeight: 15 * 1.6)
           divider.isHidden = reply.isEmpty

           scrollView.setContentOffset(.zero, animated: false)   // 每次进来从头看
       }

    @objc private func Tapped() {
        guard !scrollView.isDragging, !scrollView.isDecelerating else { return }
        onBack?()
        }
    
    private static let timeFormatter: DateFormatter = {
          let f = DateFormatter()
          f.dateFormat = "HH:mm"
          return f
      }()
}
