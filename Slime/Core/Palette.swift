import UIKit

/// 全部取自参考图。集中放一处，方便整体调色。
enum Palette {
    static let background = UIColor(hex: 0xFBF6EC)

    static let bodyLight = UIColor(hex: 0xFCE7B4)
    static let body = UIColor(hex: 0xFADFA0)
    static let bodyDeep = UIColor(hex: 0xF6D68C)
    static let wing = UIColor(hex: 0xF5D386)

    static let comb = UIColor(hex: 0xEE6D4B)
    static let tail = UIColor(hex: 0xF07C58)
    static let beak = UIColor(hex: 0xEE8B3D)
    static let beakDeep = UIColor(hex: 0xE07A2E)

    static let eye = UIColor(hex: 0x33302C)
    static let shadow = UIColor(white: 0, alpha: 0.075)

    static let grassTop = UIColor(hex: 0x8ECB44)
    static let grassSide = UIColor(hex: 0x6FAF32)
    static let grassTuft = UIColor(hex: 0x74B93A)

    static let nest = UIColor(hex: 0xE9B95F)
    static let nestDeep = UIColor(hex: 0xD9A44A)
    static let egg = UIColor(hex: 0xFDFBF4)
    static let eggShade = UIColor(hex: 0xEDE7D6)

    static let spark = UIColor(hex: 0xF0783C)
    static let ink = UIColor(hex: 0x4A453D)
    static let inkSoft = UIColor(hex: 0x9A9186)
}

/// 首页（设计稿 3a）的配色。天光是一整块很淡的渐变，
/// 上面浮两团几乎看不见的光晕 —— "清透感全部交给背景"。
enum Sky {
    static let top = UIColor(hex: 0xFEFCF4)
    static let mid = UIColor(hex: 0xFAF7E9)
    static let bottom = UIColor(hex: 0xF1F4E2)

    /// 左上的草绿光晕、右下的暖黄光晕。
    static let glowGreen = UIColor(red: 196 / 255, green: 229 / 255, blue: 120 / 255, alpha: 0.30)
    static let glowGold = UIColor(red: 250 / 255, green: 222 / 255, blue: 160 / 255, alpha: 0.34)

    /// 正文墨色。整页只有这一种字色，靠透明度分层次。
    static let ink = UIColor(hex: 0x4A3D2E)
    static func ink(_ alpha: CGFloat) -> UIColor { ink.withAlphaComponent(alpha) }

    /// 岛底下那团影子。
    static let islandShadow = UIColor(red: 120 / 255, green: 146 / 255, blue: 60 / 255, alpha: 0.40)
    /// 鸟巢上的提示圈。
    static let ring = UIColor(red: 242 / 255, green: 114 / 255, blue: 62 / 255, alpha: 0.55)
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
