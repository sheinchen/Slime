//
//  SquareViewController.swift
//  Slime
//
//  广场页:月份标题 + 周条(可下拉成月历)+ 选中那天的日记卡片堆 + 鸟巢。
//

import UIKit
import SnapKit

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
    /// 卡片、空状态、页码点三样的容器。展开月历时整块一起淡出
    private let cardArea = UIView()
    private let emptyCard = UIView()
    private let pageControl = UIPageControl()
    private let cardStack = DiaryCardStackView()
    private let nestStage = NestStageView()

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
            self.viewModel.select(day)
            self.refresh(showFirstCard: true)
        }

        // 翻周只换标题，不碰选中、不碰列表、不碰鸟巢 —— 翻周就只是「看看那周」
        weekStrip.onWeekChange = { [weak self] _ in
            self?.updateTitle()
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
        
        setupCards()
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
                    // 只重画周条和月历上的蛋，不走 refresh —— 鸟巢正在演揭晓，
                    // refresh 会重新 configure 鸟巢把它打断。
                    // 月历也要刷：展开着月历时母鸡照样按得到
                    self.weekStrip.configure(weeks: self.viewModel.weeks, jumpTo: nil)
                    self.monthGrid.configure(months: self.viewModel.months, jumpTo: nil)
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
    /// - Parameter showFirstCard: 卡片堆要不要从第一篇重新叠。**换了一天**才传 true
    ///   （进页、点周条、点月历）。数据在别处变了、删了一篇都不传 ——
    ///   切出 App 再回来会触发 `dataDidChange`，正看着第三篇被换回第一篇会很烦。
    ///   跟 `jumpTo` 同一个道理：是调用方知道的事，不是 VC 该记住的状态。
    private func refresh(jumpTo index: Int? = nil, showFirstCard: Bool = false) {
        weekStrip.configure(weeks: viewModel.weeks, jumpTo: index)
        // 月历停在哪个月不动。它展开着时数据也可能变（切出 App 再回来会补蛋）
        monthGrid.configure(months: viewModel.months, jumpTo: nil)

        updateTitle()
        // 页码数要先于卡片堆设好 —— 堆装完会马上回报「最上面是第几篇」
        pageControl.numberOfPages = viewModel.entries.count
        cardStack.configure(viewModel.entries, startOver: showFirstCard)
        emptyCard.isHidden = !viewModel.entries.isEmpty
        nestStage.configure(viewModel.selectedDay)
    }

    /// 月历盖在「周条 + 卡片」的位置上。
    /// **必须在 setupCards() 之后 addSubview** —— UIKit 里后加的 subview 在上层，
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
            // 收起之后周条要停在刚选的那天所在的周，否则高亮圈在屏幕外。
            // 这里不走 alignHiddenSide 的「标题不跳」规则：点的若是上月末那几格，
            // 周条就该去那天，标题跟着变才是对的
            self.refresh(jumpTo: self.viewModel.weekIndex(containing: day.date), showFirstCard: true)
        }

        // 翻月同翻周：只换标题
        monthGrid.onMonthChange = { [weak self] _ in
            self?.updateTitle()
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
        // 月历现在也能横滑翻月了，跟周条同一个问题、同一个解法
        monthGrid.horizontalPan.require(toFail: gridPan)
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
        monthGridHeight?.update(offset: MonthGridView.contentHeight * t)
        weekStrip.alpha = 1 - t
        cardArea.alpha = 1 - t
        // 不写满 .pi：正好 180° 时两个旋转方向等距，Core Animation 会随机挑一边
        chevron.transform = CGAffineTransform(rotationAngle: .pi * 0.999 * t)
    }

    /// 手指拖到现在，进度是多少。
    /// 从当前状态起算：收起时从 0 往下加，展开时从 1 往回减。
    private func monthProgress(for gesture: UIPanGestureRecognizer) -> CGFloat {
        let base: CGFloat = isMonthExpanded ? 1 : 0
        return min(max(base + gesture.translation(in: view).y / MonthGridView.contentHeight, 0), 1)
    }

    @objc private func handleMonthPan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            // 手指一动，藏着的那一边就开始往外冒了 —— 必须在第一帧之前对好位置
            alignHiddenSide()

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
        alignHiddenSide()
        setMonthExpanded(!isMonthExpanded)
    }

    /// 展开 / 收起之前，把**藏着的那一边**挪到跟标题对得上的位置：
    /// - 展开前（周条在显示）：月历翻到周条这一周所在的月
    /// - 收起前（月历在显示）：周条挪到月历这个月里的某一周，挑哪周见 VM 的 `weekIndex(forMonth:current:)`
    ///
    /// 两边都是从高度 0 / alpha 0 慢慢出来的，所以得在出来之前就挪好 ——
    /// 等动画完再挪，会看到它在眼皮底下跳一下。
    private func alignHiddenSide() {
        if isMonthExpanded {
            weekStrip.jump(to: viewModel.weekIndex(forMonth: monthGrid.currentIndex,
                                                   current: weekStrip.currentIndex))
        } else {
            // nil 只在最早那一周出现（它的周四落在 months 之前那个月），就近取第一页
            monthGrid.jump(to: viewModel.monthIndex(ofWeek: weekStrip.currentIndex) ?? 0)
            monthGrid.isHidden = false
        }
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
        // 标题的来源换了一边（周条 ↔ 月历）。alignHiddenSide 对好位置之后两边是同一个月，
        // 平时这句不会让标题变；只有最早那一周的边角情况会，见 alignHiddenSide
        updateTitle()

        if expanded {
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

    /// 标题跟着**正在看的那一页**走，不跟选中日走 —— 翻到八月就写「八月」，
    /// 哪怕选中的还是今天。收起时看周条停在哪周，展开时看月历翻到哪个月。
    private func updateTitle() {
        let month: String
        let year: String?
        if isMonthExpanded {
            month = viewModel.monthTitle(atMonth: monthGrid.currentIndex)
            year = viewModel.yearTitle(atMonth: monthGrid.currentIndex)
        } else {
            month = viewModel.monthTitle(atWeek: weekStrip.currentIndex)
            year = viewModel.yearTitle(atWeek: weekStrip.currentIndex)
        }

        monthLabel.attributedText = AppFont.attributed(month, size: 34,
                                                   color: Sky.ink, kern: 34 * 0.03)
        if let year {
            yearLabel.attributedText = AppFont.attributed(year, size: 15, color: Sky.ink(0.34))
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
        refresh(jumpTo: viewModel.currentWeekIndex, showFirstCard: true)
    }

    // MARK: - 卡片堆

    private func setupCards() {
        view.addSubview(cardArea)
        cardArea.snp.makeConstraints { make in
            make.top.equalTo(weekStrip.snp.bottom).offset(24)
            // 和周条、浮动 tab 条同一个 22 缩进，竖着看是对齐的
            make.leading.trailing.equalToSuperview().inset(22)
            // 底下留出页码点那一条
            make.bottom.equalTo(nestStage.snp.top).offset(-26)
        }

        // 空的那天放一张半透明的「虚卡」占住位置，版面不塌
        emptyCard.backgroundColor = UIColor.white.withAlphaComponent(0.5)
        emptyCard.layer.cornerRadius = DiaryCardView.cornerRadius
        emptyCard.layer.cornerCurve = .continuous
        emptyCard.isHidden = true
        cardArea.addSubview(emptyCard)
        emptyCard.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        let emptyLabel = UILabel()
        emptyLabel.attributedText = AppFont.attributed("这天巢是空的", size: 16, color: Sky.ink(0.3))
        emptyCard.addSubview(emptyLabel)
        emptyLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }

        cardArea.addSubview(cardStack)
        cardStack.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        cardStack.onTopChange = { [weak self] index in
            self?.pageControl.currentPage = index
        }
        cardStack.onDelete = { [weak self] item in
            self?.deleteItem(item)
        }

        // 页码点只是个指示，不接点击 —— 换下一篇就靠抽卡
        pageControl.hidesForSinglePage = true
        pageControl.isUserInteractionEnabled = false
        pageControl.pageIndicatorTintColor = Sky.ink(0.14)
        pageControl.currentPageIndicatorTintColor = Sky.ink(0.45)
        cardArea.addSubview(pageControl)
        pageControl.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            // 落在卡片堆和鸟巢之间那条缝里
            make.centerY.equalTo(cardArea.snp.bottom).offset(13)
        }
    }

    /// 删除:VM 删数据,再整体 refresh —— 不只是卡片,周条上那天的圆点、
    /// 鸟巢的状态也可能跟着变(删光了那天就没记录了)
    ///
    /// 刷两次:删完立刻刷一次(过去的天变成没表情的绿壳,今天变回母鸡),
    /// 过去那天的蛋重孵回来再刷一次(绿壳就地揭晓成新蛋,动画由 NestStageView 自己认出来演)。
    private func deleteItem(_ item: SlimeItem) {
        viewModel.delete(item)
        refresh()
        Task {
            if await viewModel.rehatchAfterDelete(item) { refresh() }
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

