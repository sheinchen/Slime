//
//  FloatingTabBar.swift
//  Slime
//
//  底部那条浮动的 tab：左边一颗胶囊装主 tab，右边一个独立的圆。
//  图标现在用 SF Symbols 占位 —— 换成自己的 icon 时只要换构造参数里那几个名字，
//  或者把 UIImage(systemName:) 换成 UIImage(named:)，别的都不用动。
//

import UIKit
import SnapKit

final class FloatingTabBar: UIView {

    /// 条本身的高度（胶囊高 = 圆的直径 = 这个值）
    static let height: CGFloat = 56
    /// 条底离安全区底部的距离
    static let bottomInset: CGFloat = 10

    /// 点左边胶囊里的第几个
    var onSelect: ((Int) -> Void)?
    /// 点右边那个圆。它**不是 tab**，是个动作入口，所以单独一个回调
    var onAccessoryTap: (() -> Void)?

    private(set) var selectedIndex = 0

    private let capsule = UIView()
    private let row = UIStackView()
    private var buttons: [UIButton] = []
    private let accessory = UIButton(type: .custom)

    private static let iconConfig = UIImage.SymbolConfiguration(pointSize: 21, weight: .semibold)
    /// 每个 tab 的点击热区宽度。胶囊的宽度由它 × 个数撑出来，不写死
    private static let itemWidth: CGFloat = 74

    init(icons: [String], accessoryIcon: String) {
        super.init(frame: .zero)

        style(capsule)
        addSubview(capsule)

        row.axis = .horizontal
        row.distribution = .fillEqually
        capsule.addSubview(row)
        row.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        for (index, name) in icons.enumerated() {
            let button = UIButton(type: .custom)
            button.setImage(UIImage(systemName: name, withConfiguration: Self.iconConfig), for: .normal)
            button.tag = index
            button.addTarget(self, action: #selector(itemTapped), for: .touchUpInside)
            button.snp.makeConstraints { make in
                make.width.equalTo(Self.itemWidth)
            }
            row.addArrangedSubview(button)
            buttons.append(button)
        }

        // 选中态的配色只有 select() 一个出口，别在这儿再写一份
        select(0)

        style(accessory)
        accessory.setImage(UIImage(systemName: accessoryIcon, withConfiguration: Self.iconConfig), for: .normal)
        accessory.tintColor = Sky.ink(0.55)
        accessory.addTarget(self, action: #selector(accessoryTapped), for: .touchUpInside)
        addSubview(accessory)

        capsule.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
            make.height.equalTo(Self.height)
        }
        accessory.snp.makeConstraints { make in
            // 胶囊贴左、圆贴右，中间由外层宽度自然拉开。
            // 这里用 greaterThanOrEqualTo 只是兜底：万一 tab 多到快顶上圆了，
            // 至少还剩 14pt，不会叠在一起。
            make.leading.greaterThanOrEqualTo(capsule.snp.trailing).offset(14)
            make.trailing.top.bottom.equalToSuperview()
            make.width.height.equalTo(Self.height)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - 对外

    /// 只改外观，不回调 —— 给「代码切页」用（比如启动时选中第 0 个）
    func select(_ index: Int) {
        guard buttons.indices.contains(index) else { return }
        selectedIndex = index
        for (i, button) in buttons.enumerated() {
            button.tintColor = i == index ? Sky.ink : Sky.ink(0.3)
        }
    }

    // MARK: - 交互

    @objc private func itemTapped(_ sender: UIButton) {
        let index = sender.tag
        bounce(sender)
        guard index != selectedIndex else { return }
        select(index)
        onSelect?(index)
    }

    @objc private func accessoryTapped() {
        bounce(accessory)
        onAccessoryTap?()
    }

    /// 按下去回弹一下。transform 不影响 Auto Layout 的约束，所以随便缩
    private func bounce(_ view: UIView) {
        view.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
        UIView.animate(withDuration: 0.34, delay: 0,
                       usingSpringWithDamping: 0.5, initialSpringVelocity: 0.6) {
            view.transform = .identity
        }
    }

    // MARK: - 外观

    /// 圆角 + 阴影同时设在一个 view 上是可以的 —— 前提是不 clipsToBounds，
    /// 一 clip 阴影就被自己裁掉了。这里内容不会超出，不需要裁。
    private func style(_ view: UIView) {
        view.backgroundColor = .white
        view.layer.cornerRadius = Self.height / 2
        view.layer.cornerCurve = .continuous
        view.layer.shadowColor = UIColor(hex: 0x6B5B45).cgColor
        view.layer.shadowOpacity = 0.10
        view.layer.shadowRadius = 16
        view.layer.shadowOffset = CGSize(width: 0, height: 6)
    }
}
