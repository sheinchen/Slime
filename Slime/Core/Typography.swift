import UIKit

/// 设计稿用的是霞鹜文楷（LXGW WenKai），iOS 上没有。
/// 系统里最接近的是楷体，退到衬线，再退到系统字 —— 一层层兜底，
/// 免得换了系统版本就掉回黑体。
enum Kai {
    /// 系统里可能存在的楷体名字，按偏好排。
    private static let candidates = [
        "STKaitiSC-Regular",
        "Kaiti SC",
        "STKaiti",
        "KaiTi",
    ]

    private static let resolved: String? = candidates.first { UIFont(name: $0, size: 12) != nil }

    static func font(_ size: CGFloat) -> UIFont {
        if let name = resolved, let font = UIFont(name: name, size: size) {
            return font
        }
        let base = UIFont.systemFont(ofSize: size, weight: .regular)
        if let serif = base.fontDescriptor.withDesign(.serif) {
            return UIFont(descriptor: serif, size: size)
        }
        return base
    }

    /// 带字距的一行字。设计稿标题是 letter-spacing:.03em。
    static func attributed(_ text: String, size: CGFloat, color: UIColor,
                           kern: CGFloat = 0, lineHeight: CGFloat? = nil) -> NSAttributedString {
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font(size),
            .foregroundColor: color,
        ]
        if kern != 0 { attrs[.kern] = kern }
        if let lineHeight {
            let style = NSMutableParagraphStyle()
            style.minimumLineHeight = lineHeight
            style.maximumLineHeight = lineHeight
            attrs[.paragraphStyle] = style
        }
        return NSAttributedString(string: text, attributes: attrs)
    }
}
