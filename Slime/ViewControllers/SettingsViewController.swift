//
//  SettingsViewController.swift
//  Slime
//

import UIKit
import SnapKit
import SafariServices

/// 设置页。入口在首页右上角的齿轮。
///
/// 两行，都是审核规则要求 App 里必须有的：
/// · 撤回 AI 授权 —— 5.1.1(ii)：要有**容易找到、看得懂**的撤回同意方式
/// · 隐私政策 —— 5.1.1(i)：App 里要有隐私政策的链接，而且容易找到
/// 以后开源致谢、求助入口也放这里，加一个 Section / Item 就行。
///
/// 跟同意页一样**只负责显示**：撤回之后存哪、换哪个页面，是组合根的事，这里只通过 `onWithdraw` 报告。
final class SettingsViewController: UIViewController {

    // Diffable 的标识要求 Sendable；工程默认主线程隔离，所以这两个枚举要显式 nonisolated（同 ChatViewController）
    private enum Section: nonisolated Hashable {
        case ai
        case about
    }

    private enum Item: nonisolated Hashable {
        case withdrawConsent
        case privacyPolicy
    }

    private let onWithdraw: () -> Void

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!

    init(onWithdraw: @escaping () -> Void) {
        self.onWithdraw = onWithdraw
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Sky.top

        title = "设置"
        navigationController?.navigationBar.titleTextAttributes = [
            .font: AppFont.font(18),
            .foregroundColor: Sky.ink,
        ]
        let done = UIBarButtonItem(title: "完成", style: .done, target: self, action: #selector(close))
        done.setTitleTextAttributes([.font: AppFont.font(17)], for: .normal)
        done.setTitleTextAttributes([.font: AppFont.font(17)], for: .highlighted)
        done.tintColor = Sky.ink
        navigationItem.rightBarButtonItem = done

        setupCollectionView()
        applySnapshot()
    }

    // MARK: - 列表

    private func setupCollectionView() {
        // 系统自带的「设置」样式：圆角分组、每组底下可以挂一段说明文字（footer）
        var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        config.backgroundColor = Sky.top
        config.footerMode = .supplementary
        let layout = UICollectionViewCompositionalLayout.list(using: config)

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.delegate = self
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { $0.edges.equalToSuperview() }

        let cellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Item> { cell, _, item in
            var content = cell.defaultContentConfiguration()
            switch item {
            case .withdrawConsent:
                content.text = "撤回 AI 授权"
                // 冠子的红：是个「要想一下再点」的动作，但不是删东西，不用系统那种刺眼的红
                content.textProperties.color = Palette.comb
                cell.accessories = []
            case .privacyPolicy:
                content.text = "隐私政策"
                content.textProperties.color = Sky.ink
                // 右边的小箭头：告诉人「点了会去另一页」
                cell.accessories = [.disclosureIndicator(options: .init(tintColor: Sky.ink(0.3)))]
            }
            content.textProperties.font = AppFont.font(17)
            cell.contentConfiguration = content
            // 从 cell 自己的默认背景改起（`UIBackgroundConfiguration.listCell()` 要 iOS 18，工程最低 17.6）
            var background = cell.defaultBackgroundConfiguration()
            background.backgroundColor = Sky.bubble
            cell.backgroundConfiguration = background
        }

        let footerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionFooter
        ) { [weak self] footer, _, indexPath in
            guard let section = self?.dataSource.sectionIdentifier(for: indexPath.section) else { return }
            var content = UIListContentConfiguration.groupedFooter()
            switch section {
            case .ai:
                content.text = "撤回之后，母鸡不再把任何内容发给 AI，App 会回到同意页。日记和蛋都还留在这台手机上，重新同意就能接着用。"
            case .about:
                content.text = nil
            }
            content.textProperties.font = AppFont.font(14)
            content.textProperties.color = Sky.ink(0.45)
            footer.contentConfiguration = content
        }

        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) {
            collectionView, indexPath, item in
            collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: item)
        }
        dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(using: footerRegistration, for: indexPath)
        }
    }

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.ai, .about])
        snapshot.appendItems([.withdrawConsent], toSection: .ai)
        snapshot.appendItems([.privacyPolicy], toSection: .about)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    // MARK: - 动作

    @objc private func close() {
        dismiss(animated: true)
    }

    /// 用 App 内的 Safari（SFSafariViewController）打开，不跳出 App：看完点「完成」就回到设置页。
    /// 它是系统提供的完整浏览器界面，自带地址栏和「完成」按钮，不用自己写网页容器。
    private func openPrivacyPolicy() {
        let safari = SFSafariViewController(url: AppLinks.privacyPolicy)
        safari.preferredControlTintColor = Palette.beak
        present(safari, animated: true)
    }

    /// 撤回前再确认一次：点了之后整个 App 会换成同意页，误触的代价不小。
    private func confirmWithdraw() {
        let alert = UIAlertController(
            title: "撤回 AI 授权？",
            message: "母鸡会停止读你的日记，App 回到同意页。日记都还在，重新同意就能接着用。",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "撤回", style: .destructive) { [weak self] _ in
            guard let self else { return }
            // 先把自己收掉，收完再报告。
            // 组合根收到报告会换掉整个根页面；设置页还挂在上面的话，
            // 旧的根页面带着它一起被换走，这一页可能残留在屏幕上、或者跟着旧页面一起泄漏。
            let onWithdraw = self.onWithdraw
            self.dismiss(animated: true) { onWithdraw() }
        })
        present(alert, animated: true)
    }
}

extension SettingsViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        switch item {
        case .withdrawConsent:
            confirmWithdraw()
        case .privacyPolicy:
            openPrivacyPolicy()
        }
    }
}
