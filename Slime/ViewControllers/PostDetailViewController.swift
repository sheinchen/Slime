//
//  PostDetailViewController.swift
//  Slime
//
//  详情页:展示被点中那只史莱姆对应的原帖正文 + 日期。
//  只显示、不查库 —— 数据由广场读好后经 ViewModel 传进来。
//

import UIKit
import SnapKit

final class PostDetailViewController: UIViewController {

    // 详情页的逻辑层。用 let,一进来就定,不再变。
    private let viewModel: PostDetailViewModel

    // 日期(小、次要)
    private let dateLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        return label
    }()

    // 正文。用只读 UITextView:内容长了能滚动,又不给编辑。
    private let contentTextView: UITextView = {
        let tv = UITextView()
        tv.font = .systemFont(ofSize: 18)
        tv.textColor = .label
        tv.isEditable = false
        tv.isScrollEnabled = true
        tv.backgroundColor = .clear
        return tv
    }()

    // MARK: - 初始化(依赖注入)

    // 自定义 init:必须把 viewModel 传进来才能创建这个页面
    init(viewModel: PostDetailViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)   // 纯代码创建,没有 xib
    }

    // 代码创建 VC 时用不到,但 UIViewController 要求实现,给个明确崩溃即可
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "详情"
        view.backgroundColor = .systemBackground
        setupUI()
        bind()   // 把 ViewModel 的数据灌进控件
    }

    // MARK: - 私有

    private func setupUI() {
        view.addSubview(dateLabel)
        view.addSubview(contentTextView)

        dateLabel.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(16)
            make.leading.trailing.equalToSuperview().inset(16)
        }
        contentTextView.snp.makeConstraints { make in
            make.top.equalTo(dateLabel.snp.bottom).offset(12)
            make.leading.trailing.equalToSuperview().inset(16)
            make.bottom.equalTo(view.safeAreaLayoutGuide).inset(16)
        }
    }

    // 从 ViewModel 取现成字符串填进界面。VC 不做任何格式化。
    private func bind() {
        dateLabel.text = viewModel.dateText
        contentTextView.text = viewModel.contentText
    }
}
