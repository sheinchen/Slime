//
//  MonthGridView.swift
//  Slime
//
//  月历：一行固定的表头「日一二…六」+ 下面一个**横向分页的 UICollectionView**，
//  一页 = 一个月（固定 6 行）。一个月的蛋摆在一起，就是这个月的情绪地图。
//
//  跟 WeekStripView 是同一个套路：周条横滑翻周，月历横滑翻月。
//  「翻不到未来」也一样由数据到本月为止实现，这里一行边界判断都不用写。
//
//  它只管画和翻页，不管展开收起 —— 高度由外面的约束控制，
//  所以收起到 0 的时候内容要被裁掉（clipsToBounds）。
//

import UIKit
import SnapKit

final class MonthGridView: UIView {

    /// 点某一天
    var onSelect: ((SquareViewModel.Day) -> Void)?
    /// 翻到第几个月（下标对应 SquareViewModel.months）。只在真的换页时回调一次。
    var onMonthChange: ((Int) -> Void)?

    private(set) var currentIndex = 0

    /// 内部那个横向分页 scrollView 的拖动手势。
    /// 外面要让自己的竖向手势和它互斥时用（见 SquareViewController 的下拉展开）。
    var horizontalPan: UIPanGestureRecognizer {
        collectionView.panGestureRecognizer
    }

    fileprivate static let rows = 6
    fileprivate static let rowHeight: CGFloat = 50
    fileprivate static let spacing: CGFloat = 4
    private static let headerHeight: CGFloat = 16
    /// 表头和第一行之间单独留的间距。和行距一样宽的话，
    /// 「日一二…」会和第一行日期粘成一坨
    private static let headerGap: CGFloat = 10
    private static let padding: CGFloat = 10
    private static let names = ["日", "一", "二", "三", "四", "五", "六"]

    /// 一页（6 行 + 5 个行间隔）的高度
    private static let pageHeight = CGFloat(rows) * rowHeight + CGFloat(rows - 1) * spacing

    /// 展开后的高度，外面拿它当展开动画的目标。
    ///
    /// 每页都是 6 行，所以是个常量。以前按月份算（跨 5 周和跨 6 周不一样高），
    /// 能翻页之后就不行了：翻到一半两个月同时在屏幕上，高度说不清该听谁的。
    static let contentHeight = padding + headerHeight + headerGap + pageHeight + padding

    nonisolated private enum Section {
        case main
    }

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, SquareViewModel.Month>!

    /// 待跳转的页。第一次布局拿到宽度时才能真的跳，所以先记下来。
    private var pendingJump: Int?

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = Palette.grassSide
        layer.cornerRadius = 22
        layer.cornerCurve = .continuous
        // 高度被压到 0 时，内容要跟着被裁掉，不然会溢出到卡片上
        clipsToBounds = true

        // 表头放在列表外面、不跟着翻页 —— 换了月份，星期几的排法不会变
        let header = makeHeader()
        addSubview(header)
        header.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(Self.padding)
            make.leading.trailing.equalToSuperview().inset(6)
            make.height.equalTo(Self.headerHeight)
        }

        setupCollectionView()
        setupDataSource()
        // 只钉 top + 固定高度，不钉 bottom —— 整个月历的高度归外面的约束管。
        // 钉了 bottom，展开收起时列表会跟着被压扁，每一帧都要重排一遍
        collectionView.snp.makeConstraints { make in
            make.top.equalTo(header.snp.bottom).offset(Self.headerGap)
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(Self.pageHeight)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - 对外

    /// - Parameter jumpTo: 要停在第几页。传 nil = 保持用户当前翻到的位置不动。
    func configure(months: [SquareViewModel.Month], jumpTo index: Int?) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, SquareViewModel.Month>()
        snapshot.appendSections([.main])
        snapshot.appendItems(months, toSection: .main)
        dataSource.apply(snapshot, animatingDifferences: false)

        if let index {
            jump(to: index)
        }
    }

    /// 只挪位置、不换数据。展开前用 —— 月历要在露出来之前就翻到对的那个月。
    func jump(to index: Int) {
        pendingJump = index
        jumpIfPossible()
    }

    // MARK: - 搭建

    private func setupCollectionView() {
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
        collectionView.backgroundColor = .clear
        collectionView.isPagingEnabled = true
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.alwaysBounceHorizontal = true
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.delegate = self
        addSubview(collectionView)
    }

    /// 一页占满整个可视区，横向滚动 —— 和周条的 layout 一模一样
    private func makeLayout() -> UICollectionViewLayout {
        let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1),
                                          heightDimension: .fractionalHeight(1))
        let item = NSCollectionLayoutItem(layoutSize: size)
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: size, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)

        let config = UICollectionViewCompositionalLayoutConfiguration()
        config.scrollDirection = .horizontal
        return UICollectionViewCompositionalLayout(section: section, configuration: config)
    }

    private func setupDataSource() {
        // 同 WeekStripView：先包一个只捕获 weak self 的闭包，
        // 避免 dataSource → registration 闭包 → self 的循环引用
        let forward: (SquareViewModel.Day) -> Void = { [weak self] day in
            self?.onSelect?(day)
        }

        let registration = UICollectionView.CellRegistration<MonthPageCell, SquareViewModel.Month> { cell, _, month in
            cell.configure(month)
            cell.onSelect = forward
        }

        dataSource = UICollectionViewDiffableDataSource<Section, SquareViewModel.Month>(
            collectionView: collectionView
        ) { collectionView, indexPath, month in
            collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: month)
        }
    }

    // MARK: - 表头

    /// 「日一二三四五六」只在最上面出现一行 ——
    /// 所以下面的 WeekRowView 都是 .month 样式，不带星期名
    private func makeHeader() -> UIView {
        let header = UIStackView()
        header.axis = .horizontal
        header.distribution = .fillEqually
        for name in Self.names {
            let label = UILabel()
            label.textAlignment = .center
            label.attributedText = AppFont.attributed(name, size: 13,
                                                  color: Palette.grassInk.withAlphaComponent(0.62))
            header.addArrangedSubview(label)
        }
        return header
    }

    // MARK: - 定位

    override func layoutSubviews() {
        super.layoutSubviews()
        // 第一次 jump 时 bounds 可能还是 0，跳不了，留到这里补上
        jumpIfPossible()
    }

    private func jumpIfPossible() {
        guard let index = pendingJump, collectionView.bounds.width > 0 else { return }
        // apply 之后 contentSize 未必算好了，先逼它算一次，否则 offset 会被 clamp 回 0
        collectionView.layoutIfNeeded()
        guard collectionView.numberOfItems(inSection: 0) > index else { return }

        pendingJump = nil
        let width = collectionView.bounds.width
        collectionView.setContentOffset(CGPoint(x: CGFloat(index) * width, y: 0), animated: false)
        currentIndex = index
    }
}

// MARK: - UIScrollViewDelegate

extension MonthGridView: UICollectionViewDelegate {

    /// 用 didScroll 而不是 didEndDecelerating：标题在拖到一半时就翻，跟手 —— 同周条
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let width = scrollView.bounds.width
        let count = collectionView.numberOfItems(inSection: 0)
        guard width > 0, count > 0 else { return }

        let raw = Int((scrollView.contentOffset.x / width).rounded())
        let index = min(max(raw, 0), count - 1)
        guard index != currentIndex else { return }

        currentIndex = index
        onMonthChange?(index)
    }
}

// MARK: - 一页 = 一个月六行

private final class MonthPageCell: UICollectionViewCell {

    var onSelect: ((SquareViewModel.Day) -> Void)?

    /// 六行一开始就建好。每页都是固定 6 周，不存在「这个月少一行要藏起来」
    private var rows: [WeekRowView] = []

    override init(frame: CGRect) {
        super.init(frame: frame)

        let column = UIStackView()
        column.axis = .vertical
        column.spacing = MonthGridView.spacing
        contentView.addSubview(column)
        column.snp.makeConstraints { make in
            // 左右 6 跟表头一样 —— 每一列日期正好落在「日一二…」正下方
            make.top.equalToSuperview()
            make.leading.trailing.equalToSuperview().inset(6)
        }

        for _ in 0..<MonthGridView.rows {
            let row = WeekRowView(style: .month)
            row.onSelect = { [weak self] day in
                self?.onSelect?(day)
            }
            row.snp.makeConstraints { make in
                make.height.equalTo(MonthGridView.rowHeight)
            }
            column.addArrangedSubview(row)
            rows.append(row)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ month: SquareViewModel.Month) {
        for (row, week) in zip(rows, month.weeks) {
            row.configure(week)
        }
    }
}
