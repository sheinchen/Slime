import RiveRuntime
import UIKit

/// 母鸡本体：一个 Rive 画板。
///
/// 播放策略是「一条待机循环 + 偶尔插一段小动作」：
/// 平时循环 `Idle`，随机时刻插播一段 one-shot，播完自己回到 `Idle`。
/// 之所以不用状态机，是因为这个 .riv 里的两台状态机没有对外的 input，
/// 从代码侧点不动；直接按名字播时间线反而是能控的那条路。
final class RiveHenView: UIView {

    /// .riv 里实际存在的动画名（Rive 编辑器里就叫这些）。
    enum Clip: String, CaseIterable {
        /// 待机循环。
        case idle = "Idle"
        /// 啄草。
        case peck = "Peck"
        /// 转身。左转中再转回左，播完的那一刻水平翻面，就成了「转向另一边」。
        case turn = "Turn_Back"

        static let file = "Hen"
        /// 会被随机插播的小动作。转身不在里面 —— 那是走位需要时才播的。
        static let flourishes: [Clip] = [.peck]
    }

    private let viewModel: HenViewModel
    private let riveView: RiveView

    /// .riv 里真实存在的动画名，用来过滤配置里写错的名字 ——
    /// RiveViewModel.play 内部是 try!，播一个不存在的动画会直接崩。
    private let available: Set<String>
    /// 每条动画的时长，载入时一次性读出来。转身要靠它算中点。
    private let durations: [String: TimeInterval]

    /// 当前正在播的 one-shot。播完（Rive 回调 pause/stop）就清空并回到 idle。
    private(set) var playingClip: Clip?

    /// 主动暂停（退到后台）也会触发 pause 回调，那次不算「播完了」。
    private var suppressFinish = false

    // MARK: -

    /// 载入失败（.riv 没进 bundle、artboard 坏了）时返回 nil，
    /// 让调用方自己决定要不要降级，而不是在这里崩掉。
    static func make() -> RiveHenView? {
        guard let model = try? RiveModel(fileName: Clip.file),
              (try? model.setArtboard()) != nil,
              let artboard = model.artboard
        else { return nil }

        let available = Set(artboard.animationNames())
        // 每条动画建一个临时实例只为了读时长，读完就丢
        var durations: [String: TimeInterval] = [:]
        for name in available {
            if let instance = try? artboard.animation(fromName: name) {
                durations[name] = TimeInterval(instance.effectiveDurationInSeconds())
            }
        }
        return RiveHenView(model: model, available: available, durations: durations)
    }

    private init(model: RiveModel, available: Set<String>, durations: [String: TimeInterval]) {
        self.available = available
        self.durations = durations
        let start = available.contains(Clip.idle.rawValue) ? Clip.idle.rawValue : available.sorted().first

        viewModel = HenViewModel(model, animationName: start, fit: .contain, alignment: .bottomCenter)
        riveView = viewModel.createRiveView()

        super.init(frame: .zero)

        riveView.backgroundColor = .clear
        riveView.isOpaque = false
        riveView.layer.isOpaque = false
        riveView.isUserInteractionEnabled = false
        riveView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(riveView)
        NSLayoutConstraint.activate([
            riveView.leadingAnchor.constraint(equalTo: leadingAnchor),
            riveView.trailingAnchor.constraint(equalTo: trailingAnchor),
            riveView.topAnchor.constraint(equalTo: topAnchor),
            riveView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        backgroundColor = .clear
        isUserInteractionEnabled = false

        viewModel.onFinished = { [weak self] in self?.returnToIdle() }
        playIdle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - 播放

    func has(_ clip: Clip) -> Bool { available.contains(clip.rawValue) }

    /// 配置里写了但文件里没有的名字，在这里被挡掉。
    var flourishes: [Clip] { Clip.flourishes.filter(has) }

    var isBusy: Bool { playingClip != nil }

    /// 一段 one-shot 有多长。转身要靠它知道什么时候播完、该翻面了。
    func duration(of clip: Clip) -> TimeInterval? { durations[clip.rawValue] }

    func playIdle() {
        guard has(.idle) else { return }
        playingClip = nil
        viewModel.play(animationName: Clip.idle.rawValue, loop: .loop)
    }

    /// 插播一段 one-shot。播完会自动回 idle。
    @discardableResult
    func play(_ clip: Clip) -> Bool {
        guard has(clip) else { return false }
        playingClip = clip
        viewModel.play(animationName: clip.rawValue, loop: .oneShot)
        return true
    }

    private func returnToIdle() {
        guard !suppressFinish, playingClip != nil else { return }
        playIdle()
    }

    func pauseRendering() {
        suppressFinish = true
        viewModel.pause()
    }

    func resumeRendering() {
        suppressFinish = false
        if let clip = playingClip {
            viewModel.play(animationName: clip.rawValue, loop: .oneShot)
        } else {
            playIdle()
        }
    }
}

/// 只为了拿到「这一段播完了」这个信号。
///
/// one-shot 播到头时 RiveView 走的是 pause 分支而不是 stop，
/// 所以两个回调都接一下。
nonisolated private final class HenViewModel: RiveViewModel {
    var onFinished: (() -> Void)?

    override func player(pausedWithModel riveModel: RiveModel?) {
        onFinished?()
    }

    override func player(stoppedWithModel riveModel: RiveModel?) {
        onFinished?()
    }
}
