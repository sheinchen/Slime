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

/// 聊天页的配色。整屏只有母鸡和一串气泡，所以色带比别处更克制：
/// 两条（母鸡一条、你一条），各自从「实」渐到「几乎是背景色」。
enum ChatPalette {
    /// 页面底色，比首页天光更暖一点，衬得住满屏的黄
    static let background = UIColor(hex: 0xFDF8EA)

    /// 母鸡说的话：奶黄。near = 最新那条，far = 快飘出视野那条
    static let henNear = UIColor(hex: 0xFBE7AE)
    static let henFar = UIColor(hex: 0xFDF7E2)

    /// 你说的话：更饱和的橙黄，一眼能和她的分开
    static let userNear = UIColor(hex: 0xF9C95E)
    static let userFar = UIColor(hex: 0xFCEDC6)

    static let text = UIColor(hex: 0x5A4A33)
    static let textSoft = UIColor(hex: 0x9A8B72)

    /// 输入条
    static let inputField = UIColor(hex: 0xFFFFFF, alpha: 0.72)
    static let inputHint = UIColor(hex: 0xB5A98F)

    /// 颜色只由「离最新消息多远」决定 —— 不是 index/total。
    ///
    /// 按 index/total 算的话，每来一条新消息，所有旧气泡的颜色都要重算，
    /// 整屏会闪一下。按深度算，新消息进来时旧的是**渐渐褪色往上飘**，
    /// 这个变化本身有意义，也和顶部那层渐隐是同一套语言。
    ///
    /// depthSpan 条之外就全部淡到底，不再继续变。
    static func bubble(role: ChatRole, depth: Int) -> UIColor {
        let t = min(CGFloat(depth) / CGFloat(depthSpan), 1)
        let near = role == .user ? userNear : henNear
        let far = role == .user ? userFar : henFar
        return near.blended(to: far, t: t)
    }

    private static let depthSpan = 5
}

extension UIColor {
    /// 在两个颜色之间线性插值。t=0 全是自己，t=1 全是 other。
    func blended(to other: UIColor, t: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let k = max(0, min(1, t))
        return UIColor(red: r1 + (r2 - r1) * k,
                       green: g1 + (g2 - g1) * k,
                       blue: b1 + (b2 - b1) * k,
                       alpha: a1 + (a2 - a1) * k)
    }
}
