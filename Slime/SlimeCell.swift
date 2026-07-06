//
//  SlimeCell.swift
//  Slime
//
//  广场里的一个格子:纯色圆角方块占位一只史莱姆 + 日期。
//  切片 1 不接情绪,颜色先按 id 稳定地从调色板里挑一个。
//

import UIKit
import SnapKit

final class SlimeCell: UICollectionViewCell {

    // 史莱姆占位方块
    private let box: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 16
        return v
    }()

    // 日期小标签(区分手段之一:文档里说靠 颜色/大小/日期 区分每只史莱姆)
    private let dateLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        return label
    }()

    // 代码创建 cell 必须实现这个 init
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        contentView.addSubview(box)
        contentView.addSubview(dateLabel)

        dateLabel.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
        }
        box.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.bottom.equalTo(dateLabel.snp.top).offset(-4)
        }
    }

    /// 把一条展示数据灌进 cell。Diffable 会在需要时替我们调用它。
    func configure(with item: SlimeItem) {
        box.backgroundColor = Self.color(for: item.id)
        dateLabel.text = Self.dateFormatter.string(from: item.createdAt)
    }

    // MARK: - 占位颜色 & 日期

    // 情绪色板(黄/绿/蓝/橙),对应 PRD 里开心/平静/难过/生气。切片 1 只是占位,不代表真实情绪。
    private static let palette: [UIColor] = [
        UIColor(red: 1.00, green: 0.84, blue: 0.35, alpha: 1),  // 黄
        UIColor(red: 0.55, green: 0.80, blue: 0.55, alpha: 1),  // 绿
        UIColor(red: 0.50, green: 0.70, blue: 0.95, alpha: 1),  // 蓝
        UIColor(red: 1.00, green: 0.60, blue: 0.35, alpha: 1),  // 橙
    ]

    // 用 UUID 的第一个字节对调色板取模 —— 同一篇帖子每次启动都是同一个颜色(稳定)
    private static func color(for id: UUID) -> UIColor {
        let firstByte = id.uuid.0
        return palette[Int(firstByte) % palette.count]
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f
    }()
}
