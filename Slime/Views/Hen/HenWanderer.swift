import CoreGraphics
import Foundation

/// 母鸡在岛上的行为：站着呼吸 → 想去别处 → 需要的话先转身 → 走过去 → 再站着。
///
/// 「呼吸感」从三件事叠出来，缺一件就会露馅：
///
/// 1. **呼吸** —— 一条 4.7 秒的正弦，只改 ±1.5% 的高矮和不到 1pt 的高度。
///    幅度必须小到看不出是在动，只让人觉得她是活的。
/// 2. **缓慢挪动** —— 每隔几秒挑一个不远的落点，用 easeInOut 花三四秒滑过去。
///    关键是 easeInOut：起步和收尾都软，中间才有速度，看着才像「踱过去」。
/// 3. **随机小动作** —— 只在站定的时候插播，走路中途不打断。
///
/// 这里只算数、不碰视图。位置用单位圆坐标（-1...1）存，映射到屏幕在
/// `IslandView` 里做，这样换屏幕尺寸不用动任何行为参数。
struct HenWanderer {

    struct Config {
        /// 两次挪窝之间的间隔。
        var restBetweenStrolls: ClosedRange<TimeInterval> = 4.5...10.0
        /// 一次挪窝走多久。
        var strollDuration: ClosedRange<TimeInterval> = 2.6...4.6
        /// 一次挪窝走多远（占可走区域半径的比例）。刻意不大，她是在踱步不是在赶路。
        var strollDistance: ClosedRange<CGFloat> = 0.25...0.70
        /// 两次随机小动作之间的间隔。
        var betweenFlourishes: ClosedRange<TimeInterval> = 6.0...14.0
        /// 呼吸周期。
        var breathPeriod: TimeInterval = 4.7
        /// 呼吸的高矮变化幅度。
        var breathAmount: CGFloat = 0.015
        /// 横向移动超过这个距离才值得为它专门转一次身。
        var turnThreshold: CGFloat = 0.10
        /// 画板画的是朝左的鸡（鸡冠、喙、肉垂都在左边），所以不翻转时朝向是 -1。
        var authoredFacing: CGFloat = -1
        /// 翻面渐变的时长。**默认 0 = 瞬间翻，这是想要的行为。**
        ///
        /// 翻面靠 scaleX 从 +1 扫到 -1，中途必然经过 0，也就是宽度为零、
        /// 整只鸡消失。哪怕只有一两帧，看起来也是「闪一下」。
        ///
        /// 而翻面掐在她最背对镜头那一帧，左右本来就接近对称，
        /// 瞬间镜像看不出接缝 —— 没有渐变要摊的东西。
        /// 横移交给 `IslandView.turnDriftPeak` 从位置上抵掉，那才是对的地方。
        ///
        /// 真要开渐变的话，记得给 |scaleX| 加个下限，否则一定会闪。
        var flipDuration: TimeInterval = 0
    }

    /// 她想让上层替她做的事。上层负责去 Rive 里播对应的片段。
    enum Request {
        case peck
        case turn
    }

    /// 每帧交给视图的一份「她现在长什么样」。
    struct Frame {
        /// 单位圆坐标。
        var position: CGPoint
        /// 垂直方向的呼吸/走路起伏，单位 pt。
        var lift: CGFloat
        /// 横向缩放，含朝向（负数就是水平翻转）。
        var scaleX: CGFloat
        /// 当前朝向本身，-1…1 之间连续。翻面期间会平滑穿过 0，
        /// 位移补偿要跟着它走才抵得干净，不能只看正负号。
        var facing: CGFloat
        /// 纵向缩放，呼吸用。
        var scaleY: CGFloat
    }

    private enum Phase {
        case resting
        /// 等转身动画播完。这段时间她站着不动。
        case turning
        case strolling
    }

    var config = Config()

    private(set) var position: CGPoint
    private var origin: CGPoint
    private var target: CGPoint

    private var clock: TimeInterval = 0
    private var phase: Phase = .resting
    private var strollElapsed: TimeInterval = 0
    private var strollLength: TimeInterval = 0

    private var restTimer: TimeInterval
    private var flourishTimer: TimeInterval

    /// 逻辑朝向，只有 ±1。翻面的时机由上层掐在转身动画的中点，
    /// 那一帧她正好转成对称的背面，翻过去看不出接缝。
    private var facing: CGFloat = 1
    /// 画面上正在用的朝向，会花 `flipDuration` 从旧值滑到 `facing`。
    private var renderedFacing: CGFloat = 1

    init(start: CGPoint = .zero) {
        position = start
        origin = start
        target = start
        restTimer = TimeInterval.random(in: 1.5...4.0)
        flourishTimer = TimeInterval.random(in: 3.0...7.0)
    }

    // MARK: -

    /// 推进一帧。返回这一帧的样子，以及（如果有）要上层去播的片段。
    mutating func update(dt: TimeInterval) -> (frame: Frame, request: Request?) {
        clock += dt
        var request: Request?

        switch phase {
        case .strolling:
            strollElapsed += dt
            let t = min(CGFloat(strollElapsed / strollLength), 1)
            let eased = Ease.easeInOut.apply(t)
            position = CGPoint(x: lerp(origin.x, target.x, eased),
                               y: lerp(origin.y, target.y, eased))
            if t >= 1 {
                phase = .resting
                restTimer = TimeInterval.random(in: config.restBetweenStrolls)
            }

        case .turning:
            break  // 站着等，由 turnDidFinish() 放行

        case .resting:
            restTimer -= dt
            if restTimer <= 0 {
                origin = position
                target = pickTarget(from: position)
                strollElapsed = 0
                strollLength = TimeInterval.random(in: config.strollDuration)

                // 要往反方向走就先转身，转完再迈步
                let dx = target.x - origin.x
                if abs(dx) > config.turnThreshold, (dx > 0 ? 1 : -1) != facingDirection {
                    phase = .turning
                    request = .turn
                } else {
                    phase = .strolling
                }
            }
        }

        // 小动作只在站定时插播，走一半或转一半被打断都很奇怪
        flourishTimer -= dt
        if flourishTimer <= 0 {
            if phase == .resting, request == nil {
                request = .peck
                flourishTimer = TimeInterval.random(in: config.betweenFlourishes)
            } else {
                flourishTimer = 0.5  // 还忙着，等一下再问
            }
        }

        advanceFlip(dt: dt)
        return (makeFrame(), request)
    }

    /// 把镜像摊到 `flipDuration` 里走完。中间会经过一个被压扁的瞬间，
    /// 叠在转身动画上正好读成「转过去」。
    private mutating func advanceFlip(dt: TimeInterval) {
        guard renderedFacing != facing else { return }
        let step = CGFloat(dt / max(config.flipDuration, 0.001)) * 2
        renderedFacing = facing > renderedFacing
            ? min(renderedFacing + step, facing)
            : max(renderedFacing - step, facing)
    }

    /// 她现在面朝哪边（+1 右 / -1 左），跟画板原本的朝向无关。
    private var facingDirection: CGFloat { facing * config.authoredFacing }

    /// 转身动画播到中点时调用 —— 就是这一下把她翻到另一边。
    mutating func flipFacing() {
        facing *= -1
    }

    /// 转身动画播完了，可以迈步了。
    mutating func turnDidFinish() {
        guard phase == .turning else { return }
        phase = .strolling
    }

    /// 在可走区域里挑一个不太远、也不要原地打转的落点。
    private func pickTarget(from p: CGPoint) -> CGPoint {
        for _ in 0..<10 {
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let distance = CGFloat.random(in: config.strollDistance)
            let candidate = CGPoint(x: p.x + cos(angle) * distance,
                                    y: p.y + sin(angle) * distance)
            if candidate.x * candidate.x + candidate.y * candidate.y <= 1 {
                return candidate
            }
        }
        // 十次都撞边就往圆心收一点，总比卡在边上强
        return CGPoint(x: p.x * 0.4, y: p.y * 0.4)
    }

    private func makeFrame() -> Frame {
        let breath = CGFloat(sin(clock * 2 * .pi / config.breathPeriod))

        // 走路时多一层高频的轻微起伏，落脚感
        var lift = breath * 0.7
        if phase == .strolling {
            let progress = strollElapsed / max(strollLength, 0.001)
            lift -= abs(CGFloat(sin(progress * .pi * 6))) * 1.6
        }

        return Frame(
            position: position,
            lift: lift,
            scaleX: renderedFacing * (1 - breath * config.breathAmount * 0.6),
            facing: renderedFacing,
            scaleY: 1 + breath * config.breathAmount
        )
    }
}
