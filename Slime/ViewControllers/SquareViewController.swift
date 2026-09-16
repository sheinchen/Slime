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
    /// 翻到不是今年的周时才露出来的小年份
    private let yearLabel = UILabel()
    /// 月份 + 小箭头整块可点 —— 光给 UILabel 加手势的话点击区域只有字那么大
    private let titleTap = UIControl()
    private let chevron = UIImageView()
    private let monthGrid = MonthGridView()
    /// 存着月历的高度约束，展开收起就是改它
    private var monthGridHeight: Constraint?
    private var isMonthExpanded = false
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
        view.addSubview(titleTap)
        titleTap.addSubview(monthLabel)
        titleTap.addSubview(chevron)
        view.addSubview(yearLabel)
        view.addSubview(weekStrip)
        view.addSubview(nestStage)

        titleTap.addTarget(self, action: #selector(titleTapped), for: .touchUpInside)
        titleTap.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(20)
            make.leading.equalToSuperview().offset(28)
        }
        // titleTap 没有自己的尺寸，由里面的 monthLabel + chevron 撑出来
        monthLabel.snp.makeConstraints { make in
            make.top.leading.bottom.equalToSuperview()
        }
        chevron.image = UIImage(systemName: "chevron.down",
                                withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
        chevron.tintColor = Sky.ink(0.4)
        chevron.snp.makeConstraints { make in
            make.leading.equalTo(monthLabel.snp.trailing).offset(8)
            make.centerY.equalTo(monthLabel)
            make.trailing.equalToSuperview()
        }
        yearLabel.isHidden = true
        yearLabel.snp.makeConstraints { make in
            // lastBaseline 对齐：34pt 的月份和 15pt 的年份坐在同一条基线上，才像一个词组
            make.lastBaseline.equalTo(monthLabel)
            make.leading.equalTo(titleTap.snp.trailing).offset(8)
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

        // 翻周只换标题，不碰选中、不碰列表、不碰鸟巢 —— 翻周就只是「看看那周」
        weekStrip.onWeekChange = { [weak self] index in
            self?.updateTitle(week: index)
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
        setupMonthGrid()
     
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
                    self.weekStrip.configure(weeks: self.viewModel.weeks, jumpTo: nil)
                } catch {
                    self.refresh()
                    self.nestStage.setCaption("哎呀没有孵出来！再试一次！")
                }
            }
            
        }
    }
    
    /// - Parameter index: 要把周条挪到第几周。传 nil = 停在哪就是哪。
    ///   「重新进这一页」传本周；「从月历选了某天」传那天所在的周；
    ///   其余调用方（点周条上某一天、数据在别处变了）一律用默认值 ——
    ///   否则你翻到上周、点上周三，周条会把自己弹回本周，那天就点不开了。
    private func refresh(jumpTo index: Int? = nil) {
        let week = index ?? weekStrip.currentIndex
        weekStrip.configure(weeks: viewModel.weeks, jumpTo: index)

        updateTitle(week: week)
        applySnapshot()
        emptyLabel.isHidden = !viewModel.entries.isEmpty
        nestStage.configure(viewModel.selectedDay)
    }
 
    /// 月历盖在「周条 + 卡片」的位置上。
    /// **必须在 setupCard() 之后 addSubview** —— UIKit 里后加的 subview 在上层，
    /// 早于卡片加进去就会被卡片盖住。
    private func setupMonthGrid() {
        monthGrid.isHidden = true
        view.addSubview(monthGrid)
        monthGrid.snp.makeConstraints { make in
            make.top.equalTo(weekStrip.snp.top)
            make.leading.trailing.equalTo(weekStrip)
            monthGridHeight = make.height.equalTo(0).constraint
        }

        monthGrid.onSelect = { [weak self] day in
            guard let self else { return }
            self.viewModel.select(day)
            self.setMonthExpanded(false)
            self.showList()
            // 收起之后周条要停在刚选的那天所在的周，否则高亮圈在屏幕外
            self.refresh(jumpTo: self.viewModel.weekIndex(containing: day.date))
        }

        // 两处都要能拖：收起时在周条上往下拉，展开时在月历上往上推。
        // 不能只加在周条上 —— 展开后周条 alpha 归 0，
        // 而 UIKit 的 hitTest 会跳过 alpha ≤ 0.01 的 view，它根本收不到手势。
        let stripPan = makeMonthPan()
        weekStrip.addGestureRecognizer(stripPan)
        // 竖着拉月历时，周条不许跟着横滑。
        // 做法不是「两个手势共存」，而是让周条的横向滚动**等这个手势先判定**：
        //   横拖 → shouldBegin 返回 false（= 手势失败）→ 周条立刻接管，照常翻周
        //   竖拖 → 这个手势进入 began → 周条永远不会开始，一点都不动
        weekStrip.horizontalPan.require(toFail: stripPan)

        let gridPan = makeMonthPan()
        monthGrid.addGestureRecognizer(gridPan)
    }

    private func makeMonthPan() -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleMonthPan))
        pan.delegate = self
        return pan
    }

    // MARK: - 下拉展开

    /// 把展开进度施加到三样东西上。t = 0 收起、1 完全展开，中间连续。
    ///
    /// 抽出来是因为**拖动和松手回弹用的是同一套**：拖动时每帧调一次，
    /// 回弹时在动画块里调一次目标值。两边各写一份迟早会漂。
    private func applyMonthProgress(_ t: CGFloat) {
        monthGridHeight?.update(offset: monthGrid.contentHeight * t)
        weekStrip.alpha = 1 - t
        cardShadow.alpha = 1 - t
        // 不写满 .pi：正好 180° 时两个旋转方向等距，Core Animation 会随机挑一边
        chevron.transform = CGAffineTransform(rotationAngle: .pi * 0.999 * t)
    }

    /// 手指拖到现在，进度是多少。
    /// 从当前状态起算：收起时从 0 往下加，展开时从 1 往回减。
    private func monthProgress(for gesture: UIPanGestureRecognizer) -> CGFloat {
        let full = monthGrid.contentHeight
        guard full > 0 else { return isMonthExpanded ? 1 : 0 }
        let base: CGFloat = isMonthExpanded ? 1 : 0
        return min(max(base + gesture.translation(in: view).y / full, 0), 1)
    }

    @objc private func handleMonthPan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            // 拖之前先把这个月备好 —— contentHeight 是按行数算的，
            // 没 configure 就没有高度，除不动
            if !isMonthExpanded {
                monthGrid.configure(weeks: viewModel.weeksInMonth(ofWeek: weekStrip.currentIndex))
                monthGrid.isHidden = false
            }

        case .changed:
            applyMonthProgress(monthProgress(for: gesture))
            view.layoutIfNeeded()

        case .ended, .cancelled:
            // 甩得够快就按方向走，慢慢拖就看过没过半 —— 这是 snap 的标准判法
            let velocity = gesture.velocity(in: view).y
            let expand = abs(velocity) > 300 ? velocity > 0 : monthProgress(for: gesture) > 0.5
            setMonthExpanded(expand)

        default:
            break
        }
    }

    @objc private func titleTapped() {
        setMonthExpanded(!isMonthExpanded)
    }

    /// 展开 / 收起月历。
    ///
    /// 动画的做法：先把目标高度写进约束，再在动画块里 `layoutIfNeeded()` ——
    /// Auto Layout 的约束变化本身不是动画，是这句「重新布局」在动画块里执行才产生了过渡。
    /// 这是约束动画的固定套路，改 frame 那一套在这儿不适用。
    ///
    /// - Parameter animated: `viewWillAppear` 里重置时传 false，不然进页面会看到月历闪一下
    private func setMonthExpanded(_ expanded: Bool, animated: Bool = true) {
        isMonthExpanded = expanded

        if expanded {
            // 显示周条当前停的那一周所属的月份。
            // 必须在量高度之前 configure —— contentHeight 是按行数算的，
            // 5 周的月份和 6 周的月份不一样高
            monthGrid.configure(weeks: viewModel.weeksInMonth(ofWeek: weekStrip.currentIndex))
            // 展开要先露出来再长高；收起则相反，等动画完了再藏
            monthGrid.isHidden = false
        }

        let apply = {
            self.applyMonthProgress(expanded ? 1 : 0)
            self.view.layoutIfNeeded()
        }

        guard animated else {
            apply()
            monthGrid.isHidden = !expanded
            return
        }

        UIView.animate(withDuration: 0.36, delay: 0,
                       usingSpringWithDamping: 0.88, initialSpringVelocity: 0,
                       options: .curveEaseOut) {
            apply()
        } completion: { _ in
            self.monthGrid.isHidden = !expanded
        }
    }

    /// 标题跟着**翻到哪一周**走，不跟选中日走 —— 翻到八月就写「八月」，
    /// 哪怕选中的还是今天。
    private func updateTitle(week index: Int) {
        monthLabel.attributedText = Kai.attributed(viewModel.monthTitle(atWeek: index), size: 34,
                                                   color: Sky.ink, kern: 34 * 0.03)
        if let year = viewModel.yearTitle(atWeek: index) {
            yearLabel.attributedText = Kai.attributed(year, size: 15, color: Sky.ink(0.34))
            yearLabel.isHidden = false
        } else {
            yearLabel.isHidden = true
        }
    }

    /// 每次进这一页都当成「重新打开」：回到今天、周条回到本周、重读数据。
    ///
    /// 选中日和周条位置都是会留存的状态（VM 是组合根建的单例），不重置的话
    /// 上次翻到八月、选中十六号的样子会一直挂着 ——
    /// 写完日记切回来看到的是那天的空列表，像是没存上。
    ///
    /// 这是**唯一**把周条挪回本周的地方。
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.resetToToday()
        setMonthExpanded(false, animated: false)
        viewModel.loadPosts()
        refresh(jumpTo: viewModel.currentWeekIndex)
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

// MARK: - UIGestureRecognizerDelegate

extension SquareViewController: UIGestureRecognizerDelegate {

    /// 只接竖着的拖动，而且方向要对：收起时只认往下拉，展开时只认往上推。
    /// 横着拖一律放行给周条自己去翻周 —— 周条内部是个横向分页的 collectionView，
    /// 这个判断就是两者的分工线。
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: view)
        guard abs(velocity.y) > abs(velocity.x) else { return false }
        return isMonthExpanded ? velocity.y < 0 : velocity.y > 0
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

//MARK: - RootPage当前页面协议
extension SquareViewController: RootPage {
    
    func pageVisibilityDidChange(isCurrent: Bool) {
        // 空的：pager 时代切页不走 viewWillAppear，所以要靠这个回调刷新；
        // 换成 UITabBarController 之后切页会正常走 viewWillAppear，那边已经做全了。
        // 在这儿再刷一次只是白跑一遍 fetchAll。
    }
    
    func dataDidChange() {
        viewModel.loadPosts()
        refresh()
    }
}

