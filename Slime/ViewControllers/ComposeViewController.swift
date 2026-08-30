//
//  ComposeViewController.swift
//  Slime
//
//  生成页:写一句碎碎念 → 点"生成" → 一只史莱姆孵化揭晓 → 走进广场。
//  两种模式:输入模式(写字) / 孵化模式(播揭晓动画)。VC 只做编排,
//  存数据交给 ViewModel、绘制与动画交给 SlimeView、转场交给导航控制器。
//

import UIKit
import SnapKit

final class ComposeViewController: UIViewController {

    // MARK: - 依赖

    private let viewModel: ComposeViewModel
    private let careViewModel: CareViewModel
    private var careBubble: CareBubbleView?
    
    var backdropImage: UIImage?

    
    var onClose: (() -> Void)?
    
    init(viewModel: ComposeViewModel, careViewModel: CareViewModel) {
        self.viewModel = viewModel
        self.careViewModel = careViewModel
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - UI 控件
    
    private let backdrop: UIImageView = {
        let v = UIImageView()
        v.contentMode = .scaleAspectFill
        v.isUserInteractionEnabled = true
        return v
    }()
    
    private let scrim: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor(hex: 0xFDFBF4).withAlphaComponent(0.26)
        v.isUserInteractionEnabled = false
        return v
    }()
    
    private let cardShadow: UIView = {
        let v = UIView()
        v.backgroundColor = .clear
        v.layer.shadowColor = UIColor(hex: 0x6B5B45).cgColor
        v.layer.shadowOpacity = 0.14
        v.layer.shadowRadius = 30
        v.layer.shadowOffset = CGSize(width: 0, height: 14)
        return v
    }()
    
    private let card: UIVisualEffectView = {
        let v = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
        v.layer.cornerRadius = 28
        v.layer.cornerCurve = .continuous
        
        v.clipsToBounds = true
        v.layer.borderWidth = 1
        v.layer.borderColor = UIColor.white.withAlphaComponent(0.55).cgColor
        return v
    }()
    
    private let cardTint: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.white.withAlphaComponent(0.52)
        v.isUserInteractionEnabled = false
        return v
    }()
    
    private let dateLabel = UILabel()
    
    private let textView: UITextView  = {
        let tv = UITextView()
        tv.font  = Kai.font(19)
        tv.textColor = Sky.ink
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.keyboardDismissMode = .interactive
        return tv
    }()



    /// 占位提示文字(叠在输入框上模拟 placeholder)。
    private let placeholderLabel: UILabel = {
        let label = UILabel()
        label.text = "此刻想说点什么…"
        label.font = .systemFont(ofSize: 18)
        label.textColor = .tertiaryLabel
        return label
    }()
    
    private let generateButton: UIButton = {
        let b = UIButton(type: .system)
        b.setAttributedTitle(Kai.attributed("下 蛋", size: 17, color: Sky.ink(0.75), kern: 2), for: .normal)
        b.backgroundColor = UIColor.white.withAlphaComponent(0.75)
        b.layer.cornerRadius = 24
        b.layer.cornerCurve = .continuous
        return b
    }()

    /// 生成时中央出现的史莱姆,复用 SlimeView 组件。平时隐藏。
    private let slimeView: SlimeView = {
        let v = SlimeView()
        v.isHidden = true
        return v
    }()

    /// 揭晓后在史莱姆下面淡入的一行 AI 回复。平时隐藏。
    private let replyLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        return label
    }()

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        setupUI()
        textView.delegate = self
        generateButton.addTarget(self, action: #selector(generateTapped), for: .touchUpInside)
        
        //点糊掉区域=关掉浮窗
        backdrop.image = backdropImage
        backdrop.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(closeTapped)))
      
    }

    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        resetToInputMode()
        cardShadow.transform = CGAffineTransform(translationX: 0, y: 46).scaledBy(x: 0.94, y: 0.94)
        cardShadow.alpha = 0
        generateButton.alpha = 0
        
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // 只有输入模式才自动弹键盘
        UIView.animate(withDuration: 0.5, delay: 0.04, usingSpringWithDamping: 0.82, initialSpringVelocity: 0.2) {
            self.cardShadow.transform = .identity
            self.cardShadow.alpha = 1
            self.generateButton.alpha = 1
        }
        //主动关心
       // presentCareIfNeeded()
    }

    // MARK: - 搭建 UI

  

    private func setupUI() {
        view.addSubview(backdrop)
        view.addSubview(scrim)
        view.addSubview(cardShadow)
        cardShadow.addSubview(card)
        // 内容必须加到 contentView,不能直接加到 UIVisualEffectView 上 ——
        // 后者是给系统的效果层用的,直接塞会有渲染异常。
        card.contentView.addSubview(cardTint)
        card.contentView.addSubview(dateLabel)
        card.contentView.addSubview(textView)
        card.contentView.addSubview(placeholderLabel)
        view.addSubview(generateButton)
        view.addSubview(slimeView)
        view.addSubview(replyLabel)

        dateLabel.attributedText = Kai.attributed(todayTitle(), size: 15, color: Sky.ink(0.45))
        placeholderLabel.attributedText = Kai.attributed("今天……", size: 19, color: Sky.ink(0.28))

        backdrop.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        cardShadow.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(100)
            make.leading.trailing.equalToSuperview().inset(26)
            make.bottom.equalTo(generateButton.snp.top).offset(-28)
            make.height.lessThanOrEqualTo(360)
        }
        card.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        cardTint.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        dateLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(26)
            make.leading.equalToSuperview().offset(26)
        }
        textView.snp.makeConstraints { make in
            make.top.equalTo(dateLabel.snp.bottom).offset(26)
            make.leading.trailing.equalToSuperview().inset(26)
            make.bottom.equalToSuperview().offset(-26)
        }
        placeholderLabel.snp.makeConstraints { make in
            make.top.leading.equalTo(textView)
        }
        generateButton.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalTo(view.keyboardLayoutGuide.snp.top).offset(-24)
            make.width.equalTo(132)
            make.height.equalTo(48)
        }
        
        slimeView.snp.makeConstraints { make in
               make.center.equalToSuperview()
               make.width.height.equalTo(180)
           }

        replyLabel.snp.makeConstraints { make in
            make.top.equalTo(slimeView.snp.bottom).offset(16)
            make.leading.trailing.equalToSuperview().inset(32)
        }

    }

    /// "八月十六日 · 星期日"
    private func todayTitle() -> String {
        let names = ["日", "一", "二", "三", "四", "五", "六"]
        let index = Calendar.current.component(.weekday, from: Date()) - 1
        return ChineseDate.title() + "日 · 星期" + names[index]
    }
    
    // MARK: - 交互

    @objc private func closeTapped() {
        guard slimeView.isHidden else { return }
        textView.resignFirstResponder()
        onClose?()
        dismiss(animated: true)
    }

    // 生成:先出未定形并凝结(乐观 UI)→ 后台调 AI → 拿到真实情绪再揭晓 → 走进广场
    @objc private func generateTapped() {
        let text = textView.text ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        //孵化前收走气泡
        careBubble?.removeFromSuperview()
        careBubble = nil
        
        enterHatchingMode()
        slimeView.beginHatching()     // 立刻凝结,用动画盖住下面的网络等待

        // Task:进入 async 世界,后台等 AI 结果(界面不卡,凝结/待机动画照播)
        Task {
            //失败也有孵化画面
            let startedAt = DispatchTime.now()
            let minHatchNanos: UInt64 = 800_000_000
            do {
                let item =  try await viewModel.generate(content: text)
                // 拿到真实情绪 → 揭晓;揭晓完淡入 AI 回复,读一会儿再走进广场
                slimeView.reveal(to: item.emotion) { [weak self] in
                    guard let self else { return }
                    self.showReply(item.reply)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
                        self?.goToSquare()
                    }
                }
            } catch {
                //返回输入
                await waitAtLeast(minHatchNanos, since: startedAt)
                handleGenerateFailure(error)
            }
        }
    }
    
    private func waitAtLeast(_ minNanos: UInt64, since start: DispatchTime) async {
        let elapsed = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
        if elapsed < minNanos {
            try? await Task.sleep(nanoseconds: minNanos - elapsed)
        }
    }
    
    private func handleGenerateFailure(_ error: Error) {
        print("生成失败\(error)")
        
        slimeView.isHidden = true
        replyLabel.isHidden = true
        textView.isHidden = false
        placeholderLabel.isHidden = !(textView.text ?? "").isEmpty
        generateButton.isEnabled = true

        let alert = UIAlertController(
            title: "分析失败",
            message: "嗷 网络好像出了点问题",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "收到", style: .cancel))
        present(alert, animated: true)
    }
    

    // 淡入一行 AI 回复(在史莱姆下面)
    private func showReply(_ reply: String?) {
        guard let reply, !reply.isEmpty else { return }
        replyLabel.text = reply
        replyLabel.alpha = 0
        replyLabel.isHidden = false
        UIView.animate(withDuration: 0.3) { self.replyLabel.alpha = 1 }
    }

    private func goToSquare() {
        onClose?()
        dismiss(animated: true)
    }
    
    //MARK: - 主动过关心出现
    private func presentCareIfNeeded() {
        guard careBubble == nil,
              slimeView.isHidden,
              let care = careViewModel.activeCare() else { return }
        
        let bubble = CareBubbleView(text: care.text)
        view.addSubview(bubble)
        bubble.snp.makeConstraints { make in
            make.top.equalTo(textView.snp.bottom).offset(20)
            make.leading.equalToSuperview().inset(16)
            make.trailing.lessThanOrEqualToSuperview().inset(16)
        }
        
        bubble.onFirstExpand = { [weak self] in
            self?.careViewModel.markRead(care)
        }
        bubble.onDismiss = { [weak self] in
//            self?.careBubble?.removeFromSuperview()
//            self?.careBubble = nil
        }
//        bubble.onChat = { [weak self] in
//            guard let self else { return }
//            self.careViewModel.markAccepted(care)
////            self.careBubble?.removeFromSuperview()
////            self.careBubble = nil
//            let chatVM = ChatViewModel(care: care, chatRepo: CoreDataChatRepository(), posts: CoreDataPostRepository(), aiService: DeepSeekAIService())
//            
//            self.navigationController?.pushViewController(ChatViewController(viewModel: chatVM), animated: true)
//            
//        }
        
        careBubble = bubble
        bubble.playEntrance()
        careViewModel.markShown(care)
    }

    // MARK: - 两种模式切换

    private func enterHatchingMode() {
        textView.resignFirstResponder()
        textView.isHidden = true
        placeholderLabel.isHidden = true
        replyLabel.isHidden = true
        slimeView.isHidden = false
        cardShadow.isHidden = true
        generateButton.isHidden = true
        generateButton.isEnabled = false   // 孵化中禁止再点生成
    }

    private func resetToInputMode() {
        slimeView.isHidden = true
        replyLabel.isHidden = true
        textView.isHidden = false
        cardShadow.isHidden = false
        generateButton.isHidden = false
        textView.text = ""
        placeholderLabel.isHidden = false
        navigationItem.rightBarButtonItem?.isEnabled = true
    }
}

// MARK: - UITextViewDelegate

extension ComposeViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        placeholderLabel.isHidden = !textView.text.isEmpty
    }
}
