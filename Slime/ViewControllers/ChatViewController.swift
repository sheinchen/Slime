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
        inputField.delegate = self
        // Do any additional setup after loading the view.
    }
    
    //MARK: - UI
    
    private func setupUI() {
        //底部输入条
        let inputBar = UIView()
        view.addSubview(inputBar)
        inputBar.addSubview(inputField)
        inputBar.addSubview(sendButton)
        
        // keyboardLayoutGuide:iOS 15+ 系统自带的"键盘位置向导",
        // 约束到它的顶,键盘弹起/收起输入条自动跟着走,不用再手写通知监听
        
        inputBar.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            
            make.bottom.equalTo(view.keyboardLayoutGuide.snp.top)
            make.height.equalTo(56)
        }
        inputField.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(16)
            make.centerY.equalToSuperview()
            make.height.equalTo(36)
        }
        sendButton.snp.makeConstraints { make in
            make.leading.equalTo(inputField.snp.trailing).offset(8)
            make.trailing.equalToSuperview().inset(12)
            make.centerY.equalToSuperview()
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
            case .retryHint:
                return collectionView.dequeueConfiguredReusableCell(using: retryCell, for: indexPath, item: "ohno，刚刚走神了，能在跟我说一遍吗")
            }
        })
    }
        
    private var showsRetry = false
        
    private func applySnapshot(animated: Bool = true) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.main])
        snapshot.appendItems(viewModel.messages.map {.message($0)})
        if showsRetry { snapshot.appendItems([.retryHint])}
        dataSource.apply(snapshot, animatingDifferences: animated)
        scrollToBottom()
    }
    
    private func scrollToBottom() {
        let count = collectionView.numberOfItems(inSection: 0)
        guard count > 0 else { return }
        collectionView.scrollToItem(at: IndexPath(item: count - 1, section: 0), at: .bottom, animated: true)
    }
    
    //MARK: - 发送 /重试
    
    @objc private func sendTapped() {
        let text = inputField.text ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !isWaitingReply else { return }
        inputField.text = ""
        
        Task {
            await requestRound {
                try await self.viewModel.send(text)
            }
        }
        
    }
    
    private func retryTapped() {
        guard !isWaitingReply else { return }
        Task {
            await requestRound {
                try await self.viewModel.retry()
            }
        }
    }
    
    //一轮请求：上屏用户消息 -> 等回复 -> 成功/失败（重试）
    private func requestRound(_ round: () async throws -> ChatMessageItem) async {
        showsRetry = false
        isWaitingReply = true
        applySnapshot()
        
        do {
            _ = try await round()
            showsRetry = false
        } catch {
            print("聊天请求失败\(error)")
            showsRetry = true
        }
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
