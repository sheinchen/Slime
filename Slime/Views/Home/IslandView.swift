import UIKit

/// 浮在页面中间的那座草地小岛：草皮、鸟巢、提示圈，母鸡站在上面。
///
/// 整座岛（连同岛上的鸡）一起做 6.5 秒一轮的浮动 —— 这就是「草地的呼吸感」。
/// 母鸡挂在岛里而不是岛外，她才会跟着草一起起伏，而不是浮在草上面平移。
final class IslandView: UIView {

    /// 草皮图的原始尺寸，整座岛的坐标都按它算。
    static let size = CGSize(width: 330, height: 201)

    private let grass = UIImageView(image: UIImage(named: "grass"))
    private let nest = UIImageView(image: UIImage(named: "nest"))
    private let ring = CAShapeLayer()
    private let nestButton = UIButton(type: .custom)

    private(set) var hen: RiveHenView?
    private var wanderer = HenWanderer()

    /// 母鸡在岛上的可走范围（单位圆 → 岛坐标）。压在草皮顶面里，
    /// 往右下偏一点是为了给左上角的鸟巢让开。
    private let walkCenter = CGPoint(x: 0.57, y: 0.52)
    private let walkRadius = CGSize(width: 0.27, height: 0.20)

    /// 鸟巢中心（岛坐标归一化）。
    private let nestCenter = CGPoint(x: 0.27, y: 0.28)
    private let nestSize = CGSize(width: 92, height: 58)
    /// 画板比母鸡本身宽不少（周围留了空），所以这个框要比看到的鸡大一圈。
    private let henSize = CGSize(width: 155, height: 155)

    /// 母鸡身体中线在画框里的横向位置（0…1）。
    ///
    /// 翻面是绕这条线做的，所以它必须落在她**站立姿势的身体中线**上。
    /// 你已经在 Rive 里把她在画板中居中了，所以这里就是 0.5。
    /// 换了 .riv 之后如果翻面又开始横跳，先回 Rive 确认站姿是不是还在中线上。
    static let henBodyAnchorX: CGFloat = 0.5

    /// 翻面残留位移的补偿，单位 pt。
    ///
    /// 翻面掐在整段转身的哪个进度（0…1）—— 要正好是她**最背对镜头**的那一帧，
    /// 那时候左右最接近对称，镜像过去看不出接缝。
    /// 0.5 = 时间线正中间。如果你在 Rive 里把最背对那一帧挪了位置，这里跟着改。
    static let turnFlipProgress: TimeInterval = 0.5
    /// 播到这个进度就算转完。1.0 = 整段播完。
    static let turnUsefulProgress: TimeInterval = 1.0

    /// 她最背对时，身体在画板里横向偏出中线多少（pt）。**这是唯一要调的旋钮。**
    ///
    /// 镜像是绕中线翻的，所以她偏出去多少，翻面就会横移 2 倍。
    /// 填上这个值之后，转身期间会施加一个反向补偿把她钉在原地。
    ///
    /// 关键是这个补偿**只在转身期间生效**（见 `driftComp`）：
    /// 权重从转身起点的 0 涨到翻面那一刻的 1、再落回终点的 0，
    /// 所以她站着和走路时的位置完全不受影响，不会出现「朝左朝右站两个地方」。
    ///
    /// 0 = 不补。调法：跑起来盯她转身，往一边窜就往这里加，反向窜就减。
    /// 先试 ±5，再二分。Rive 里把漂移改小之后，这里也要跟着改小。
    static let turnDriftPeak: CGFloat = 3.5

    /// 母鸡当前画在鸟巢前面还是后面。只在换边时才真的动图层，不用每帧排序。
    private var henInFront = true

    /// 转身进行到第几秒。翻面掐在 `turnFlipProgress`，理由见 `advanceTurn`。
    private var turnElapsed: TimeInterval?
    private var turnLength: TimeInterval = 0
    private var didFlipThisTurn = false

    var onNestTap: (() -> Void)?
    var onHenTap: (() -> Void)?

    // MARK: -

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        grass.contentMode = .scaleAspectFit
        addSubview(grass)

        nest.contentMode = .scaleAspectFit
        addSubview(nest)

        ring.fillColor = UIColor.clear.cgColor
        ring.strokeColor = Sky.ring.cgColor
        ring.lineWidth = 2
        ring.opacity = 0
        layer.addSublayer(ring)

        if let hen = RiveHenView.make() {
            addSubview(hen)
            // 缩放/翻转都绕「脚底 + 身体中线」做：
            // y=1 让她站在地上而不是绕肚子转，x 决定镜像绕哪条竖线翻。
            hen.layer.anchorPoint = CGPoint(x: Self.henBodyAnchorX, y: 1)
            self.hen = hen
        }
        hen?.isUserInteractionEnabled = false

        nestButton.addTarget(self, action: #selector(nestTapped), for: .touchUpInside)
        addSubview(nestButton)
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(islandTapped))
        tap.cancelsTouchesInView = false
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize { Self.size }

    override func layoutSubviews() {
        super.layoutSubviews()

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        grass.frame = bounds

        let nestOrigin = CGPoint(x: bounds.width * nestCenter.x - nestSize.width / 2,
                                 y: bounds.height * nestCenter.y - nestSize.height / 2)
        nest.frame = CGRect(origin: nestOrigin, size: nestSize)

        // 提示圈从巢口起，往外扩到草地上 —— 收在巢里面的话，
        // 橙线压在橙色的巢上根本看不见。
        // frame 必须是圈自己的大小：脉冲是 transform.scale，
        // 挂在整座岛的 bounds 上会绕岛心放大，圈就飘走了。
        let ringRect = nest.frame.insetBy(dx: nestSize.width * 0.04, dy: nestSize.height * 0.03)
        ring.frame = ringRect
        ring.path = CGPath(ellipseIn: CGRect(origin: .zero, size: ringRect.size), transform: nil)

        // 点击热区比巢大一圈，保证够得着
        nestButton.frame = nest.frame.insetBy(dx: -10, dy: -14)

        hen?.bounds = CGRect(origin: .zero, size: henSize)

        CATransaction.commit()
    }

    // MARK: - 呼吸

    /// 岛的浮动 + 提示圈的脉冲。对应设计稿的 float3 / ringPulse。
    func startBreathing() {
        guard layer.animation(forKey: "float") == nil else { return }

        // 设计稿写的是 6.5s 一整轮，autoreverses 各占一半
        let half: CFTimeInterval = 3.25

        let rise = CABasicAnimation(keyPath: "transform.translation.y")
        rise.fromValue = 0
        rise.toValue = -13
        // 组里的子动画不写 duration 会退回 0.25s 默认值，整条呼吸就变成一下抽搐
        rise.duration = half

        let tilt = CABasicAnimation(keyPath: "transform.rotation.z")
        tilt.fromValue = -0.4 * CGFloat.pi / 180
        tilt.toValue = 0.4 * CGFloat.pi / 180
        tilt.duration = half

        let float = CAAnimationGroup()
        float.animations = [rise, tilt]
        float.duration = half
        float.autoreverses = true
        float.repeatCount = .infinity
        float.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(float, forKey: "float")

        startRingPulse()
    }

    func stopBreathing() {
        layer.removeAnimation(forKey: "float")
        ring.removeAnimation(forKey: "pulse")
    }

    private func startRingPulse() {
        guard ring.opacity > 0 else { return }

        let period: CFTimeInterval = 2.6

        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [0.86, 1.5, 1.5]
        scale.keyTimes = [0, 0.7, 1]
        scale.duration = period

        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0.85, 0, 0]
        fade.keyTimes = [0, 0.7, 1]
        fade.duration = period

        let pulse = CAAnimationGroup()
        pulse.animations = [scale, fade]
        pulse.duration = period
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ring.add(pulse, forKey: "pulse")
    }

    /// 今天还没写就一直提示，写完了就不再闪。
    func setNestHintVisible(_ visible: Bool) {
        ring.opacity = visible ? 1 : 0
        if visible {
            startRingPulse()
        } else {
            ring.removeAnimation(forKey: "pulse")
        }
    }

    // MARK: - 每帧

    func tick(dt: TimeInterval) {
        guard let hen, bounds.width > 1 else { return }

        let (frame, request) = wanderer.update(dt: dt)

        switch request {
        case .turn:
            beginTurn(hen)
        case .peck:
            if !hen.isBusy, let clip = hen.flourishes.randomElement() {
                hen.play(clip)
            }
        case nil:
            break
        }
        advanceTurn(dt: dt, hen: hen)

        let feet = point(for: frame.position)
        // 近大远小。等距视角下幅度必须很小，夸张了反而假。
        let depth = 0.93 + 0.12 * ((frame.position.y + 1) / 2)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hen.layer.position = CGPoint(x: feet.x - driftComp(facing: frame.facing, depth: depth),
                                     y: feet.y + frame.lift)
        hen.transform = CGAffineTransform(scaleX: frame.scaleX * depth,
                                          y: frame.scaleY * depth)
        CATransaction.commit()

        updateHenDepthOrder(feetY: feet.y)
    }

    // MARK: - 转身

    /// 转身期间把她钉在原地的横向补偿。不在转身中就是 0。
    ///
    /// 她的中心 = 落脚点 + 朝向 × 画板内偏移。翻面把朝向从 +1 扫到 -1，
    /// 偏移就被整个翻到另一边去 —— 这就是那段横移。
    /// 这里减掉一个同样大小的量，两边正好抵掉。
    /// 用连续的朝向值而不是它的正负号，`flipDuration` 那 0.16 秒里才抵得干净。
    private func driftComp(facing: CGFloat, depth: CGFloat) -> CGFloat {
        guard Self.turnDriftPeak != 0, let elapsed = turnElapsed, turnLength > 0 else { return 0 }
        let p = elapsed / turnLength
        let flip = Self.turnFlipProgress
        // 0 → 翻面那一刻 1 → 转完回 0，两头都用 smoothstep 软化
        let w: CGFloat = p <= flip
            ? smoothstep(0, CGFloat(flip), CGFloat(p))
            : 1 - smoothstep(CGFloat(flip), CGFloat(Self.turnUsefulProgress), CGFloat(p))
        return facing * Self.turnDriftPeak * w * depth
    }

    /// 播转身动画。文件里没有这一段（或播不动）就直接翻面，别把她卡在原地。
    private func beginTurn(_ hen: RiveHenView) {
        guard let length = hen.duration(of: .turn), length > 0, hen.play(.turn) else {
            wanderer.flipFacing()
            wanderer.turnDidFinish()
            return
        }
        turnElapsed = 0
        turnLength = length
        didFlipThisTurn = false
    }

    private func advanceTurn(dt: TimeInterval, hen: RiveHenView) {
        guard var elapsed = turnElapsed else { return }
        elapsed += dt
        turnElapsed = elapsed

        // 翻面必须发生在她背对镜头的那一帧 —— 那时候左右最接近对称，
        // 镜像过去看不出接缝。实测（把这条时间线慢放 12 秒逐帧量身体中心）：
        //
        //   进度 0.35  → 最背对，身体在画板里往右偏 +14.4pt
        //   进度 0.55  → 转回接近站姿，+4.6pt
        //   进度 0.80  → 又一次最背对，+15.1pt
        //
        // 也就是导出的 Turn_Back 里「转过去再转回来」发生了**两遍**，
        // 而且她背对时身体会在画板里往右滑 14~15pt。
        // 所以翻面掐在第一次最背对的 0.35，整段只用到 0.55 就当转完了 ——
        // 后面那半段是重复的，播完再翻就变成「转过去又转回来才改朝向」。
        if !didFlipThisTurn, elapsed >= turnLength * Self.turnFlipProgress {
            wanderer.flipFacing()
            didFlipThisTurn = true
        }

        if elapsed >= turnLength * Self.turnUsefulProgress {
            turnElapsed = nil
            if !didFlipThisTurn { wanderer.flipFacing() }
            wanderer.turnDidFinish()
        }
    }

    /// 单位圆坐标 → 岛上的落脚点。
    private func point(for unit: CGPoint) -> CGPoint {
        CGPoint(x: bounds.width * (walkCenter.x + unit.x * walkRadius.width),
                y: bounds.height * (walkCenter.y + unit.y * walkRadius.height))
    }

    /// 脚在巢底沿之下就走到巢前面，之上就退到巢后面。
    private func updateHenDepthOrder(feetY: CGFloat) {
        guard let hen else { return }
        let shouldBeInFront = feetY > nest.frame.maxY - 8
        guard shouldBeInFront != henInFront else { return }
        henInFront = shouldBeInFront
        if shouldBeInFront {
            insertSubview(hen, aboveSubview: nest)
        } else {
            insertSubview(hen, belowSubview: nest)
        }
        bringSubviewToFront(nestButton)
    }

    // MARK: -

    @objc private func nestTapped() {
        onNestTap?()

        let dip = CAKeyframeAnimation(keyPath: "transform.scale")
        dip.values = [1, 0.93, 1.02, 1]
        dip.keyTimes = [0, 0.28, 0.66, 1]
        dip.duration = 0.42
        dip.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        nest.layer.add(dip, forKey: "dip")

    }
    
    @objc private func islandTapped(_ g: UITapGestureRecognizer) {
        guard let hen else { return }
        let p = g.location(in: self)
        
        guard !nestButton.frame.contains(p) else { return }
        guard hen.frame.insetBy(dx: -10, dy: -10).contains(p) else { return }
        
        onHenTap?()
        
        let dip = CAKeyframeAnimation(keyPath: "transform.scale")
        dip.values = [1, 0.94, 1.03, 1]
        dip.keyTimes = [0, 0.28, 0.66, 1]
        dip.duration = 0.42
        dip.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        hen.layer.add(dip, forKey: "dip")
    }
}
