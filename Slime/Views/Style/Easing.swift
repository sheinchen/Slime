import CoreGraphics
import Foundation

/// 缓动曲线。动画"像 Rive"还是"像 CSS"的分水岭基本就在这里 ——
/// 关键帧之间绝不用线性插值。
enum Ease {
    case linear
    case easeIn
    case easeOut
    case easeInOut

    func apply(_ t: CGFloat) -> CGFloat {
        let t = min(max(t, 0), 1)
        switch self {
        case .linear:
            return t
        case .easeIn:
            return t * t * t
        case .easeOut:
            let f = 1 - t
            return 1 - f * f * f
        case .easeInOut:
            return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
        }
    }
}

@inline(__always)
func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
    a + (b - a) * t
}

/// 两端平滑的 0→1 过渡。用于把补偿量渐入渐出，不留折角。
@inline(__always)
func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
    let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
    return t * t * (3 - 2 * t)
}
