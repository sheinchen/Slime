//
//  SquareViewController.swift
//  Slime
//
//  史莱姆广场:用现代 UICollectionView 把存下来的帖子渲染成一格格史莱姆占位方块。
//  两个核心概念:Compositional Layout(排版)+ Diffable Data Source(数据驱动)。
//

import UIKit

// Diffable 需要"分区"的类型。我们只有一个区,用枚举表示。


final class SquareViewController: UIViewController {

    // 广场的逻辑层,负责读数据、转成 SlimeItem
    private let viewModel = SquareViewModel()

    nonisolated private enum Section {
        case main
    }

    private var collectionView: UICollectionView!

    // Diffable Data Source:泛型是 <分区类型, item 类型>。
    // 它取代了老的 dataSource 代理(numberOfItems / cellForItem),改成"给它数据快照,它自己算差异刷新"。
    private var dataSource: UICollectionViewDiffableDataSource<Section, SlimeItem>!

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "史莱姆广场"
        view.backgroundColor = .systemBackground
        setupCollectionView()
        setupDataSource()
    }

    // 每次界面将要显示时重新读数据 —— 从输入页存完返回广场,能立刻看到新史莱姆
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.loadPosts()
        applySnapshot()
    }

    // MARK: - 布局(Compositional Layout)

    private func setupCollectionView() {
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
        collectionView.backgroundColor = .clear
        collectionView.delegate = self   // 让本类接收点击事件
        view.addSubview(collectionView)
        // 这里没用 SnapKit,直接让 collectionView 铺满,顺便示范一下等价的原生写法
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    /// Compositional Layout:用"item → group → section"三层描述排版。
    /// 这里做一个每行 3 列的方格网格。
    private func makeLayout() -> UICollectionViewLayout {
        // item:占所在 group 宽度的 1/3、撑满 group 高度
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0 / 3.0),
            heightDimension: .fractionalHeight(1.0)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        item.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)

        // group:占满整行宽,高度按屏宽的 1/3(让格子接近正方形)
        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .fractionalWidth(1.0 / 3.0)
        )
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])

        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)

        return UICollectionViewCompositionalLayout(section: section)
    }

    // MARK: - 数据(Diffable Data Source)

    private func setupDataSource() {
        // CellRegistration:现代注册方式,不用再写字符串 reuseIdentifier,类型安全
        let registration = UICollectionView.CellRegistration<SlimeCell, SlimeItem> { cell, _, item in
            cell.configure(with: item)
        }

        // dataSource 负责:给它一个 item,它返回配置好的 cell
        dataSource = UICollectionViewDiffableDataSource<Section, SlimeItem>(
            collectionView: collectionView
        ) { collectionView, indexPath, item in
            collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: item)
        }
    }

    /// 快照(snapshot)= 当前该显示哪些数据。把最新的 items 塞进去,交给 dataSource,它自动算差异刷新界面。
    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, SlimeItem>()
        snapshot.appendSections([.main])
        snapshot.appendItems(viewModel.items, toSection: .main)
        dataSource.apply(snapshot, animatingDifferences: true)
    }
}

// MARK: - UICollectionViewDelegate

extension SquareViewController: UICollectionViewDelegate {

    // 点中某个格子时调用。indexPath 告诉你点的是第几个。
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        // 取消选中高亮(纯视觉)
        collectionView.deselectItem(at: indexPath, animated: true)

        // 关键:不用 indexPath 去数组里 [下标] 取数据,而是问 dataSource 要 item。
        // 这样即使数据正在变动也不会取错/越界 —— 这是 Diffable 的正确取值姿势。
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }

        // 造详情页的 ViewModel(把这条数据注入),再 push。换成 SpriteKit 场景后,
        // 变的只有"怎么知道点了哪只",下面这两行完全一样。
        let detailVM = PostDetailViewModel(item: item)
        let detailVC = PostDetailViewController(viewModel: detailVM)
        navigationController?.pushViewController(detailVC, animated: true)
    }
}
