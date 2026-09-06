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

    
    var backdropImage: UIImage?

    
    var onClose: (() -> Void)?
    
    init(viewModel: ComposeViewModel) {
        self.viewModel = viewModel
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
        b.setAttributedTitle(Kai.attributed("收 好", size: 17, color: Sky.ink(0.75), kern: 2), for: .normal)
        b.backgroundColor = UIColor.white.withAlphaComponent(0.75)
        b.layer.cornerRadius = 24
        b.layer.cornerCurve = .continuous
        return b
    }()

    /// 记录时上台的母鸡。载入失败就是 nil ——
    /// 那时演出降级成「只淡入一行回应」，不崩、也不卡流程。
    private let henView: RiveHenView? = {
        let v = RiveHenView.make()
        v?.isHidden = true
        return v
    }()

    /// 正在记录（母鸡在台上）。
    /// 以前是拿 slimeView.isHidden 当状态用，但 henView 可能是 nil，
    /// isHidden 就不再可靠 —— 状态该显式存着。
    private var isRecording = false

    /// 等她点完头再说的那句话
    private var pendingReply: String?
    /// 这一轮的回应有没有送出去。回调和兜底超时谁先到都只算一次。
    private var didDeliverReply = false

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

        // 她点完头，才轮到说话
        henView?.onClipFinished = { [weak self] clip in
            guard let self, clip == .nod, self.isRecording else { return }
            self.deliverReply()
        }
        
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
        if let henView { view.addSubview(henView) }
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
        
        if let henView {
            henView.snp.makeConstraints { make in
                make.centerX.equalToSuperview()
                make.centerY.equalToSuperview().offset(-40)
                make.width.height.equalTo(220)
            }
            replyLabel.snp.makeConstraints { make in
                make.top.equalTo(henView.snp.bottom).offset(20)
                make.leading.trailing.equalToSuperview().inset(32)
            }
        } else {
            // 母鸡没载进来，回应就自己站中间
            replyLabel.snp.makeConstraints { make in
                make.center.equalToSuperview()
                make.leading.trailing.equalToSuperview().inset(32)
            }
        }

    }

    /// "八月十六日 · 星期日"
    private func todayTitle() -> String {
        let names = ["日", "一", "二", "三", "四", "五", "六"]
        let index = Calendar.current.component(.weekday, from: Date()) - 1
        return ChineseDate.title() + "日 · 星期" + names[index]
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        henView?.pauseRendering()
    }

    // MARK: - 交互

    @objc private func closeTapped() {
        guard !isRecording else { return }
        textView.resignFirstResponder()
        onClose?()
        dismiss(animated: true)
    }

    // 记录:母鸡上台待机(盖住网络等待)→ 拿到结果她点头「记下了」→ 点完头才说话 → 收起
    @objc private func generateTapped() {
        let text = textView.text ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }


    

        enterRecordingMode()

        // Task:进入 async 世界,后台等 AI 结果(界面不卡,待机动画照播)
        Task {
            // 她至少要在台上待够这么久 —— 秒回的时候闪一下就没了,反而像出错
            let startedAt = DispatchTime.now()
            let minStageNanos: UInt64 = 800_000_000
            do {
                let item = try await viewModel.generate(content: text)
                await waitAtLeast(minStageNanos, since: startedAt)
                acknowledge(reply: item.reply)
            } catch {
                await waitAtLeast(minStageNanos, since: startedAt)
                handleGenerateFailure(error)
            }
        }
    }

    /// 「记下了」:她点一下头,点完再开口。
    ///
    /// 两件事分开是有意的 —— 点头是「我收到了」,说话是「我的回应」,
    /// 挤在一起就没有「她听完了」那个停顿。
    /// 点完头的信号来自 RiveHenView.onClipFinished(在 viewDidLoad 里接的)。
    private func acknowledge(reply: String?) {
        pendingReply = reply

        // .riv 里还没有 Nod、或者根本没载入成功 —— 不卡流程,直接说话
        guard let henView, henView.play(.nod) else {
            deliverReply()
            return
        }

        // 兜底:万一 Rive 的「播完」回调没来(动画配置有问题、渲染被打断),
        // 用户会被永远晾在这儿。卡死是最差的失败模式,宁可早一点说话。
        let timeout = (henView.duration(of: .nod) ?? 1.0) + 0.8
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            self?.deliverReply()
        }
    }

    /// 回调和兜底超时都会走到这儿,所以要幂等。
    private func deliverReply() {
        guard !didDeliverReply else { return }
        didDeliverReply = true

        showReply(pendingReply)
        pendingReply = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            self?.finishAndClose()
        }
    }
    
    private func waitAtLeast(_ minNanos: UInt64, since start: DispatchTime) async {
        let elapsed = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
        if elapsed < minNanos {
            try? await Task.sleep(nanoseconds: minNanos - elapsed)
        }
    }
    
    private func handleGenerateFailure(_ error: Error) {
        print("记录失败 \(error)")

        isRecording = false
        pendingReply = nil
        henView?.pauseRendering()
        henView?.isHidden = true
        replyLabel.isHidden = true
        textView.isHidden = false
        // 这三行原来漏了 —— enterRecordingMode 把卡片和按钮藏起来了,
        // 失败时不恢复,用户会对着一片空白,连原文都看不见
        cardShadow.isHidden = false
        generateButton.isHidden = false
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

    private func finishAndClose() {
        henView?.pauseRendering()
        onClose?()
        dismiss(animated: true)
    }
    

    // MARK: - 两种模式切换

    private func enterRecordingMode() {
        isRecording = true
        didDeliverReply = false
        textView.resignFirstResponder()
        textView.isHidden = true
        placeholderLabel.isHidden = true
        replyLabel.isHidden = true
        cardShadow.isHidden = true
        generateButton.isHidden = true
        generateButton.isEnabled = false   // 记录中禁止再点

        henView?.isHidden = false
        henView?.resumeRendering()         // Rive 开始渲染
        henView?.playIdle()
    }

    private func resetToInputMode() {
        isRecording = false
        didDeliverReply = false
        pendingReply = nil
        henView?.pauseRendering()
        henView?.isHidden = true
        replyLabel.isHidden = true
        textView.isHidden = false
        cardShadow.isHidden = false
        generateButton.isHidden = false
        generateButton.isEnabled = true
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
