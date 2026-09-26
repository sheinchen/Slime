//
//  DiaryCardStackView.swift
//  Slime
//
//  一天的日记叠成一摞，但平时只看得到最上面那张。
//  把它往任一边拖走，下一篇就在原来的位置；拖走的那篇排到最后 ——
//  首尾相接，一直循环。
//
//  这不是列表，是一个带手势的自定义 view（跟 SlimeView / EggView 一类），
//  所以没用 UICollectionView：同时只有最上面那张能动，
//  没有滚动、没有复用，collectionView 那套在这里全是负担。
//

import UIKit
import SnapKit

final class DiaryCardStackView: UIView, UIGestureRecognizerDelegate {

    // MARK: - 手感

    /// 横着拖过卡宽的这个比例，松手就算抽走
    private static let commitRatio: CGFloat = 0.3
    /// 拖满一整张卡宽时最多歪多少。只给一点点，让它像被手推着走，不是被拎起来甩
    private static let maxTilt: CGFloat = .pi / 90

    // MARK: - 对外

    /// 最上面换成了第几篇（在 entries 里的下标），给页码点用
    var onTopChange: ((Int) -> Void)?
    /// 编辑模式下点了卡片左上角的叉。真正删数据是 VC → VM 的事，这里只负责报上去
    var onDelete: ((SlimeItem) -> Void)?

    /// 编辑模式：像桌面删 App —— 长按，卡片抖起来、左上角出叉，点叉删。
    /// 点卡片别处、换一天、这天删光了都会退出。编辑模式下照样能横拖翻卡，
    /// 翻上来的下一张也在抖、也有叉，可以连着删。
    private(set) var isEditing = false

    // MARK: - 状态

    private var entries: [SlimeItem] = []
    /// 叠放顺序，`[0]` 是最上面那张。所有卡都叠在同一个位置
    private var cards: [DiaryCardView] = []
    /// 正在飞出去的卡。它在数组里已经排到最后了，但位置还归飞出动画管，
    /// 摆放其他卡时要跳过它，不然动画播到一半会被拽回原位
    private var flying: Set<ObjectIdentifier> = []

    private lazy var pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
    private lazy var longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
    /// 编辑模式下点卡片（叉以外的地方）退出。平时关着，免得跟别的点击抢
    private lazy var exitTap = UITapGestureRecognizer(target: self, action: #selector(handleExitTap))

    private var isDragging: Bool {
        pan.state == .began || pan.state == .changed
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        // delegate 必须挂 —— 方向过滤写在 gestureRecognizerShouldBegin 里，
        // 而那个方法只有作为**手势 delegate** 时才会被调到。详见那个方法上的注释
        pan.delegate = self
        addGestureRecognizer(pan)
        // 长按不会跟横拖打架：长按要求手指不动，一动就失败，拖动才开始
        addGestureRecognizer(longPress)
        exitTap.isEnabled = false
        addGestureRecognizer(exitTap)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - 装数据

    /// - Parameter startOver: 换了一天传 true，按时间顺序从第一篇重新排。
    ///   同一天里的变化（删了一篇、数据在别处刷新）传 false ——
    ///   保留当前的顺序，你正看着的那张还在最上面。
    func configure(_ entries: [SlimeItem], startOver: Bool) {
        self.entries = entries
        // 换了一天就退出编辑模式 —— 桌面上翻到别的页不会退，但这里换天等于换了一摞牌
        if startOver { setEditing(false) }
        let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        let existing = Dictionary(uniqueKeysWithValues: cards.map { ($0.item.id, $0) })

        let order: [UUID]
        if startOver {
            order = entries.map(\.id)
        } else {
            // 原来的顺序里去掉删了的，新出现的排在最后
            let kept = cards.map(\.item.id).filter { byID[$0] != nil }
            let added = entries.map(\.id).filter { existing[$0] == nil }
            order = kept + added
        }

        // 不在新顺序里的卡：删了的淡出，换天的直接拿掉
        for card in cards where byID[card.item.id] == nil {
            // 飞行中的交给飞完的回调收尾，这里再动它会和动画打架
            guard !flying.contains(ObjectIdentifier(card)) else { continue }
            if startOver {
                card.removeFromSuperview()
            } else {
                // 删掉的：缩小着淡出，跟桌面上删 App 一个感觉
                UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseIn) {
                    card.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
                    card.alpha = 0
                } completion: { _ in
                    card.removeFromSuperview()
                }
            }
        }

        cards = order.compactMap { id in
            guard let item = byID[id] else { return nil }
            if let card = existing[id] {
                card.configure(item)
                if startOver { card.scrollToTop() }
                return card
            }
            let card = makeCard(item)
            // 新卡先透明，下面统一淡到它该有的样子
            card.alpha = 0
            return card
        }

        // 编辑模式下删了一篇：还在编辑，新冒上来的卡也得抖起来。删光了就退出
        if cards.isEmpty { setEditing(false) }
        cards.forEach { $0.setEditing(isEditing, animated: false) }

        restack()
        if startOver {
            placeCards()
        } else {
            // 删掉的是最上面那张时，下一张在这里淡出来
            UIView.animate(withDuration: 0.25) {
                self.placeCards()
            }
        }
        reportTop()
    }

    private func makeCard(_ item: SlimeItem) -> DiaryCardView {
        let card = DiaryCardView(item: item)
        addSubview(card)
        card.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        // 卡片里的全文要能竖着滚，但横着拖得归这摞牌。
        // 做法跟周条那里一样：让滚动**等横拖手势先判定** ——
        // 竖着拖时横拖手势立刻失败，滚动马上接管；横着拖时滚动一点都不动。
        card.scrollPan.require(toFail: pan)
        card.onDeleteTap = { [weak self, weak card] in
            guard let self, let card else { return }
            self.onDelete?(card.item)
        }
        return card
    }

    // MARK: - 摆放

    /// 按 cards 的顺序调整 subview 的上下层：UIKit 里后面的 subview 盖在前面的上面。
    /// 飞行中的卡永远最上层，直到它飞出屏幕。
    private func restack() {
        for card in cards.reversed() {
            bringSubviewToFront(card)
        }
        for card in subviews.compactMap({ $0 as? DiaryCardView })
        where flying.contains(ObjectIdentifier(card)) {
            bringSubviewToFront(card)
        }
    }

    /// 最上面那张显示，其余全部藏起来。
    ///
    /// 第二张平时也藏着：它和最上面那张完全重合，亮着也看不见，
    /// 只会让两层影子叠出一圈更深的边。拖动开始时才把它亮出来垫在底下。
    private func placeCards() {
        for (index, card) in cards.enumerated() where !flying.contains(ObjectIdentifier(card)) {
            card.transform = .identity
            card.alpha = index == 0 ? 1 : 0
            // 只有最上面那张能碰（滚全文）
            card.isUserInteractionEnabled = index == 0
        }
    }

    private func reportTop() {
        guard let top = cards.first,
              let index = entries.firstIndex(where: { $0.id == top.item.id }) else { return }
        onTopChange?(index)
    }

    // MARK: - 拖动

    /// 只接横着的拖，竖着拖留给卡片里的全文滚动。这是抽卡和滚正文的分工线。
    ///
    /// ⚠️ **光写这个方法没用，init 里必须同时 `pan.delegate = self`。**
    /// `UIView` 和 `UIGestureRecognizerDelegate` 上各有一个同名同签名的方法，
    /// 在 UIView 子类里它们是同一个选择器 —— 所以这里只能写 `override`
    /// （写进扩展里会报「requires an 'override' keyword」，而扩展又不许 override）。
    /// 但 `override` 只保证它能作为**代理方法**被调到；作为 UIView 自己那个方法，
    /// 实测一次都不会被调。没挂 delegate 时它就是一段死代码：能编译、不报错、不警告。
    ///
    /// 漏掉的后果不是「横拖失灵」（那样立刻就发现了），而是这个 pan 把**所有**方向的
    /// 拖动都吃掉，再配上 `scrollPan.require(toFail: pan)`，正文就永远滚不起来。
    /// 日记短的时候本来就没得滚，所以这个洞能一直藏着。
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === pan else {
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }
        let velocity = pan.velocity(in: self)
        return !cards.isEmpty && abs(velocity.x) > abs(velocity.y)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let top = cards.first else { return }
        let translation = gesture.translation(in: self)
        let width = max(bounds.width, 1)

        switch gesture.state {
        case .began:
            // 下一篇亮出来，在原位等着
            if cards.count > 1 {
                cards[1].alpha = 1
            }

        case .changed:
            guard cards.count > 1 else {
                // 只有一张：抽走了底下也还是它，干脆拖不动，给点阻尼让你知道到头了
                top.transform = CGAffineTransform(translationX: translation.x * 0.2, y: 0)
                return
            }
            top.transform = dragTransform(translation.x, width: width)

        case .ended, .cancelled:
            let velocity = gesture.velocity(in: self)
            // 拖得够远，或者朝同一个方向甩得够快，都算抽走
            let farEnough = abs(translation.x) > width * Self.commitRatio
            let flungOut = abs(velocity.x) > 700 && velocity.x * translation.x > 0
            if gesture.state == .ended, cards.count > 1, farEnough || flungOut {
                flyAway(top, translation: translation, velocity: velocity)
            } else {
                snapBack(top)
            }

        default:
            break
        }
    }

    /// 只跟横向，竖直方向锁死 —— 卡片贴着原来那条线平移，不会被拖得上下飘
    private func dragTransform(_ x: CGFloat, width: CGFloat) -> CGAffineTransform {
        CGAffineTransform(translationX: x, y: 0).rotated(by: x / width * Self.maxTilt)
    }

    private func snapBack(_ card: DiaryCardView) {
        // 阻尼给高，回到原位就停，不来回弹
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.95,
                       initialSpringVelocity: 0) {
            card.transform = .identity
        } completion: { _ in
            // 等它盖回去了再把第二张藏起来 —— 先藏的话，没盖住的那一截会闪一下空白。
            // 回弹期间又开始拖了就别动，第二张正垫着用
            guard !self.isDragging else { return }
            self.placeCards()
        }
    }

    /// 抽走最上面那张。
    ///
    /// **数组顺序在动画开始前就改好**，不等飞完 —— 飞行那零点几秒里你可能已经
    /// 开始拖下一张了，那时候 `cards[0]` 必须已经是下一张。
    private func flyAway(_ card: DiaryCardView, translation: CGPoint, velocity: CGPoint) {
        let direction: CGFloat = translation.x >= 0 ? 1 : -1
        flying.insert(ObjectIdentifier(card))
        cards.removeFirst()
        cards.append(card)
        // 下一张早在拖动开始时就亮着垫在底下了，这里只是把它认作新的最上面那张
        placeCards()
        reportTop()

        // 沿水平线滑出去，刚好出屏幕就够
        // （卡片离屏幕边还有 22 的缩进，多给 60 保证连影子一起出去）
        let distance = bounds.width + 60
        // 甩得越快滑得越快，但不低于 0.18 秒，不然像是瞬移
        let speed = max(abs(velocity.x), 1400)
        let duration = min(max(TimeInterval((distance - abs(translation.x)) / speed), 0.18), 0.3)

        UIView.animate(withDuration: duration, delay: 0, options: .curveEaseOut) {
            card.transform = self.dragTransform(direction * distance, width: self.bounds.width)
        } completion: { _ in
            self.flying.remove(ObjectIdentifier(card))
            self.tuckUnder(card)
        }
    }

    /// 飞出去的那张回到原位，排到最后，藏起来等下次轮到它
    private func tuckUnder(_ card: DiaryCardView) {
        // 飞的时候这篇被删了（或者换了一天）—— 不用回来了
        guard let index = cards.firstIndex(where: { $0 === card }) else {
            card.removeFromSuperview()
            return
        }
        card.scrollToTop()
        restack()
        card.transform = .identity
        card.isUserInteractionEnabled = index == 0
        // 一般是藏起来；但只剩两篇、而你已经在拖下一张时，它正好是垫在底下的那张
        card.alpha = index == 0 || (index == 1 && isDragging) ? 1 : 0
    }
}

// MARK: - 编辑模式

extension DiaryCardStackView {

    /// 进出编辑模式。所有卡一起切 —— 藏在底下的也切，翻上来时就已经在抖了。
    func setEditing(_ editing: Bool) {
        guard editing != isEditing else { return }
        isEditing = editing
        exitTap.isEnabled = editing
        cards.forEach { $0.setEditing(editing, animated: true) }
    }

    @objc fileprivate func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, !isEditing, !cards.isEmpty else { return }
        // 桌面上长按进抖动模式也是这一下
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        setEditing(true)
    }

    /// 点叉不会走到这里：父 view 上的单击手势碰上按钮，UIKit 让按钮优先
    @objc fileprivate func handleExitTap() {
        setEditing(false)
    }
}
