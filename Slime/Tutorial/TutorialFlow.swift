//
//  TutorialFlow.swift
//  Slime
//
//  示范教程的剧本：有哪几步、每一步等什么、屏幕上露出哪里、母鸡说什么。
//
//  全是纯函数（`TutorialFlowTests` 锁着）。真正去压暗屏幕、找按钮在哪、等几秒再换下一步的，
//  是 `TutorialCoordinator` —— 它只照着这里演，自己不做任何判断。
//
//  示范用的是**真页面 + 内存里的假数据**（见 `TutorialAssembly`）：
//  用户按的鸟巢、「收好」、按住母鸡、拖卡片、下拉月历、长按删除，全是以后每天用的那几个手势；
//  但写的、孵的、删的都不进数据库，也不发给 AI，示范一结束就跟着扔掉。
//

import Foundation

/// 示范的每一步。顺序就是剧本的顺序。
nonisolated enum TutorialStep: Equatable, CaseIterable {
    case intro
    // —— 写 ——
    case tapNest
    /// 等：预设那篇一个字一个字打出来
    case typing
    case tapSave
    /// 等：母鸡点头、回一句、自己收起
    case henReplying
    // —— 孵 ——
    case tapCalendar
    case pressHen
    /// 等：蛋孵出来
    case hatching
    case eggExplained
    // —— 看 ——
    case flipCard
    /// 周条往右滑，翻到上一周。
    ///
    /// 「点一天」**只在月历里教一次**（`pickInMonth`）。10-02 删掉了周条上的那次 ——
    /// 两次都是「点一颗蛋 → 看那天」，教重了。留月历那次：点完日子跳过去、月历自己收起，
    /// 「选一天」和「从月历回来」一下就都会了，删除也接着在那天上做
    case swipeWeek
    case pullMonth
    /// 月历拉下来了，左右滑翻月
    case swipeMonth
    /// 翻过月了，等点一天
    case pickInMonth
    /// 翻过月之后又把月历推回去了（或者在月历里点了一天、月历先收起）—— 再拉下来点一天就行，不用重新翻月
    case repullMonth
    /// 月历里点的那天删不了（今天，或者空的那天）—— 换一天
    case pickDayToDelete
    // —— 删 ——
    case longPress
    case tapDelete
    /// 等：删完那天的蛋重孵
    case rehatching
    case rehatchExplained
    case outro
    case finished
}

/// 页面上发生的、示范关心的事。
nonisolated enum TutorialEvent: Equatable {
    case continueTapped
    case skipTapped
    case composeOpened
    case presetTyped
    case diarySaved
    case composeClosed
    case pageChanged(Int)
    case laidEgg
    case eggHatched
    /// 没孵出来。剧本 AI 不会失败，正常走不到；真走到了要退回「按住我」，
    /// 不然停在「等」那一步 —— 蒙层挡着所有点击，人就被卡死在示范里
    case hatchFailed
    case flippedCard
    /// 手指滑到了另一周 / 另一个月，松手停稳了（拖到一半弹回去、代码跳页都不算）
    case swipedWeek
    case swipedMonth
    /// - Parameters:
    ///   - entryCount: 那天有几篇
    ///   - fromMonth: 是在月历里点的（不是周条）
    case pickedDay(isToday: Bool, entryCount: Int, fromMonth: Bool)
    case monthExpanded(Bool)
    case editingChanged(Bool)
    case deletedEntry
    case rehatched
}

/// 示范要露出来的那几样东西。rawValue 就是真页面上那个 view 的 `accessibilityIdentifier` ——
/// 协调者按这个名字去窗口里找，不用每个页面都为示范开一个口子。
///
/// ⚠️ 改名要两边一起改：这里，和设 identifier 的那个页面（每个 case 后面写着在哪）。
nonisolated enum TutorialAnchor: String, CaseIterable {
    case nest = "home.nest"                 // IslandView.nestButton
    case composeSave = "compose.save"       // ComposeViewController.generateButton
    case calendarTab = "tab.1"              // FloatingTabBar 的第 2 个 tab
    case squareHen = "square.hen"           // NestStageView 里的母鸡
    case nestStage = "square.nestStage"     // NestStageView 整块（蛋 + 下面那行字）
    case cards = "square.cards"             // SquareViewController.cardArea
    case weekStrip = "square.weekStrip"     // SquareViewController.weekStrip
    case monthGrid = "square.monthGrid"     // SquareViewController.monthGrid
}

/// 一步在屏幕上长什么样。
nonisolated struct TutorialScene: Equatable {
    /// 母鸡说的话。**nil = 这一步是「等」**：蒙层透明、不说话、挡住所有点击 ——
    /// 等母鸡回话、等蛋孵出来的那几秒，别让人乱点把剧本点乱
    let line: String?
    /// 露出来的地方，多个就取并集。空 = 整屏压暗、只说话
    let spotlight: [TutorialAnchor]
    /// 「继续」按钮上的字。nil = 这一步靠用户做动作推进，不给按钮
    let continueTitle: String?
    /// 显不显示「跳过示范」
    let canSkip: Bool

    static let waiting = TutorialScene(line: nil, spotlight: [], continueTitle: nil, canSkip: false)
}

nonisolated enum TutorialFlow {

    /// 这一步收到这个事件之后去哪一步，以及**过多久再露出**下一步的画面。
    /// nil = 这个事件在这一步不算数（比如该按母鸡的时候去翻卡片 —— 本来也点不到，双保险）。
    ///
    /// 「过多久」只推迟画面，不推迟状态：协调者收到结果就立刻换到下一步，
    /// 中间那段显示 `.waiting`。给动画留时间（蛋揭晓、月历展开），也给「做到了」留个空当。
    static func next(from step: TutorialStep, on event: TutorialEvent) -> (step: TutorialStep, delay: TimeInterval)? {
        if event == .skipTapped, step != .finished { return (.finished, 0) }

        switch (step, event) {
        case (.intro, .continueTapped):           return (.tapNest, 0)

        case (.tapNest, .composeOpened):          return (.typing, 0)
        case (.typing, .presetTyped):             return (.tapSave, 0)
        case (.tapSave, .diarySaved):             return (.henReplying, 0)
        case (.henReplying, .composeClosed):      return (.tapCalendar, 0.4)

        case (.tapCalendar, .pageChanged(1)):     return (.pressHen, 0.5)
        case (.pressHen, .laidEgg):               return (.hatching, 0)
        // 揭晓动画要一会儿，演完再开口
        case (.hatching, .eggHatched):            return (.eggExplained, 1.6)
        // 母鸡自己会说「等会儿再按我试试」，蒙层回到「按住我」，再按一次就行
        case (.hatching, .hatchFailed):           return (.pressHen, 0.8)
        case (.eggExplained, .continueTapped):    return (.flipCard, 0)

        case (.flipCard, .flippedCard):           return (.swipeWeek, 0.6)
        case (.swipeWeek, .swipedWeek):           return (.pullMonth, 0.5)

        case (.pullMonth, .monthExpanded(true)):  return (.swipeMonth, 0.35)
        // 还没翻月就推回去了（或者直接点了一天，月历跟着收起）—— 回到「往下拉」，翻月这步不能混过去。
        // 所以 .pullMonth 故意不接「在月历里点了一天」：没翻过月，点了也不算
        case (.swipeMonth, .monthExpanded(false)): return (.pullMonth, 0)
        case (.swipeMonth, .swipedMonth):         return (.pickInMonth, 0.4)

        // 翻过月之后月历收起了。在月历里点一天也会走这条：月历选完日期先收起、再报选了哪天 ——
        // 所以 .repullMonth 要接住紧跟着来的那个「选了哪天」
        case (.pickInMonth, .monthExpanded(false)): return (.repullMonth, 0)
        case (.repullMonth, .monthExpanded(true)): return (.pickInMonth, 0.35)
        // 只认 fromMonth —— 在周条上点一天不能把「看月历」这一步混过去
        case (.pickInMonth, .pickedDay(let isToday, let count, true)),
             (.repullMonth, .pickedDay(let isToday, let count, true)):
            return (canDelete(isToday: isToday, entryCount: count) ? .longPress : .pickDayToDelete, 0.6)
        case (.pickDayToDelete, .pickedDay(let isToday, let count, _)) where canDelete(isToday: isToday, entryCount: count):
            return (.longPress, 0.6)

        case (.longPress, .editingChanged(true)): return (.tapDelete, 0.3)
        // 抖着的时候点了卡片别处，退出了编辑模式 —— 叉没了，回去重新长按
        case (.tapDelete, .editingChanged(false)): return (.longPress, 0)
        case (.tapDelete, .deletedEntry):         return (.rehatching, 0)
        case (.rehatching, .rehatched):           return (.rehatchExplained, 1.4)
        case (.rehatchExplained, .continueTapped): return (.outro, 0)

        case (.outro, .continueTapped):           return (.finished, 0)

        default:
            return nil
        }
    }

    /// 删除要演到「那天的蛋按剩下的日记重孵」，所以挑的那天得满足两条：
    /// · 不是今天 —— 删今天的，蛋直接作废、母鸡回到台上等人按，跟「重孵」讲的不是一回事
    /// · 至少两篇 —— 删完还剩一篇，才有东西可以重孵
    ///
    /// 示范数据里过去每天都正好两篇（`TutorialScript`），所以点任何一颗蛋都行；
    /// 只有点到今天、或者点到示范数据以外的空日子，才会走到 `.pickDayToDelete`。
    static func canDelete(isToday: Bool, entryCount: Int) -> Bool {
        !isToday && entryCount >= 2
    }

    // MARK: - 这一步放行哪些手势

    /// **教什么就只放行什么。** 蒙层只管「点哪里」—— 可洞里那个东西身上往往不止一种手势，蒙层分不出来：
    /// 周条上往下拉会展开月历，卡片上长按会进删除模式。不该教的时候放行了，示范会卡死：
    /// · 教翻周时往下拉 → 月历展开、周条被淡成透明，洞跟着没了，整屏点不动（09-29 模拟器复现过）
    /// · 教翻卡时长按、删掉今天一篇 → 今天只剩一篇，拖不动了
    ///
    /// 所以这两种手势由页面上的开关管（`SquareViewController.allowsMonthToggle` / `allowsCardEditing`），
    /// 每换一步，导演照这里的答案去拨开关。
    static func allowsMonthToggle(at step: TutorialStep) -> Bool {
        switch step {
        case .pullMonth, .swipeMonth, .pickInMonth, .repullMonth: return true
        default: return false
        }
    }

    static func allowsCardEditing(at step: TutorialStep) -> Bool {
        step == .longPress || step == .tapDelete
    }

    // MARK: - 每一步长什么样

    static func scene(for step: TutorialStep) -> TutorialScene {
        switch step {
        case .intro:
            return say("我是 Muji。先陪你走一遍怎么用 —— 这一趟写的都是示范，走完就清空。",
                       continueTitle: "好")
        case .tapNest:
            return say("点一下鸟巢，写今天的日记。", at: [.nest])
        case .tapSave:
            return say("这篇我替你写好了，点「收好」。", at: [.composeSave])
        case .tapCalendar:
            return say("写下的日记都在日历里。点这里。", at: [.calendarTab])
        case .pressHen:
            return say("按住我别松手，把今天孵成一颗蛋。", at: [.squareHen])
        case .eggExplained:
            return say("一天不管写几篇，最后都收成一颗蛋。蛋的样子，就是这一天的心情。",
                       at: [.nestStage], continueTitle: "嗯")
        case .flipCard:
            // 最上面那张是早上那篇（按时间排），翻过去才是刚写的
            return say("左右拖卡片，看今天的另一篇。", at: [.cards])
        case .swipeWeek:
            // 这时周条一定停在本周（进日历页会回到本周），本周是最后一页，只能往右 = 往回翻
            return say("这一行是这一周，每天的蛋都挂在上面。往右滑，翻到上一周。", at: [.weekStrip])
        case .pullMonth:
            // 月历收着时高度是 0、贴在周条上沿，并集就是周条；拉下来之后就是整个月历
            return say("往下拉，展开整个月。", at: [.weekStrip, .monthGrid])
        case .swipeMonth:
            // 不说方向：月历打开在哪个月不一定（跟着周条停的那周走），可能在最后一页、也可能不在
            return say("这是整个月。左右滑，翻到别的月份。", at: [.weekStrip, .monthGrid])
        case .pickInMonth:
            return say("每颗蛋是一天。点一颗，跳到那天。", at: [.weekStrip, .monthGrid])
        case .repullMonth:
            return say("再往下拉，点一颗蛋。", at: [.weekStrip, .monthGrid])
        case .pickDayToDelete:
            return say("换一天试试：点周条上挂着蛋的那几天。", at: [.weekStrip])
        case .longPress:
            return say("写下的也能删。长按卡片。", at: [.cards])
        case .tapDelete:
            return say("点卡片左上角的叉，删掉这篇。", at: [.cards])
        case .rehatchExplained:
            return say("删掉一篇，那天的蛋按剩下的重新孵。",
                       at: [.nestStage], continueTitle: "知道了")
        case .outro:
            // 最后一句不给跳过：它本身就是出口
            // 手动断行：自动折行会把「现在」拆成「现 / 在」
            return TutorialScene(line: "示范就到这儿，刚才那些都会清空。\n现在，轮到你了。",
                                 spotlight: [], continueTitle: "开始", canSkip: false)
        case .typing, .henReplying, .hatching, .rehatching, .finished:
            return .waiting
        }
    }

    private static func say(_ line: String, at spotlight: [TutorialAnchor] = [],
                            continueTitle: String? = nil) -> TutorialScene {
        TutorialScene(line: line, spotlight: spotlight, continueTitle: continueTitle, canSkip: true)
    }
}
