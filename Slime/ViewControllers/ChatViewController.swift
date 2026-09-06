//
//  ChatViewController.swift
//  Slime
//

import UIKit
import SnapKit

/// 和母鸡说话的地方。
///
/// 层次从后往前：底色 → 母鸡（铺满，被输入条裁掉下缘）→ 气泡列表 → 输入条。
/// 母鸡是背景，不跟键盘走；只有输入条跟着键盘上下。
final class ChatViewController: UIViewController {

    private let viewModel: ChatViewModel

    private enum Section: nonisolated Hashable { case main }

    private enum Item: nonisolated Hashable {
        case message(ChatMessageItem)
        case streaming
        case retryHint
    }

    // MARK: - 视图

    private let henStage = HenStageView()
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!

    /// 列表顶部的渐隐。飘到上面的旧消息化进底色，而不是在屏幕边缘被硬切一刀。
    private let fadeMask = CAGradientLayer()

    private let inputBar = UIView()

    private let inputTextView: UITextView = {
        let tv = UITextView()
        tv.backgroundColor = .clear
        tv.textColor = ChatPalette.text
        tv.textContainerInset = UIEdgeInsets(top: 10, left: 6, bottom: 10, right: 6)
        tv.isScrollEnabled = false
        if let d = UIFont.systemFont(ofSize: 16).fontDescriptor.withDesign(.rounded) {
            tv.font = UIFont(descriptor: d, size: 16)
        } else {
            tv.font = .systemFont(ofSize: 16)
        }
        return tv
    }()

    private let inputBackground: UIView = {
        let v = UIView()
        v.backgroundColor = ChatPalette.inputField
        v.layer.cornerRadius = 22
        v.layer.cornerCurve = .continuous
        return v
    }()

    private let inputPlaceholder: UILabel = {
        let l = UILabel()
        l.text = "说点什么"
        l.textColor = ChatPalette.inputHint
        if let d = UIFont.systemFont(ofSize: 16).fontDescriptor.withDesign(.rounded) {
            l.font = UIFont(descriptor: d, size: 16)
        } else {
            l.font = .systemFont(ofSize: 16)
        }
        return l
    }()

    private let sendButton: UIButton = {
        let b = UIButton(type: .custom)
        b.setImage(UIImage(systemName: "arrow.up",
                           withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .bold)),
                   for: .normal)
        b.tintColor = .white
        b.backgroundColor = Palette.beak
        b.layer.cornerRadius = 19
        return b
    }()

    private static let minInputHeight: CGFloat = 44
    private static let maxInputHeight: CGFloat = 130
    private var inputHeightConstraint: Constraint?

    // MARK: - 状态

    private var isWaitingReply = false {
        didSet {
            sendButton.isEnabled = !isWaitingReply
            sendButton.alpha = isWaitingReply ? 0.4 : 1
        }
    }
    private var showsRetry = false
    private var lastStreamRenderAt: CFTimeInterval = 0
    private var didPlayEntrance = false

    // MARK: -

    init(viewModel: ChatViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ChatPalette.background

        setupUI()
        setupDataSource()
        applySnapshot(animated: false)

        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        inputTextView.delegate = self
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        henStage.startBreathing()

        // 波浪只在第一次进来时荡 —— 每次回到这一页都演一遍就成了噪音
        if !didPlayEntrance {
            didPlayEntrance = true
            henStage.playEntranceRipple()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        henStage.stopBreathing()
        henStage.stopTalking()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateFadeMask()
    }

    // MARK: - UI

    private func setupUI() {
        // 1. 母鸡铺满整页，压在最底下
        view.addSubview(henStage)
        henStage.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        // 2. 输入条。keyboardLayoutGuide 是 iOS 15+ 系统自带的「键盘位置向导」，
        //    约束到它的顶，键盘弹起/收起输入条自动跟着走
        view.addSubview(inputBar)
        inputBar.addSubview(inputBackground)
        inputBackground.addSubview(inputTextView)
        inputTextView.addSubview(inputPlaceholder)
        inputBar.addSubview(sendButton)

        inputBar.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(view.keyboardLayoutGuide.snp.top)
        }
        inputBackground.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(18)
            make.top.bottom.equalToSuperview().inset(10)
            inputHeightConstraint = make.height.equalTo(Self.minInputHeight).constraint
        }
        inputTextView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12))
        }
        inputPlaceholder.snp.makeConstraints { make in
            // 对齐 UITextView 真正的文字起点：
            // 左 = textContainerInset.left(6) + lineFragmentPadding(默认 5)
            // 上 = textContainerInset.top(10)
            make.leading.equalToSuperview().offset(11)
            make.top.equalToSuperview().offset(10)
        }
        sendButton.snp.makeConstraints { make in
            make.leading.equalTo(inputBackground.snp.trailing).offset(10)
            make.trailing.equalToSuperview().inset(16)
            make.bottom.equalTo(inputBackground.snp.bottom).offset(-3)
            make.width.height.equalTo(38)
        }

        // 3. 气泡列表夹在中间，背景透明，母鸡透过来
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.showsVerticalScrollIndicator = false
        collectionView.keyboardDismissMode = .interactive
        view.insertSubview(collectionView, belowSubview: inputBar)
        collectionView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(8)
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(inputBar.snp.top).offset(-6)
        }

        fadeMask.colors = [UIColor.clear.cgColor, UIColor.black.cgColor]
        fadeMask.locations = [0, 0.2]
        fadeMask.startPoint = CGPoint(x: 0.5, y: 0)
        fadeMask.endPoint = CGPoint(x: 0.5, y: 1)
        collectionView.layer.mask = fadeMask
    }

    /// mask 挂在 layer 上，坐标系是内容坐标系 —— 列表一滚它就跟着内容跑掉了。
    /// 所以每次滚动都把它拉回可视区域，让渐隐永远贴在屏幕顶部。
    private func updateFadeMask() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fadeMask.frame = CGRect(origin: CGPoint(x: 0, y: collectionView.contentOffset.y),
                                size: collectionView.bounds.size)
        CATransaction.commit()
    }

    private func makeLayout() -> UICollectionViewLayout {
        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                              heightDimension: .estimated(52))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let group = NSCollectionLayoutGroup.vertical(layoutSize: itemSize, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 0
        return UICollectionViewCompositionalLayout(section: section)
    }

    private func setupDataSource() {
        let cell = UICollectionView.CellRegistration<ChatBubbleCell, Item> { [weak self] cell, indexPath, item in
            guard let self else { return }
            // 离最新那条多远。0 = 最新，越往上越淡
            let total = self.collectionView.numberOfItems(inSection: 0)
            let depth = max(0, total - 1 - indexPath.item)

            switch item {
            case .message(let m):
                cell.configure(text: m.content, role: m.role, depth: depth)
            case .streaming:
                cell.configure(text: self.viewModel.streamingText ?? "", role: .slime, depth: depth)
            case .retryHint:
                cell.configure(text: "咕……刚刚走神了，能再跟我说一遍吗", role: .slime, depth: depth)
            }
        }

        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) {
            collectionView, indexPath, item in
            collectionView.dequeueConfiguredReusableCell(using: cell, for: indexPath, item: item)
        }
    }

    private func applySnapshot(animated: Bool = true) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.main])
        snapshot.appendItems(viewModel.messages.map { .message($0) })
        if viewModel.streamingText != nil { snapshot.appendItems([.streaming]) }
        if showsRetry { snapshot.appendItems([.retryHint]) }

        // 每条消息的颜色取决于它离底部多远 —— 来了新消息，旧的都要淡一档
        snapshot.reconfigureItems(snapshot.itemIdentifiers)

        dataSource.apply(snapshot, animatingDifferences: animated)
        scrollToBottom()
    }

    /// 每个 delta 都会调，但界面最多 ~60ms 刷一次（节流，保护主线程）
    private func onStreamDelta() {
        let now = CACurrentMediaTime()
        guard now - lastStreamRenderAt >= 0.06 else { return }
        lastStreamRenderAt = now

        var snapshot = dataSource.snapshot()
        if snapshot.itemIdentifiers.contains(.streaming) {
            snapshot.reconfigureItems([.streaming])
            dataSource.apply(snapshot, animatingDifferences: false)
            scrollToBottom(animated: false)
        } else {
            applySnapshot(animated: false)
        }
    }

    private func scrollToBottom(animated: Bool = true) {
        let count = collectionView.numberOfItems(inSection: 0)
        guard count > 0 else { return }
        collectionView.scrollToItem(at: IndexPath(item: count - 1, section: 0), at: .bottom, animated: animated)
    }

    // MARK: - 输入框高度

    private func updateInputHeight() {
        let width = inputTextView.bounds.width
        guard width > 0 else { return }

        let fitting = inputTextView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        let clamped = min(max(fitting, Self.minInputHeight), Self.maxInputHeight)
        inputTextView.isScrollEnabled = fitting > Self.maxInputHeight

        inputHeightConstraint?.update(offset: clamped)
        UIView.animate(withDuration: 0.15) { self.view.layoutIfNeeded() }
    }

    // MARK: - 发送 / 重试

    @objc private func sendTapped() {
        let text = inputTextView.text ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !isWaitingReply else { return }

        inputTextView.text = ""
        inputPlaceholder.isHidden = false
        updateInputHeight()

        Task {
            await requestRound {
                try await self.viewModel.send(text, onDelta: { self.onStreamDelta() })
            }
        }
    }

    private func retryTapped() {
        guard !isWaitingReply else { return }
        Task {
            await requestRound {
                try await self.viewModel.retry(onDelta: { self.onStreamDelta() })
            }
        }
    }

    /// 一轮请求：上屏用户消息 → 等回复 → 成功 / 失败（可重试）
    private func requestRound(_ round: () async throws -> ChatMessageItem) async {
        showsRetry = false
        isWaitingReply = true
        applySnapshot()
        henStage.startTalking()

        do {
            _ = try await round()
            showsRetry = false
        } catch {
            print("聊天请求失败 \(error)")
            showsRetry = true
        }

        henStage.stopTalking()
        isWaitingReply = false
        applySnapshot()
    }
}

// MARK: - 滚动与重试

extension ChatViewController: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        if case .retryHint = dataSource.itemIdentifier(for: indexPath) {
            retryTapped()
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateFadeMask()
    }
}

extension ChatViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        inputPlaceholder.isHidden = !textView.text.isEmpty
        updateInputHeight()
    }
}
