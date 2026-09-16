//
//  WeekStripView.swift
//  Slime
//
//  Created by shiying on 2026/8/24.
//

import Foundation
import SnapKit
import UIKit

/// 周条。整条是一个**横向分页的 UICollectionView**，一页 = 一周 7 格。
///
/// 为什么不是自己拿 UIPanGestureRecognizer 手搓：
/// 分页、回弹、惯性、cell 复用 collectionView 全带好了，
/// 而且「翻不到未来」直接由数据到本周为止实现，一行边界判断都不用写。
final class WeekStripView: UIView {

    /// 点某一天
    var onSelect: ((SquareViewModel.Day) -> Void)?
    /// 翻到第几周（下标对应 SquareViewModel.weeks）。只在真的换页时回调一次。
    var onWeekChange: ((Int) -> Void)?

    private(set) var currentIndex = 0

    /// 内部那个横向分页 scrollView 的拖动手势。
    /// 外面要让自己的竖向手势和它互斥时用（见 SquareViewController 的下拉展开）。
    var horizontalPan: UIPanGestureRecognizer {
        collectionView.panGestureRecognizer
    }

    nonisolated private enum Section {
        case main
    }

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, SquareViewModel.Week>!

    /// 待跳转的页。第一次布局拿到宽度时才能真的跳，所以先记下来。
    private var pendingJump: Int?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Palette.grassSide
        layer.cornerRadius = 22
        layer.cornerCurve = .continuous
        clipsToBounds = true

        setupCollectionView()
        setupDataSource()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - 对外

    /// - Parameter jumpTo: 要停在第几页。传 nil = 保持用户当前翻到的位置不动
    ///   （刷新数据时绝不能把用户从他翻到的那周拽回来）。
    func configure(weeks: [SquareViewModel.Week], jumpTo index: Int?) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, SquareViewModel.Week>()
        snapshot.appendSections([.main])
        snapshot.appendItems(weeks, toSection: .main)
        dataSource.apply(snapshot, animatingDifferences: false)

        if let index {
            pendingJump = index
            jumpIfPossible()
        }
    }

    // MARK: - 搭建

    private func setupCollectionView() {
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
        collectionView.backgroundColor = .clear
        collectionView.isPagingEnabled = true
        collectionView.showsHorizontalScrollIndicator = false
        // 关键：到边界自己回弹，别把手势漏给外层那个 RootPager 的分页 scrollView，
        // 否则在周条上往右滑到头会直接跳回首页。
        collectionView.alwaysBounceHorizontal = true
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.delegate = self
        addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    /// 一页占满整个可视区：item 和 group 都是 fractional 1.0，
    /// 再把 configuration 的滚动方向改成横向。
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
        // 提前把「往上转发」这件事包成一个只捕获一次 weak self 的闭包。
        // dataSource 由 self 持有，registration 闭包又被 dataSource 持有 ——
        // 这里直接写 self 就是循环引用，页面永远不释放。
        let forward: (SquareViewModel.Day) -> Void = { [weak self] day in
            self?.onSelect?(day)
        }

        let registration = UICollectionView.CellRegistration<WeekPageCell, SquareViewModel.Week> { cell, _, week in
            cell.configure(week)
            cell.onSelect = forward
        }

        dataSource = UICollectionViewDiffableDataSource<Section, SquareViewModel.Week>(
            collectionView: collectionView
        ) { collectionView, indexPath, week in
            collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: week)
        }
    }

    // MARK: - 定位

    override func layoutSubviews() {
        super.layoutSubviews()
        // 第一次进来时 configure 那会儿 bounds 还是 0，跳不了，留到这里补上
        jumpIfPossible()
    }

    private func jumpIfPossible() {
        guard let index = pendingJump, bounds.width > 0 else { return }
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

extension WeekStripView: UICollectionViewDelegate {

    /// 用 didScroll 而不是 didEndDecelerating：月份标题在拖到一半时就翻，跟手。
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let width = scrollView.bounds.width
        let count = collectionView.numberOfItems(inSection: 0)
        guard width > 0, count > 0 else { return }

        let raw = Int((scrollView.contentOffset.x / width).rounded())
        let index = min(max(raw, 0), count - 1)
        guard index != currentIndex else { return }

        currentIndex = index
        onWeekChange?(index)
    }
}

// MARK: - 一页 = 一周七格

private final class WeekPageCell: UICollectionViewCell {

    var onSelect: ((SquareViewModel.Day) -> Void)? {
        get {
            rowView.onSelect
        }
        set {
            rowView.onSelect = newValue
        }
    }
    
    private let rowView = WeekRowView(style: .strip)

    override init(frame: CGRect) {
        super.init(frame: frame)
        
        contentView.addSubview(rowView)
        rowView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 12, left: 6, bottom: 12, right: 6))
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ week: SquareViewModel.Week) {
        rowView.configure(week)
    }

}


