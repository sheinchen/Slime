//
//  SquareViewController.swift
//  Slime
//
//  史莱姆广场:用现代 UICollectionView 把存下来的帖子渲染成一格格史莱姆占位方块。
//  两个核心概念:Compositional Layout(排版)+ Diffable Data Source(数据驱动)。
//

import UIKit
import SnapKit

// Diffable 需要"分区"的类型。我们只有一个区,用枚举表示。


final class SquareViewController: UIViewController {

    // 广场的逻辑层,负责读数据、转成 SlimeItem
    private let viewModel: SquareViewModel

    init(viewModel: SquareViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private let detailView = DiaryDetailView()

    nonisolated private enum Section {
        case main
    }

    private let sky = SkyView()
    private let weekStrip = WeekStripView()
    private let monthLabel = UILabel()
    private let card = UIView()
    private let cardShadow = UIView()
    private let emptyLabel = UILabel()
    private var collectionView: UICollectionView!
    private let nestStage = NestStageView()

    // Diffable Data Source:泛型是 <分区类型, item 类型>。
    // 它取代了老的 dataSource 代理(numberOfItems / cellForItem),改成"给它数据快照,它自己算差异刷新"。
    private var dataSource: UICollectionViewDiffableDataSource<Section, SlimeItem>!

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        sky.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sky)
        //view.backgroundColor = UIColor(hex: 0xFCFAF4)
        // card.backgroundColor = UIColor(hex: 0xFCFAF4)
        view.addSubview(monthLabel)
        view.addSubview(weekStrip)
        view.addSubview(nestStage)
        
        monthLabel.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(20)
            make.leading.equalToSuperview().offset(28)
        }
        weekStrip.snp.makeConstraints { make in
            make.top.equalTo(monthLabel.snp.bottom).offset(26)
            make.leading.trailing.equalToSuperview().inset(22)
            make.height.equalTo(88)
        }

        weekStrip.onSelect = { [weak self] day in
            guard let self else { return }
            self.showList()
            self.viewModel.select(day)
            self.refresh()
        }
        nestStage.snp.makeConstraints { make in
        make.leading.trailing.equalToSuperview()
        make.bottom.equalTo(view.safeAreaLayoutGuide).offset(-8)
        make.height.equalTo(236)
        }
        
        NSLayoutConstraint.activate([
            sky.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sky.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sky.topAnchor.constraint(equalTo: view.topAnchor),
            sky.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        
        setupCollectionView()
        setupCard()
        setupDataSource()
     
        nestStage.canLay = { [weak self] in
            self?.viewModel.canHatchToday ?? false
        }
        
        nestStage.onPressHalfway = { [weak self] in
            self?.viewModel.prefetchTodaySummary()
        }
        
        nestStage.onDidLay = { [weak self] in
            guard let self else { return }
            Task {
                do {
                    let summary = try await self.viewModel.finishTodaySummary()
                    self.nestStage.revealEgg(to: summary.emotion)
                    self.nestStage.setCaption(summary.text)
                    self.weekStrip.configure(days: self.viewModel.days, selected: self.viewModel.selectedDate)
                } catch {
                    self.refresh()
                    self.nestStage.setCaption("哎呀没有孵出来！再试一次！")
                }
            }
            
        }
    }
    
    private func refresh() {
        monthLabel.attributedText = Kai.attributed(viewModel.monthTitle, size: 34,
           color: Sky.ink, kern: 34 * 0.03)
            weekStrip.configure(days: viewModel.days, selected: viewModel.selectedDate)
        applySnapshot()
        emptyLabel.isHidden = !viewModel.entries.isEmpty
        if let day = viewModel.selectedDay {
            nestStage.configure(day)
        }
    }

    // 每次界面将要显示时重新读数据 —— 从输入页存完返回广场,能立刻看到新史莱姆
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.loadPosts()
        refresh()
        //applySnapshot()
    }

    // MARK: - 布局(Compositional Layout)
    
    private func setupCard() {
        cardShadow.backgroundColor = .clear
        cardShadow.layer.shadowColor = UIColor(hex: 0x6B5B45).cgColor
        cardShadow.layer.shadowOpacity = 0.08
        cardShadow.layer.shadowRadius = 22
        cardShadow.layer.shadowOffset = CGSize(width: 0, height: 10)
        view.addSubview(cardShadow)

        card.backgroundColor = UIColor.white
        card.layer.cornerRadius = 26
        card.layer.cornerCurve = .continuous
        card.clipsToBounds = true
        cardShadow.addSubview(card)

        emptyLabel.attributedText = Kai.attributed("这天巢是空的", size: 16, color: Sky.ink(0.3))
        emptyLabel.isHidden = true
        card.addSubview(emptyLabel)
        
        detailView.isHidden = true
        detailView.alpha = 0
        card.addSubview(detailView)
        detailView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        detailView.onBack = { [weak self] in
            self?.showList()
        }

        cardShadow.snp.makeConstraints { make in
            make.top.equalTo(weekStrip.snp.bottom).offset(24)
            make.leading.trailing.equalToSuperview().inset(22)
            // 底下先留出母鸡的位置,下一轮填
            make.bottom.equalTo(nestStage.snp.top).offset(-14)
        }
        card.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        emptyLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
    }
    
    private func setupCollectionView() {
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        card.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    
    /// iOS 14 起 Compositional Layout 内置了列表形态,分隔线、缩进、滑动操作全带好了,
    /// 不用自己拼 item → group → section。
    private func makeLayout() -> UICollectionViewLayout {
        var config = UICollectionLayoutListConfiguration(appearance: .plain)
        config.backgroundColor = .clear
        config.showsSeparators = true
        config.separatorConfiguration.color = UIColor(hex: 0xEAE4D6)
        config.separatorConfiguration.topSeparatorVisibility = .hidden
        // 分隔线两头缩进,不要顶到卡片边
        config.separatorConfiguration.bottomSeparatorInsets =
            NSDirectionalEdgeInsets(top: 0, leading: 26, bottom: 0, trailing: 26)
        return UICollectionViewCompositionalLayout.list(using: config)
    }

    // MARK: - 数据(Diffable Data Source)

    private func setupDataSource() {
        // CellRegistration:现代注册方式,不用再写字符串 reuseIdentifier,类型安全
        let registration = UICollectionView.CellRegistration<DiaryEntryCell, SlimeItem> { cell, _, item in
            cell.configure(item)
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
        snapshot.appendItems(viewModel.entries, toSection: .main)
        dataSource.apply(snapshot, animatingDifferences: false)
    }
    
    //MARK: - 列表<->原文
    private func showDetail(_ item: SlimeItem) {
        detailView.configure(item)
        detailView.alpha = 0
        detailView.isHidden = false
        detailView.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
        
        UIView.animate(withDuration: 0.28, delay: 0, options: .curveEaseOut) {
            // 列表往外放大着淡出、原文从里面长出来 —— 视觉上是"往里走了一层"
            self.collectionView.alpha = 0
            self.collectionView.transform = CGAffineTransform(scaleX: 1.04, y: 1.04)
            self.emptyLabel.alpha = 0
            self.detailView.alpha = 1
            self.detailView.transform = .identity
        } completion: { _ in
            self.collectionView.isHidden = true
            self.collectionView.transform = .identity
        }
    }
    
    private func showList() {
        collectionView.alpha = 0
            collectionView.isHidden = false
            collectionView.transform = CGAffineTransform(scaleX: 1.04, y: 1.04)

            UIView.animate(withDuration: 0.28, delay: 0, options: .curveEaseOut) {
                self.detailView.alpha = 0
                self.detailView.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
                self.collectionView.alpha = 1
                self.collectionView.transform = .identity
                self.emptyLabel.alpha = 1
            } completion: { _ in
                self.detailView.isHidden = true
            }
    }
}

// MARK: - UICollectionViewDelegate

extension SquareViewController: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        showDetail(item)
    }
    
    // 长按某个格子时,返回一个上下文菜单(iOS 会自动做放大预览 + 弹菜单)
    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return nil }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            // 一个"删除"动作:红色破坏性样式 + 垃圾桶图标
            let delete = UIAction(
                title: "删除",
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { _ in
                self?.deleteItem(item)
            }
            return UIMenu(children: [delete])
        }
    }

    // 执行删除:VM 删数据,再刷新快照让 diffable 播移除动画
    private func deleteItem(_ item: SlimeItem) {
        viewModel.delete(item)
        applySnapshot()
    }
}

//MARK: - PagerPage当前页面协议
extension SquareViewController: PagerPage {
    
    func pageVisibilityDidChange(isCurrent: Bool) {
        guard isCurrent else { return }
        viewModel.loadPosts()
        refresh()
        
   
    }
    
    func dataDidChange() {
        viewModel.loadPosts()
        refresh()
    }
}

