//
//  WeekRowView.swift
//  Slime
//
//  一周七格。周条的每一页是一个，月历的每一行也是一个 ——
//  两处共用同一套格子，所以「有蛋画蛋、选中画高亮」这套逻辑只有一份。
//

import UIKit
import SnapKit

final class WeekRowView: UIView {

    /// 两种摆法。它们的差异不止一处（星期名、蛋多大、日期显不显示、高亮什么形状），
    /// 所以用一个枚举统一表达，而不是堆好几个布尔参数。
    enum Style {
        /// 周条：顶上有星期名，蛋大；有蛋就让位给蛋，不画日期
        case strip
        /// 月历：没有星期名（表头只有一行），蛋小；**日期永远画在蛋下面**
        case month
    }

    var onSelect: ((SquareViewModel.Day) -> Void)?

    private let row = UIStackView()
    private var cells: [DayCell] = []

    private static let names = ["日", "一", "二", "三", "四", "五", "六"]

    init(style: Style) {
        super.init(frame: .zero)

        row.axis = .horizontal
        row.distribution = .fillEqually
        addSubview(row)
        row.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        for index in 0..<7 {
            let cell = DayCell(style: style,
                               weekdayName: style == .strip ? Self.names[index] : nil)
            cell.addTarget(self, action: #selector(cellTapped), for: .touchUpInside)
            row.addArrangedSubview(cell)
            cells.append(cell)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ week: SquareViewModel.Week) {
        for (cell, day) in zip(cells, week.days) {
            // week.selected 为 nil（选中日不在这一周）时整行都不高亮
            cell.configure(day, isSelected: day.date == week.selected)
        }
    }

    @objc private func cellTapped(_ sender: DayCell) {
        guard let day = sender.day else { return }
        onSelect?(day)
    }
}

// MARK: - 一格

private final class DayCell: UIControl {

    private(set) var day: SquareViewModel.Day?

    private let style: WeekRowView.Style
    private let weekday = UILabel()
    private let number = UILabel()
    private let egg = EggView()
    private let highlight = UIView()

    private static let ink = Palette.grassInk

    init(style: WeekRowView.Style, weekdayName: String?) {
        self.style = style
        super.init(frame: .zero)

        highlight.backgroundColor = UIColor.white.withAlphaComponent(0.45)
        highlight.layer.cornerCurve = .continuous
        highlight.isHidden = true
        addSubview(highlight)

        weekday.textAlignment = .center
        number.textAlignment = .center
        addSubview(weekday)
        addSubview(egg)
        addSubview(number)

        // 这几个都不吃点击，整格的点击由 DayCell 自己（UIControl）接
        [weekday, number, egg, highlight].forEach {
            $0.isUserInteractionEnabled = false
        }

        switch style {
        case .strip:
            // 星期名在最上，蛋在中间，数字压在蛋的位置上 —— 有蛋时藏起来，没蛋时顶上
            weekday.attributedText = AppFont.attributed(weekdayName ?? "", size: 13,
                                                    color: Self.ink.withAlphaComponent(0.62))
            weekday.snp.makeConstraints { make in
                make.top.centerX.equalToSuperview()
            }
            egg.snp.makeConstraints { make in
                make.top.equalTo(weekday.snp.bottom).offset(4)
                make.centerX.equalToSuperview()
                make.width.height.equalTo(38)
            }
            number.snp.makeConstraints { make in
                make.center.equalTo(egg)
            }
            highlight.snp.makeConstraints { make in
                make.center.equalTo(egg)
                make.width.height.equalTo(egg).offset(8)
            }

        case .month:
            // 日期在上、蛋在下 —— 日历通用的排法。
            // 反过来（蛋在上）会让蛋看着像属于上一行的日期，行距再大也纠正不过来。
            weekday.isHidden = true
            number.snp.makeConstraints { make in
                make.top.centerX.equalToSuperview()
            }
            // 没蛋的格子里 egg 虽然 isHidden，但约束照常生效、照样占 30pt，
            // 所以整个月的日期数字是**对齐**的 —— 一行数字，下面零星挂着蛋
            egg.snp.makeConstraints { make in
                make.top.equalTo(number.snp.bottom).offset(1)
                make.centerX.equalToSuperview()
                make.width.height.equalTo(30)
            }
            // 圈整格而不是圈蛋：没蛋的日子如果只圈蛋的位置，
            // 就会在一片空白上画个圈、数字反而落在圈外面
            highlight.snp.makeConstraints { make in
                make.edges.equalToSuperview().inset(UIEdgeInsets(top: 0, left: 3, bottom: 0, right: 3))
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ day: SquareViewModel.Day, isSelected: Bool) {
        self.day = day

        // 删了一篇、正在重孵的那天画没表情的绿壳 —— 照实画的话蛋会变回数字，几秒后又变回蛋。
        // 格子会被复用，isBlank 每次都要显式给，不能只在重孵时设
        egg.blankStyle = .rehatch
        egg.isBlank = day.isRehatching
        egg.emotion = day.isRehatching ? nil : day.egg?.emotion
        // 月历里不属于这一页的日子（首行的上月末、末行的下月初）不画蛋：
        // 同一天会在相邻两页各出现一次，只在它自己那个月里算数 ——
        // 这一页的「情绪地图」里只该有这个月的蛋
        egg.isHidden = day.isOutsideMonth || (!day.isRehatching && day.egg == nil)
        // 周条里蛋和数字抢同一个位置；月历里数字有自己的一行，永远显示
        number.isHidden = style == .strip ? !egg.isHidden : false

        let inkAlpha: CGFloat = day.isOutsideMonth ? 0.28 : (day.isToday ? 0.95 : 0.66)
        number.attributedText = AppFont.attributed(
            "\(day.number)", size: style == .strip ? 16 : 13,
            color: Self.ink.withAlphaComponent(inkAlpha)
        )
        // 选中日落在邻月那几格时也不圈 —— 圈只画在它自己那一页上
        highlight.isHidden = !isSelected || day.isOutsideMonth

        // 未来的日子不可点 —— 那天不可能有日记，选中它只会得到一个空列表。
        // UIControl 的 isEnabled 会直接挡掉 touch，不用自己判。
        isEnabled = !day.isFuture
        alpha = day.isFuture ? 0.4 : 1
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        switch style {
        case .strip: highlight.layer.cornerRadius = highlight.bounds.height / 2
        case .month: highlight.layer.cornerRadius = 12
        }
    }
}
