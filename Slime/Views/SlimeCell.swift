//
//  SlimeCell.swift
//  Slime
//
//  广场里的一个格子:嵌一个可复用的 SlimeView(史莱姆本体)+ 日期。
//

import UIKit
import SnapKit

final class SlimeCell: UICollectionViewCell {

    // 史莱姆视图。cell 只负责把它摆好、把数据喂给它;怎么画/怎么动都在 SlimeView 内部。
    private let slimeView = SlimeView()

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
        contentView.addSubview(slimeView)
        contentView.addSubview(dateLabel)

        dateLabel.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
        }
        slimeView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.bottom.equalTo(dateLabel.snp.top).offset(-4)
        }
    }

    /// 把一条展示数据灌进 cell。Diffable 会在需要时替我们调用它。
    func configure(with item: SlimeItem) {
        // 本切片只用默认情绪;以后这里根据 item 的情绪设置 slimeView.emotion
        slimeView.emotion = .happy
        dateLabel.text = Self.dateFormatter.string(from: item.createdAt)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f
    }()
}
