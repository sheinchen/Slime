//
//  CareDebugViewController.swift
//  Slime
//
//  主动关照 v2 第 9 步「可观测」。**整个文件只在 Debug 构建里存在。**
//

#if DEBUG
import UIKit
import SnapKit

/// 关怀系统的 debug 页 —— 把 `CareCheck` 和 `CareMessage` 摊开给人看。
///
/// 它取代的是 `SceneDelegate` 里那段临时 print:print 只看得到**最近一次**，
/// 而且命令行跑的时候还会丢。真正要回答的问题都是**跨多次**的:
/// 闸门拦下了多少、AI 调了几次、关怀多久换一次。
///
/// ## 顶上那几个数字是干什么的
///
/// 不是为了好看。CLAUDE.md 里「把『换内容』和『重新开口』拆开」那个候选方案，
/// **前提是「AI 确实经常想换」—— 而那个前提只在人工构造的 eval 边界用例上测过。**
/// 真实使用里平淡的一天可能压根不触发替换。这一页就是去拿真实数字的:
///
/// · **替换间隔** —— 换得有多勤
/// · **「引用全是旧日子」占比** —— 这些是本来就该静默更新、不该重新演出的那些
///
/// 第二个数字很小 → 那个方案不值得做;占一半以上 → 它是当下最划算的改动。
/// **先看数字再改设计,别拿边界用例上的表现当真实分布。**
///
/// 入口:Debug 构建下**长按首页的日期**。不加任何可见的 UI，用户碰不到。
final class CareDebugViewController: UIViewController {

    // MARK: - 数据

    /// 直接 new 仓库,不走组合根注入。
    ///
    /// 平时这么做是偷懒,但这一页不一样:它是个**开发工具**,不在产品路径上,
    /// 为它给 SceneDelegate 加一条注入链,等于让正式代码替 debug 页背结构。
    /// 两个仓库的默认 init 都指向 `CoreDataStack.shared`,拿到的就是真库。
    private let messages: CareMessageStore = CoreDataCareMessageStore()
    private let checks: CareCheckStore = CoreDataCareCheckStore()

    private enum Section: Int, CaseIterable {
        case stats, messages, checks
        var title: String {
            switch self {
            case .stats:    return "统计"
            case .messages: return "关怀（新→旧）"
            case .checks:   return "检查日志（新→旧）"
            }
        }
    }

    /// `n` 是行号,**只为了让 diffable 的 item 唯一** ——
    /// 两行文字完全一样时(比如两次同样的闸门原因),没有它快照会崩。
    nonisolated struct Row: Hashable {
        let n: Int
        let title: String
        let detail: String
    }

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Row>!

    // MARK: -

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "关怀 debug"
        view.backgroundColor = .systemGroupedBackground

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .close, primaryAction: UIAction { [weak self] _ in
                self?.dismiss(animated: true)
            })

        setupCollectionView()
        applySnapshot()
    }

    private func setupCollectionView() {
        // 列表用现代写法:Compositional 的 list 配置 + list cell,
        // 不走老的 UITableView + cellForRowAt(工程约定)。
        var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        config.headerMode = .supplementary
        let layout = UICollectionViewCompositionalLayout.list(using: config)

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { $0.edges.equalToSuperview() }

        let cell = UICollectionView.CellRegistration<UICollectionViewListCell, Row> { cell, _, row in
            var c = cell.defaultContentConfiguration()
            c.text = row.title
            c.secondaryText = row.detail
            c.textProperties.font = .systemFont(ofSize: 14, weight: .medium)
            // 等宽:JSON 和时间戳对齐了才扫得动
            c.secondaryTextProperties.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            c.secondaryTextProperties.numberOfLines = 0
            c.secondaryTextProperties.color = .secondaryLabel
            cell.contentConfiguration = c
        }

        let header = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] view, _, indexPath in
            var c = view.defaultContentConfiguration()
            c.text = self?.dataSource.sectionIdentifier(for: indexPath.section)?.title
            view.contentConfiguration = c
        }

        dataSource = UICollectionViewDiffableDataSource<Section, Row>(collectionView: collectionView) {
            cv, indexPath, row in
            cv.dequeueConfiguredReusableCell(using: cell, for: indexPath, item: row)
        }
        dataSource.supplementaryViewProvider = { cv, _, indexPath in
            cv.dequeueConfiguredReusableSupplementary(using: header, for: indexPath)
        }
    }

    private func applySnapshot() {
        let cares = messages.allForDebug(limit: 60)
        let logs = checks.recent(limit: 60)

        var n = 0
        func row(_ title: String, _ detail: String) -> Row {
            n += 1
            return Row(n: n, title: title, detail: detail)
        }

        var snapshot = NSDiffableDataSourceSnapshot<Section, Row>()
        snapshot.appendSections(Section.allCases)

        snapshot.appendItems(CareDebugStats.lines(cares: cares, checks: logs).map { row($0.0, $0.1) },
                             toSection: .stats)

        snapshot.appendItems(cares.map { c in
            let seen = c.firstSeenAt.map { "看到 \(Self.time.string(from: $0))" } ?? "还没被看到"
            let retired = c.retiredAt.map { "退场 \(Self.time.string(from: $0))" } ?? "还挂着"
            let about = c.referencedDates.map { Self.day.string(from: $0) }.joined(separator: " ")
            return row(c.text,
                       "\(c.status) · 生成 \(Self.time.string(from: c.createdAt)) · \(seen) · \(retired)\n针对 \(about.isEmpty ? "—" : about)")
        }, toSection: .messages)

        snapshot.appendItems(logs.map { c in
            let gate = c.gatePassed ? "闸门过" : "闸门挡：\(c.gateReason ?? "?")"
            let ai = c.aiCalled ? "调AI \(c.latencyMs)ms" : "没调AI"
            let shown = c.finalShown ? "说了" : "没说\(c.dropReason.map { "：\($0)" } ?? "")"
            return row(Self.time.string(from: c.checkedAt),
                       "\(gate) · \(ai) · \(shown)\n\(c.aiRaw ?? "—")")
        }, toSection: .checks)

        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private static let time: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MM-dd HH:mm"; return f
    }()
    private static let day: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MM-dd"; return f
    }()
}

// MARK: - 统计（纯函数，好测）

/// 从关怀和检查日志里派生出几个数字。
/// **全是算术** —— 数个数、比时刻、比日期，一点情绪判断都没有。
nonisolated enum CareDebugStats {

    /// 一次「替换」= 旧的退场时刻和新的诞生时刻是同一刻。
    ///
    /// 依据是 `CoreDataCareMessageStore.show()`:它先把挂着的那条退场在 `now`、
    /// 再用同一个 `now` 建新的。所以两个时刻相等 = 那次是替换;
    /// 旧的退场明显早于新的诞生 = 中间有过空窗(挂满 3 天自然退场 + 冷却),
    /// 那是**重新开口**,不是替换。两者对用户的意义完全不同,不能混在一起数。
    static func isReplacement(prev: CareMessageDebugRow, next: CareMessageDebugRow) -> Bool {
        guard let retired = prev.retiredAt else { return false }
        return abs(retired.timeIntervalSince(next.createdAt)) < 1
    }

    /// 这次替换引用的日期，是不是**全都在上一条关怀说出口那天或更早**。
    ///
    /// 全是旧日子 = 它在用新措辞复述已经回应过的内容 → 按 CLAUDE.md 那个候选方案，
    /// 这种就该静默更新、不该重新滑出来惊动人。**这一栏的占比决定那个方案值不值得做。**
    ///
    /// 只比日期不比时刻 —— 「跨天看日期」和 `PastCare.isNewEvidence` 是同一个口径;
    /// 当天那条分支要蛋的孵出时刻，这里拿不到，而替换基本都是跨天的，差别可以忽略。
    static func onlyOldDays(prev: CareMessageDebugRow, next: CareMessageDebugRow,
                            calendar: Calendar = .current) -> Bool {
        let prevDay = calendar.startOfDay(for: prev.createdAt)
        return !next.referencedDates.contains { calendar.startOfDay(for: $0) > prevDay }
    }

    static func lines(cares: [CareMessageDebugRow],
                      checks: [CareCheckRecord],
                      calendar: Calendar = .current) -> [(String, String)] {
        // cares 是新→旧，所以 i 是新的、i+1 是它的上一条
        var replacements: [(prev: CareMessageDebugRow, next: CareMessageDebugRow)] = []
        var reopens = 0
        for i in 0..<max(0, cares.count - 1) {
            let next = cares[i], prev = cares[i + 1]
            if isReplacement(prev: prev, next: next) { replacements.append((prev, next)) }
            else if prev.retiredAt != nil { reopens += 1 }
        }

        let gaps = replacements.map { $0.next.createdAt.timeIntervalSince($0.prev.createdAt) / 86400 }
        let stale = replacements.filter { onlyOldDays(prev: $0.prev, next: $0.next) }.count

        // 不满一天就按小时显示 —— 手工多幕验证时几次替换常常挤在同一分钟里，
        // 一律写「0.0 天」等于什么都没说。
        func days(_ v: Double?) -> String {
            guard let v else { return "—" }
            return v < 1 ? String(format: "%.1f 小时", v * 24) : String(format: "%.1f 天", v)
        }

        let aiCalls = checks.filter(\.aiCalled).count
        let shown = checks.filter(\.finalShown).count
        var blocked: [String: Int] = [:]
        for c in checks where !c.gatePassed { blocked[c.gateReason ?? "?", default: 0] += 1 }

        return [
            ("关怀 \(cares.count) 条",
             "替换 \(replacements.count) 次 · 退场后重新开口 \(reopens) 次"),

            ("替换间隔",
             "最短 \(days(gaps.min())) · 最长 \(days(gaps.max())) · 平均 \(days(gaps.isEmpty ? nil : gaps.reduce(0,+) / Double(gaps.count)))"),

            ("【关键】替换里「引用全是旧日子」 \(stale)/\(replacements.count)",
             "这些是在复述已经回应过的内容 —— 占比高的话，「静默更新而不重新演出」那个方案就值得做"),

            ("检查 \(checks.count) 次",
             "闸门放行 \(checks.filter(\.gatePassed).count) · 调 AI \(aiCalls) · 最终说了 \(shown)"),

            ("闸门挡下的原因",
             blocked.isEmpty ? "—" : blocked.sorted { $0.value > $1.value }
                .map { "\($0.key) ×\($0.value)" }.joined(separator: "\n")),

            ("AI 调用率",
             checks.isEmpty ? "—" : String(format: "%.0f%%（%d/%d）——闸门该拦下大部分",
                                           Double(aiCalls) / Double(checks.count) * 100,
                                           aiCalls, checks.count)),
        ]
    }
}
#endif
