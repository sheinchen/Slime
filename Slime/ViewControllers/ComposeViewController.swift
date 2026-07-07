//
//  ComposeViewController.swift
//  Slime
//
//  输入页:写一句碎碎念 → 保存。切片 1 的"生成页"雏形。
//

import UIKit
import SnapKit

final class ComposeViewController: UIViewController {

    // MARK: - 依赖

    // VC 持有 ViewModel,保存逻辑都交给它。默认 new 一个,以后也能从外面注入。
    private let viewModel = ComposeViewModel()

    // MARK: - UI 控件

    /// 多行输入框。UITextView 支持多行、可滚动,适合写碎碎念。
    private let textView: UITextView = {
        let tv = UITextView()
        tv.font = .systemFont(ofSize: 18)
        tv.textColor = .label                 // 跟随深浅色模式的主文字色
        tv.backgroundColor = .secondarySystemBackground
        tv.layer.cornerRadius = 12
        tv.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)
        return tv
    }()

    /// 占位提示文字(UITextView 原生没有 placeholder,用一个 label 叠上去模拟)。
    private let placeholderLabel: UILabel = {
        let label = UILabel()
        label.text = "此刻想说点什么…"
        label.font = .systemFont(ofSize: 18)
        label.textColor = .tertiaryLabel
        return label
    }()

    // MARK: - 生命周期

    // viewDidLoad:界面加载进内存后调一次,是搭 UI、做初始化的标准时机
    override func viewDidLoad() {
        super.viewDidLoad()
        setupNavigationBar()
        setupUI()
        textView.delegate = self              // 让本类监听输入变化(控制 placeholder 显隐)
    }

    // 界面显示后让输入框自动聚焦、弹出键盘
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        textView.becomeFirstResponder()
    }

    // MARK: - 搭建 UI

    private func setupNavigationBar() {
        title = "写点什么"
        // 导航栏右上角放一个"保存"按钮,点击触发 saveTapped
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "保存",
            style: .done,
            target: self,
            action: #selector(saveTapped)
        )
        // 左上角"广场"按钮,push 到史莱姆广场
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "广场",
            style: .plain,
            target: self,
            action: #selector(squareTapped)
        )
    }

    // 跳到广场。push 进导航栈,顶部会自动出现返回按钮
    @objc private func squareTapped() {
        navigationController?.pushViewController(SquareViewController(), animated: true)
    }

    private func setupUI() {
        view.backgroundColor = .systemBackground
        view.addSubview(textView)
        textView.addSubview(placeholderLabel)

        // SnapKit 链式布局:输入框贴着安全区,四边留 16pt 边距
        textView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(16)
            make.leading.trailing.equalToSuperview().inset(16)
            make.height.equalTo(240)
        }

        // 占位文字放在输入框左上角(和文字起始位置对齐)
        placeholderLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(16)
            make.leading.equalToSuperview().offset(16)
        }
    }

    // MARK: - 交互

    // @objc:按钮 target-action 机制要求方法暴露给 Objective-C 运行时
    @objc private func saveTapped() {
        // VC 只把原始文字交给 ViewModel;去空白、空判断、存库都由 ViewModel 负责
        let didSave = viewModel.save(content: textView.text)
        guard didSave else { return }   // 没存成(空内容),界面不动

        // 存成功:清空输入框、恢复占位、收起键盘
        textView.text = ""
        placeholderLabel.isHidden = false
        textView.resignFirstResponder()
    }
}

// MARK: - UITextViewDelegate

extension ComposeViewController: UITextViewDelegate {
    // 输入内容变化时,有字就藏起占位文字,没字就显示
    func textViewDidChange(_ textView: UITextView) {
        placeholderLabel.isHidden = !textView.text.isEmpty
    }
}
