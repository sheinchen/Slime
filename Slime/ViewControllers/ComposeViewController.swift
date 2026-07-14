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

    private let viewModel = ComposeViewModel()

    // MARK: - UI 控件

    /// 多行输入框。
    private let textView: UITextView = {
        let tv = UITextView()
        tv.font = .systemFont(ofSize: 18)
        tv.textColor = .label
        tv.backgroundColor = .secondarySystemBackground
        tv.layer.cornerRadius = 12
        tv.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)
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

    /// 生成时中央出现的史莱姆,复用 SlimeView 组件。平时隐藏。
    private let slimeView: SlimeView = {
        let v = SlimeView()
        v.isHidden = true
        return v
    }()

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        setupNavigationBar()
        setupUI()
        textView.delegate = self
    }

    // 每次要显示时都回到"输入模式"(比如从广场返回后,重置成能继续写)
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        resetToInputMode()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // 只有输入模式才自动弹键盘
        if slimeView.isHidden {
            textView.becomeFirstResponder()
        }
    }

    // MARK: - 搭建 UI

    private func setupNavigationBar() {
        title = "写点什么"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "生成", style: .done, target: self, action: #selector(generateTapped)
        )
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "广场", style: .plain, target: self, action: #selector(squareTapped)
        )
    }

    private func setupUI() {
        view.backgroundColor = .systemBackground
        view.addSubview(textView)
        textView.addSubview(placeholderLabel)
        view.addSubview(slimeView)

        textView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(16)
            make.leading.trailing.equalToSuperview().inset(16)
            make.height.equalTo(240)
        }
        placeholderLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(16)
            make.leading.equalToSuperview().offset(16)
        }
        slimeView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.height.equalTo(180)
        }
    }

    // MARK: - 交互

    // 直接去广场(不生成)
    @objc private func squareTapped() {
        navigationController?.pushViewController(SquareViewController(), animated: true)
    }

    // 生成:VM 存数据并返回展示数据 → 播孵化揭晓 → 走进广场
    @objc private func generateTapped() {
        guard let item = viewModel.generate(content: textView.text) else { return }

        enterHatchingMode()
        slimeView.emotion = item.emotion

        // hatch 的 completion 由 SlimeView 在揭晓结束时回调;我们在这里接着走进广场
        slimeView.hatch { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                self?.goToSquare()
            }
        }
    }

    private func goToSquare() {
        navigationController?.pushViewController(SquareViewController(), animated: true)
    }

    // MARK: - 两种模式切换

    private func enterHatchingMode() {
        textView.resignFirstResponder()
        textView.isHidden = true
        placeholderLabel.isHidden = true
        slimeView.isHidden = false
        navigationItem.rightBarButtonItem?.isEnabled = false   // 孵化中禁止再点生成
    }

    private func resetToInputMode() {
        slimeView.isHidden = true
        textView.isHidden = false
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
