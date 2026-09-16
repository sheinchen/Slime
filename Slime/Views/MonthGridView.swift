//
//  MonthGridView.swift
//  Slime
//
//  月历：一行表头 +（最多）六行 WeekRowView。
//  一个月的蛋摆在一起，就是这个月的情绪地图。
//
//  它只管画，不管展开收起 —— 高度由外面的约束控制，
//  所以收起到 0 的时候内容要被裁掉（clipsToBounds）。
//

import UIKit
import SnapKit

final class MonthGridView: UIView {

    var onSelect: ((SquareViewModel.Day) -> Void)?

    /// 当前这个月画出来需要多高。外面拿它当展开动画的目标高度。
    /// 会随月份变（有的月份跨 5 周，有的跨 6 周）。
    private(set) var contentHeight: CGFloat = 0

    private static let maxRows = 6
    private static let rowHeight: CGFloat = 50
    private static let spacing: CGFloat = 4
    private static let headerHeight: CGFloat = 16
    /// 表头和第一行之间单独留的间距。和行距一样宽的话，
    /// 「日一二…」会和第一行日期粘成一坨
    private static let headerGap: CGFloat = 10
    private static let padding: CGFloat = 10
    private static let names = ["日", "一", "二", "三", "四", "五", "六"]

    private let column = UIStackView()
    private var rows: [WeekRowView] = []

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = Palette.grassSide
        layer.cornerRadius = 22
        layer.cornerCurve = .continuous
        // 高度被压到 0 时，内容要跟着被裁掉，不然会溢出到卡片上
        clipsToBounds = true

        column.axis = .vertical
        column.spacing = Self.spacing
        addSubview(column)
        // 注意只钉 top，不钉 bottom —— 高度归外面的约束管，
        // 钉了 bottom 会和高度约束打架
        column.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(Self.padding)
            make.leading.trailing.equalToSuperview().inset(6)
        }

        let header = makeHeader()
        column.addArrangedSubview(header)
        // UIStackView 的 spacing 是统一的，要给某一个间隙单独加宽就用这个
        column.setCustomSpacing(Self.headerGap, after: header)

        for _ in 0..<Self.maxRows {
            let row = WeekRowView(style: .month)
            row.onSelect = { [weak self] day in
                self?.onSelect?(day)
            }
            row.snp.makeConstraints { make in
                make.height.equalTo(Self.rowHeight)
            }
            column.addArrangedSubview(row)
            rows.append(row)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 喂一个月的周。少于 6 周时多余的行藏起来 ——
    /// 六行都是一开始就建好的，不反复创建销毁。
    func configure(weeks: [SquareViewModel.Week]) {
        for (index, row) in rows.enumerated() {
            if index < weeks.count {
                row.isHidden = false
                row.configure(weeks[index])
            } else {
                row.isHidden = true
            }
        }

        let visible = CGFloat(min(weeks.count, Self.maxRows))
        // 和上面的布局一一对应：上内边距 + 表头 + 间隔 + N 行 +(N-1)个行间隔 + 下内边距
        contentHeight = Self.padding
            + Self.headerHeight
            + Self.headerGap
            + visible * Self.rowHeight
            + max(visible - 1, 0) * Self.spacing
            + Self.padding
    }

    // MARK: - 表头

    /// 「日一二三四五六」只在最上面出现一行 ——
    /// 所以下面的 WeekRowView 都传 showsWeekday: false
    private func makeHeader() -> UIView {
        let header = UIStackView()
        header.axis = .horizontal
        header.distribution = .fillEqually
        for name in Self.names {
            let label = UILabel()
            label.textAlignment = .center
            label.attributedText = Kai.attributed(name, size: 13,
                                                  color: Palette.grassInk.withAlphaComponent(0.62))
            header.addArrangedSubview(label)
        }
        header.snp.makeConstraints { make in
            make.height.equalTo(Self.headerHeight)
        }
        return header
    }
}
