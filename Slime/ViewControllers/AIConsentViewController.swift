//
//  AIConsentViewController.swift
//  Slime
//

import UIKit
import SnapKit

/// 「让母鸡读你的日记」同意页。**不同意就用不了 App**，所以它不是弹窗，是整个根页面 ——
/// 没点同意之前，主界面根本不在窗口上，没有别的路能绕过去。
///
/// 为什么要有这一页：审核规则 5.1.2(i) 要求把个人数据交给第三方（明确点名了第三方 AI）之前，
/// 先讲清楚、再拿到明确许可。母鸡的所有 AI 能力都要把日记发出去，所以同意必须在第一次发之前。
///
/// 这一页**只负责显示**：同意存到哪、同意之后换哪个页面，都是组合根（SceneDelegate）的事，
/// 它只通过 `onAgree` 报告「用户点了同意」。
///
/// ⚠️ 页面上的每一句都是对用户的承诺。**发给 AI 的内容变了，这里要跟着改，
/// 同时把 `AIConsent.currentVersion` 加 1** —— 所有人会重新看到这一页。
final class AIConsentViewController: UIViewController {

    private let onAgree: () -> Void

    private let scrollView = UIScrollView()
    private let agreeButton = UIButton(type: .custom)

    init(onAgree: @escaping () -> Void) {
        self.onAgree = onAgree
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Sky.top

        setupFooter()
        setupContent()
    }

    // MARK: - 布局

    /// 底部固定的一块：按钮 + 一行小字。不跟着正文滚 —— 小屏上正文要滚好几屏，
    /// 按钮随时都得够得着。
    private func setupFooter() {
        agreeButton.setAttributedTitle(
            AppFont.attributed("同意并开始", size: 18, color: .white), for: .normal)
        agreeButton.backgroundColor = Palette.beak
        agreeButton.layer.cornerRadius = 26
        agreeButton.layer.cornerCurve = .continuous
        agreeButton.addTarget(self, action: #selector(agreeTapped), for: .touchUpInside)

        // 不放「不同意」按钮：不同意就是不用，点了也没地方可去。
        // 但要说清楚「离开是安全的」—— 没点同意之前，一个字都不会发出去（AIClient 那道闸保证的）
        let declineNote = UILabel()
        declineNote.numberOfLines = 0
        declineNote.textAlignment = .center
        declineNote.attributedText = AppFont.attributed(
            "不同意的话，直接离开就好 —— 什么都不会被发送。", size: 13, color: Sky.ink(0.4))

        let footer = UIView()
        footer.backgroundColor = Sky.top
        view.addSubview(footer)
        footer.addSubview(agreeButton)
        footer.addSubview(declineNote)

        footer.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
        }
        agreeButton.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(14)
            make.leading.trailing.equalToSuperview().inset(28)
            make.height.equalTo(52)
        }
        declineNote.snp.makeConstraints { make in
            make.top.equalTo(agreeButton.snp.bottom).offset(12)
            make.leading.trailing.equalToSuperview().inset(28)
            make.bottom.equalTo(view.safeAreaLayoutGuide).offset(-10)
        }

        // 正文滚到按钮上沿为止；上沿画一道极淡的线，提示「下面还有东西压着」
        view.addSubview(scrollView)
        scrollView.alwaysBounceVertical = true
        scrollView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.bottom.equalTo(footer.snp.top)
        }
        let divider = UIView()
        divider.backgroundColor = Sky.ink(0.08)
        footer.addSubview(divider)
        divider.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(0.5)
        }
    }

    private func setupContent() {
        let hen = UIImageView(image: UIImage(named: "hen_idle"))
        hen.contentMode = .scaleAspectFit
        hen.snp.makeConstraints { $0.size.equalTo(88) }

        let title = UILabel()
        title.numberOfLines = 0
        title.attributedText = AppFont.attributed(
            "让母鸡读你的日记", size: 28, color: Sky.ink, kern: 28 * 0.03)

        let stack = UIStackView(arrangedSubviews: [
            hen,
            title,
            paragraph("母鸡会读你写的日记：写完回你一句，把一天孵成一颗蛋，在合适的时候关心你，陪你聊天。这些都要把你写的内容交给 AI 来读。"),

            heading("会发出去的"),
            bullets([
                "你写的日记",
                "每颗蛋上那句一天的总结（母鸡关心你之前，要看看最近几天）",
                "和母鸡聊天时说的话，以及她为了接话翻出来的旧日记",
            ]),

            heading("发给谁"),
            paragraph("先经过母鸡自己的中转服务器（部署在 Cloudflare 上，只转发、不保存内容），再交给 DeepSeek（深度求索）的 AI 模型处理。DeepSeek 的服务在中国境内，它怎么处理这些内容，以它的隐私政策为准。"),

            heading("留在手机上的"),
            paragraph("日记、蛋和聊天记录都存在这台手机上。没有账号，母鸡也不会把它们上传到别处。只有用到上面那些功能时，相关的内容才会发出去。"),

            heading("随时可以撤回"),
            paragraph("首页右上角的设置里可以撤回。撤回之后母鸡不再发送任何内容；日记都还留在手机上，重新同意就能接着用。想彻底删掉，删除 App 就行。"),
        ])
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        // 小标题和上一段之间多空一点，一眼分得出是新的一节
        for view in stack.arrangedSubviews where view.tag == Self.headingTag {
            if let index = stack.arrangedSubviews.firstIndex(of: view), index > 0 {
                stack.setCustomSpacing(26, after: stack.arrangedSubviews[index - 1])
            }
        }
        stack.setCustomSpacing(18, after: hen)

        scrollView.addSubview(stack)
        // 文字块都撑满整行宽。alignment 是 .leading（母鸡要靠左、不被拉宽），
        // 这种对齐下多行 label 的宽度没人管，折不折行全看运气 —— 显式给个宽度最稳
        for view in stack.arrangedSubviews where view !== hen {
            view.snp.makeConstraints { $0.width.equalTo(stack) }
        }
        stack.snp.makeConstraints { make in
            // 贴 contentLayoutGuide = 决定「能滚多远」；宽度贴 frameLayoutGuide = 只能竖着滚
            make.top.equalTo(scrollView.contentLayoutGuide).offset(28)
            make.bottom.equalTo(scrollView.contentLayoutGuide).offset(-24)
            make.leading.trailing.equalTo(scrollView.contentLayoutGuide).inset(28)
            make.width.equalTo(scrollView.frameLayoutGuide).offset(-56)
        }
        // 顶部让开刘海 / 灵动岛
        scrollView.contentInsetAdjustmentBehavior = .always
    }

    // MARK: - 文字样式

    private static let headingTag = 1

    private func heading(_ text: String) -> UILabel {
        let label = UILabel()
        label.tag = Self.headingTag
        label.attributedText = AppFont.attributed(text, size: 18, color: Sky.ink)
        return label
    }

    private func paragraph(_ text: String) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.attributedText = AppFont.attributed(
            text, size: 16, color: Sky.ink(0.72), lineHeight: 16 * 1.55)
        return label
    }

    /// 一条一行，前面一个圆点。用多个 label 而不是一段带换行的字：
    /// 某一条折行时，第二行要和文字对齐，而不是顶到圆点底下。
    private func bullets(_ items: [String]) -> UIStackView {
        let rows = items.map { item -> UIView in
            let dot = UILabel()
            dot.attributedText = AppFont.attributed("·", size: 16, color: Sky.ink(0.5),
                                                    lineHeight: 16 * 1.55)
            // 两个都要顶到 required：hugging 管「别被拉宽」，compression 管「别被挤没」。
            // 只设前者的话，旁边那条字一长、想要更宽，Auto Layout 会把圆点压成 0 宽 ——
            // 模拟器上实测过，长的两条圆点直接消失了
            dot.setContentHuggingPriority(.required, for: .horizontal)
            dot.setContentCompressionResistancePriority(.required, for: .horizontal)
            let row = UIStackView(arrangedSubviews: [dot, paragraph(item)])
            row.axis = .horizontal
            row.alignment = .firstBaseline
            row.spacing = 8
            return row
        }
        let stack = UIStackView(arrangedSubviews: rows)
        stack.axis = .vertical
        stack.spacing = 6
        return stack
    }

    // MARK: - 动作

    @objc private func agreeTapped() {
        // 只认第一下：换根页面有一段淡入淡出，这期间连点会让组合根收到两次同意
        agreeButton.isEnabled = false
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        onAgree()
    }
}
