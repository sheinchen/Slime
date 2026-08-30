//
//  WeekStripView.swift
//  Slime
//
//  Created by shiying on 2026/8/24.
//

import Foundation
import SnapKit
import UIKit

final class WeekStripView: UIView {
    
    var onSelect: ((SquareViewModel.Day) -> Void)?
    
    private let row = UIStackView()
    private var cells: [DayCell] = []
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Palette.grassSide
        layer.cornerRadius = 22
        layer.cornerCurve = .continuous
        
        row.axis = .horizontal
        row.distribution = .fillEqually
        addSubview(row)
        row.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 12, left: 6, bottom: 12, right: 6))
        }
        
        for index in 0..<7 {
            let cell = DayCell(weekdayIndex: index)
            cell.addTarget(self, action: #selector(cellTapped), for: .touchUpInside)
            row.addArrangedSubview(cell)
            cells.append(cell)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configure(days: [SquareViewModel.Day], selected: Date) {
        for (cell, day) in zip(cells, days) {
            cell.configure(day, isSelected: day.date == selected)
        }
    }
    
    @objc private func cellTapped(_ sender: DayCell) {
        guard let day = sender.day else { return }
        onSelect?(day)
    }
    
}


private final class DayCell: UIControl {
    
    private(set) var day: SquareViewModel.Day?
    
    private let weekday = UILabel()
    private let number = UILabel()
    private let egg = EggView()
    private let highlight = UIView()
    
    private static let names = ["日", "一", "二", "三", "四", "五", "六"]
    private static let ink = UIColor(hex: 0x3D5A1C)
    
    init(weekdayIndex: Int) {
        super.init(frame: .zero)
        highlight.backgroundColor = UIColor.white.withAlphaComponent(0.45)
        highlight.layer.cornerCurve = .continuous
        highlight.isHidden = true
        addSubview(highlight)
        
        weekday.textAlignment = .center
        weekday.attributedText = Kai.attributed(Self.names[weekdayIndex], size: 13, color: Self.ink.withAlphaComponent(0.62))
        number.textAlignment = .center
        addSubview(weekday)
        addSubview(egg)
        addSubview(number)
        
        [weekday, number, egg, highlight].forEach {
            $0.isUserInteractionEnabled = false
        }
        weekday.snp.makeConstraints { make in
                    make.top.centerX.equalToSuperview()
                }
                egg.snp.makeConstraints { make in
                    make.top.equalTo(weekday.snp.bottom).offset(4)
                    make.centerX.equalToSuperview()
                    make.width.height.equalTo(38)
                    make.bottom.lessThanOrEqualToSuperview()
                }
                number.snp.makeConstraints { make in
                    make.center.equalTo(egg)
                }
                highlight.snp.makeConstraints { make in
                    make.center.equalTo(egg)
                    make.width.height.equalTo(egg).offset(8)
                }
    }
    
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configure(_ day: SquareViewModel.Day, isSelected: Bool) {
        self.day = day
        egg.emotion = day.egg?.emotion
        egg.isHidden = day.egg?.emotion == nil
        number.isHidden = !egg.isHidden
        
        number.attributedText = Kai.attributed("\(day.number)", size: 16, color: Self.ink.withAlphaComponent(day.isToday ? 0.95 : 0.66))
        highlight.isHidden = !isSelected
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        highlight.layer.cornerRadius = highlight.bounds.height / 2
    }
}
