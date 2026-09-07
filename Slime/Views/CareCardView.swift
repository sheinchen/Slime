//
//  CareCardView.swift
//  Slime
//

import UIKit
import SnapKit

/// 首页顶部滑出的关怀卡片。
///
/// **纯只读**：没有按钮、不接受点击、不能回应 —— 这是明确的产品选择，不是待办。
///
/// 它也不知道自己为什么会出现：拿到的 `PendingCare` 里只有 id / text / createdAt，
/// **没有 referencedDates**。「绝不暴露判断依据」这条铁律在数据结构上就锁死了，
/// 这个 view 想漏也漏不出来。
final class CareCardView: UIView {

    private let mark = UILabel()      // 一枚小小的「咕」，表明这是母鸡说的
    private let quote = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        // 用聊天页母鸡那条色带的奶黄，让「母鸡说话」在两个页面是同一种语言
        backgroundColor = ChatPalette.henNear
        layer.cornerRadius = 20
        layer.cornerCurve = .continuous

        // 很轻的一层影子，让卡片浮在天光上而不是贴上去
        layer.shadowColor = UIColor(hex: 0x8A7A5A).cgColor
        layer.shadowOpacity = 0.13
        layer.shadowRadius = 14
        layer.shadowOffset = CGSize(width: 0, height: 6)

        // 卡片本身不接受任何触摸 —— 点它等于点到了它下面的天空
        isUserInteractionEnabled = false

        mark.attributedText = Kai.attributed("咕", size: 13, color: Sky.ink(0.34))
        quote.numberOfLines = 0

        addSubview(mark)
        addSubview(quote)

        mark.snp.makeConstraints {
            $0.top.equalToSuperview().inset(16)
            $0.leading.equalToSuperview().inset(20)
        }
        quote.snp.makeConstraints {
            $0.top.equalTo(mark.snp.bottom).offset(5)
            $0.leading.trailing.equalToSuperview().inset(20)
            $0.bottom.equalToSuperview().inset(18)
        }
    }

    // MARK: - 内容

    func setText(_ text: String) {
        quote.attributedText = Kai.attributed(text, size: 17,
                                              color: Sky.ink(0.82),
                                              lineHeight: 17 * 1.55)
    }

    // MARK: - 单次露面的进退场
    //
    // ⚠️ 这两个方法只管**这一次露面**，跟关怀本身的寿命无关。
    //    fadeOut 之后 CareMessage 还是 shown，下次进首页会再滑出来。
    //    什么时候真正退场，由 CareEngine 的两条规则说了算。

    /// 滑出。延迟一点点，让首页先安顿下来，别和岛的呼吸抢注意力。
    func slideIn() {
        isHidden = false
        alpha = 0
        transform = CGAffineTransform(translationX: 0, y: -14)
        UIView.animate(withDuration: 0.55, delay: 0.4,
                       usingSpringWithDamping: 0.84, initialSpringVelocity: 0,
                       options: [.allowUserInteraction]) {
            self.alpha = 1
            self.transform = .identity
        }
    }

    /// 淡出。用户一开始操作页面就走，不挡路。
    func fadeOut(completion: (() -> Void)? = nil) {
        // 还没滑完就被打断的话，把在途的动画掐掉，否则会跳一下
        layer.removeAllAnimations()
        UIView.animate(withDuration: 0.26, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.alpha = 0
            self.transform = CGAffineTransform(translationX: 0, y: -10)
        } completion: { _ in
            self.isHidden = true
            completion?()
        }
    }
}
