import UIKit

/// 全 App 的字体：小赖字体（Xiaolai，SIL OFL 1.1，随包分发）。
/// 字体文件在 Resources/Fonts/，靠 Info.plist 的 UIAppFonts 在启动时注册；
/// 注册成功后按 PostScript 名 "Xiaolai" 就能取到。
enum AppFont {
    private static let name = "Xiaolai"

    static func font(_ size: CGFloat) -> UIFont {
        if let font = UIFont(name: name, size: size) {
            return font
        }
        // 取不到只可能是没打进包或 plist 没登记 —— 开发时直接叫出来，
        // 上线时退回系统字，不至于整页空白。
        assertionFailure("字体 \(name) 没注册上，检查 Info.plist 的 UIAppFonts 和 target 资源")
        return .systemFont(ofSize: size)
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
