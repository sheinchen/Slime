//
//  Diary.swift
//  Slime
//
//  Created by shiying on 2026/8/24.
//

import Foundation
import UIKit
import SnapKit

final class DiaryEntryCell: UICollectionViewCell {
    
    private let digestLabel = UILabel()
    private let timeLabel = UILabel()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        //关掉系统自定的选中
        automaticallyUpdatesBackgroundConfiguration = false
        backgroundColor = .clear
        
        contentView.addSubview(digestLabel)
        contentView.addSubview(timeLabel)
        
        digestLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(14)
            make.centerY.equalToSuperview()
            make.trailing.lessThanOrEqualTo(timeLabel.snp.leading).offset(-12)
        }
        timeLabel.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-26)
            make.centerY.equalToSuperview()
        }
        contentView.snp.makeConstraints { make in
            make.height.equalTo(64)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configure(_ item: SlimeItem) {
        digestLabel.attributedText = Kai.attributed(Self.digest(item.content), size: 17, color: Sky.ink(0.84))
        timeLabel.attributedText = Kai.attributed(Self.timeFormatter.string(from: item.createdAt), size: 14, color: Sky.ink(0.36))
    }
    
    private static func digest(_ content: String) -> String {
        let flat = content.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return flat.count <= 14 ? flat : String(flat.prefix(14)) + "..."
    }
    
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}
