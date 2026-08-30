//
//  ChatViewController.swift
//  Slime
//
//  Created by shiying on 2026/8/4.
//

import UIKit
import SnapKit

final class ChatViewController: UIViewController {

    private let viewModel: ChatViewModel
    
    private enum Item: nonisolated Hashable {
        case message(ChatMessageItem)
        case streaming
        case retryHint
    }
    
    private enum Section: nonisolated Hashable { case main }
    
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    
    private let slimeView = SlimeView()
    
    private let inputField: UITextField = {
        let f = UITextField()
        f.placeholder = "说点什么"
        f.backgroundColor = .secondarySystemBackground
        f.layer.cornerRadius = 18
        //textfield没有inset 惯用一个view顶开边距
        f.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 0))
        f.leftViewMode = .always
        f.returnKeyType = .send
        return f
    }()
    
    private let inputTextView: UITextView = {
        let tv = UITextView()
        tv.font = .systemFont(ofSize: 16)
        tv.backgroundColor = .secondarySystemBackground
        tv.layer.cornerRadius = 18
        tv.textContainerInset = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        tv.isScrollEnabled = false
        return tv
    }()
    
    private static let minInputHeight: CGFloat = 36
    private static let maxInputHeight: CGFloat = 120
    private var inputHeightConstraint: Constraint?
    
    
    private let inputPlaceholder: UILabel = {
        let l = UILabel()
        l.text = "say something"
        l.font = .systemFont(ofSize: 16)
        l.textColor = .tertiaryLabel
        return l
    }()
    
    private let sendButton: UIButton = {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: "arrow.up.circle.fill"), for: .normal)
        b.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 28), forImageIn: .normal)
        return b
    }()
    
    private var isWaitingReply = false {
        didSet {
            sendButton.isEnabled = !isWaitingReply
        }
    }
    
    init(viewModel: ChatViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }
    
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "和史莱姆聊聊"
        view.backgroundColor = .systemBackground
        setupUI()
        setupDataSource()
        applySnapshot(animated: false)
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        inputTextView.delegate = self
        // Do any additional setup after loading the view.
    }
    
    //MARK: - UI
    
    private func setupUI() {
        //底部输入条
        let inputBar = UIView()
        view.addSubview(inputBar)
        inputBar.addSubview(inputTextView)
        inputTextView.addSubview(inputPlaceholder)
        inputBar.addSubview(sendButton)
        
        // keyboardLayoutGuide:iOS 15+ 系统自带的"键盘位置向导",
        // 约束到它的顶,键盘弹起/收起输入条自动跟着走,不用再手写通知监听
        
        inputBar.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            
            make.bottom.equalTo(view.keyboardLayoutGuide.snp.top)
        }
        
        inputTextView.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(16)
            make.top.bottom.equalToSuperview().inset(10)
            inputHeightConstraint = make.height.equalTo(Self.minInputHeight).constraint
        }
        
        inputPlaceholder.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(8)
            make.leading.equalToSuperview().offset(15)
        }
        
        sendButton.snp.makeConstraints { make in
            make.leading.equalTo(inputTextView.snp.trailing).offset(8)
            make.trailing.equalToSuperview().inset(12)
            make.bottom.equalTo(inputTextView.snp.bottom)
            make.width.height.equalTo(44)
        }
        
        view.addSubview(slimeView)
        slimeView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalTo(inputBar.snp.top).offset(-20)
            make.width.height.equalTo(110)
        }
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(slimeView.snp.top).offset(-12)
        }
    }
    
    //计算输入框高度
    private func updateInputHeight() {
        let width = inputTextView.bounds.width
        guard width > 0 else { return }
        
        let fitting = inputTextView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        
        let clamped = min(max(fitting, Self.minInputHeight), Self.maxInputHeight)
        inputTextView.isScrollEnabled = fitting > Self.maxInputHeight
        
        inputHeightConstraint?.update(offset: clamped)
        UIView.animate(withDuration: 0.15) {
            self.view.layoutIfNeeded()
        }
        
    }
    
    private func makeLayout() -> UICollectionViewLayout {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .estimated(44)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let group = NSCollectionLayoutGroup.vertical(layoutSize: itemSize, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 2
        return UICollectionViewCompositionalLayout(section:  section)
        
    }
    
    private func setupDataSource() {
        let messageCell = UICollectionView.CellRegistration<ChatBubbleCell,ChatMessageItem> { cell, _, item in
            cell.configure(with: item)
            
        }
        // 重试提示复用同一种 cell,装成史莱姆说话的样子
        let retryCell = UICollectionView.CellRegistration<ChatBubbleCell, String> { cell, _, text in
            cell.configure(with: ChatMessageItem(id: UUID(), role: .slime, content: text, createdAt: Date()))
            
        }
        
        dataSource = UICollectionViewDiffableDataSource<Section, Item> (collectionView: collectionView, cellProvider: { collectionView, indexPath, item in
            switch item {
            case .message(let message):
                return collectionView.dequeueConfiguredReusableCell(using: messageCell, for: indexPath, item: message)
            case .streaming:
                let text = self.viewModel.streamingText ?? ""
                return collectionView.dequeueConfiguredReusableCell(using: retryCell, for: indexPath, item: text)
            case .retryHint:
                return collectionView.dequeueConfiguredReusableCell(using: retryCell, for: indexPath, item: "ohno，刚刚走神了，能在跟我说一遍吗")
            }
        })
    }
        
    private var showsRetry = false
    
    private var lastStreamRenderAt: CFTimeInterval = 0
        
    private func applySnapshot(animated: Bool = true) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.main])
        snapshot.appendItems(viewModel.messages.map {.message($0)})
        if viewModel.streamingText != nil {
            snapshot.appendItems([.streaming])
        }
        if showsRetry { snapshot.appendItems([.retryHint])}
        dataSource.apply(snapshot, animatingDifferences: animated)
        scrollToBottom()
    }
    
    //每个delta都会调用，但界面最多~60ms刷一次（节流，保护主线程
    private func onStreamDelta() {
        let now = CACurrentMediaTime()
        guard now - lastStreamRenderAt >= 0.06  else { return }
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
    
    //MARK: - 发送 /重试
    
    @objc private func sendTapped() {
        let text = inputTextView.text ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !isWaitingReply else { return }
        inputTextView.text = ""
        inputPlaceholder.isHidden = false
        updateInputHeight()
        Task {
            await requestRound {
                try await self.viewModel.send(text, onDelta: { self.onStreamDelta()})
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
    
    //一轮请求：上屏用户消息 -> 等回复 -> 成功/失败（重试）
    private func requestRound(_ round: () async throws -> ChatMessageItem) async {
        showsRetry = false
        isWaitingReply = true
        applySnapshot()
        slimeView.startTalking()
        
        do {
            _ = try await round()
            showsRetry = false
        } catch {
            print("聊天请求失败\(error)")
            showsRetry = true
        }
        slimeView.stopTalking()
        isWaitingReply = false
        applySnapshot()
    }
        
    

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

}

// MARK: - 重试

extension ChatViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        if case .retryHint = dataSource.itemIdentifier(for: indexPath) {
            retryTapped()
        }
    }
}

extension ChatViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        sendTapped()
        return false
    }
}
extension ChatViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        inputPlaceholder.isHidden = !textView.text.isEmpty
        updateInputHeight()
    }
}
