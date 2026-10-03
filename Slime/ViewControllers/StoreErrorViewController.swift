//
//  StoreErrorViewController.swift
//  Slime
//

import UIKit
import CoreData
import SnapKit
import SafariServices

/// 「日记本打不开了」—— 数据库打不开时的根页面（10-02 加）。
///
/// 以前库打不开是 `fatalError`：每次打开 App 都崩，用户连发生了什么都不知道，
/// 最容易做的事是删掉重装 —— 那才是真把日记删了。这一页要说清的就三件事：
/// **日记还在**、可能是什么原因、可以再试一次。
///
/// 跟同意页一样只负责显示：怎么重试、打开之后换哪一页，都是 SceneDelegate 的事。
final class StoreErrorViewController: UIViewController {

    /// 点「再试一次」。返回这次打开了没有：打开了，组合根会把这一页整个换掉；没打开，这一页说一声
    private let onRetry: () -> Bool
    private let error: Error

    private let scrollView = UIScrollView()
    private let retryButton = UIButton(type: .custom)
    private let statusLabel = UILabel()

    init(error: Error, onRetry: @escaping () -> Bool) {
        self.error = error
        self.onRetry = onRetry
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Sky.top
        setupButton()       // 先放按钮：正文的滚动区域滚到按钮上沿为止
        setupContent()
    }

    // MARK: - 布局

    private func setupContent() {
        let hen = UIImageView(image: UIImage(named: "hen_idle"))
        hen.contentMode = .scaleAspectFit
        hen.snp.makeConstraints { $0.size.equalTo(88) }

        let title = UILabel()
        title.numberOfLines = 0
        title.attributedText = AppFont.attributed("日记本打不开了", size: 28, color: Sky.ink, kern: 28 * 0.03)

        // 说「最常见」而不是「是因为」：空间不够只是最可能的一种，迁移失败、文件坏了也会走到这里
        let body = paragraph("你写过的日记都还在这台手机上，没有被删掉，只是这会儿读不出来。\n\n最常见的原因是手机存储空间不够了。去「设置 › 通用 › iPhone 存储空间」清出一些地方，再回来点下面的按钮。\n\n先别删掉 App —— 删掉的话，日记就真的没了。")

        statusLabel.numberOfLines = 0
        statusLabel.isHidden = true

        let contact = UIButton(type: .system)
        contact.setAttributedTitle(
            AppFont.attributed("一直打不开的话，告诉我一声 ›", size: 16, color: Palette.beak), for: .normal)
        contact.contentHorizontalAlignment = .leading
        contact.addTarget(self, action: #selector(openSupport), for: .touchUpInside)

        // 截图发过来时，这一行能告诉我是哪种打不开
        let code = UILabel()
        code.numberOfLines = 0
        code.attributedText = AppFont.attributed("出错信息：" + Self.describe(error), size: 12, color: Sky.ink(0.35))

        let stack = UIStackView(arrangedSubviews: [hen, title, body, statusLabel, contact, code])
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.setCustomSpacing(18, after: hen)
        stack.setCustomSpacing(20, after: body)

        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)
        scrollView.addSubview(stack)
        scrollView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(retryButton.snp.top).offset(-12)
        }
        // 多行 label 在 .leading 对齐的 stack 里宽度没人管，显式撑满（同意页踩过）
        for view in stack.arrangedSubviews where view !== hen {
            view.snp.makeConstraints { $0.width.equalTo(stack) }
        }
        stack.snp.makeConstraints { make in
            make.top.equalTo(scrollView.contentLayoutGuide).offset(40)
            make.bottom.equalTo(scrollView.contentLayoutGuide).offset(-24)
            make.leading.trailing.equalTo(scrollView.contentLayoutGuide).inset(28)
            make.width.equalTo(scrollView.frameLayoutGuide).offset(-56)
        }
    }

    /// 按钮固定在底部，正文再长也够得着
    private func setupButton() {
        retryButton.setAttributedTitle(AppFont.attributed("再试一次", size: 18, color: .white), for: .normal)
        retryButton.backgroundColor = Palette.beak
        retryButton.layer.cornerRadius = 26
        retryButton.layer.cornerCurve = .continuous
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        view.addSubview(retryButton)
        retryButton.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(28)
            make.height.equalTo(52)
            make.bottom.equalTo(view.safeAreaLayoutGuide).offset(-16)
        }
    }

    private func paragraph(_ text: String) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.attributedText = AppFont.attributed(text, size: 16, color: Sky.ink(0.72), lineHeight: 16 * 1.55)
        return label
    }

    /// 「NSCocoaErrorDomain 259 · SQLite 26」。
    /// SQLite 那个码最有用（13 = 磁盘满了、26 = 文件不是数据库），外层的 Core Data 码只说「打不开」。
    /// Core Data 把它放在 userInfo 的 `NSSQLiteErrorDomain` 键下，不在 `NSUnderlyingErrorKey` 里 ——
    /// 只读后者的话这一行永远只有外层那个（10-02 模拟器上看到的）
    private static func describe(_ error: Error) -> String {
        let outer = error as NSError
        var parts = ["\(outer.domain) \(outer.code)"]
        if let sqlite = outer.userInfo[NSSQLiteErrorDomain] as? Int {
            parts.append("SQLite \(sqlite)")
        } else if let inner = outer.userInfo[NSUnderlyingErrorKey] as? NSError {
            parts.append("\(inner.domain) \(inner.code)")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - 动作

    @objc private func retryTapped() {
        retryButton.isEnabled = false
        // 打开了的话组合根已经把这一页换下去了，下面这些对一个不在屏幕上的页面无害
        let opened = onRetry()
        retryButton.isEnabled = true
        guard !opened else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        statusLabel.attributedText = AppFont.attributed("还是没打开。", size: 16, color: Sky.ink)
        statusLabel.isHidden = false
    }

    @objc private func openSupport() {
        let safari = SFSafariViewController(url: AppLinks.support)
        safari.preferredControlTintColor = Palette.beak
        present(safari, animated: true)
    }
}
