//
//  HomeViewModel.swift
//  Slime
//

import Foundation

/// 关怀卡片这一刻该做什么。`HomeViewModel.careAction` 的返回值。
///
/// 以前这套判断写在 `HomeViewController.presentCareIfNeeded()` 里，四个 guard 叠在一起，
/// CLAUDE.md「卡片两种形态」那几条坑（不在眼前别演、按 id 比、取不到要收掉）全是它 —— 却没法测。
/// 09-25 抽成纯函数 `decide`，有 `CareCardActionTests` 锁着；VC 只剩「按这个结果演」。
nonisolated enum CareCardAction {
    /// 什么都不做
    case none
    /// 收掉：挂着的那条已经退场了（AI 换掉了、或满 3 天）
    case dismiss
    /// 换了一条：先把旧的收掉，收完再问一次（那时就是 speak / linger 新的那条）
    case replace
    /// 第一次露面：滑出、尾巴跟着母鸡 —— 「说」
    case speak(PendingCare)
    /// 之前被看到过：安静地挂在那行小字右边 —— 「在」
    case linger(PendingCare)

    /// - Parameters:
    ///   - isVisible: 首页此刻在用户眼前（是当前 tab，也没被写日记的浮层盖住）
    ///   - active: 库里此刻挂着的那条关怀
    ///   - showingId: 卡片上正演着的那条。nil = 卡片现在没露面
    static func decide(isVisible: Bool, active: PendingCare?, showingId: UUID?) -> CareCardAction {
        // 不在眼前就别演。挡的不是「白演一场」，是**会把这条关怀标记成看过了**：
        // 从后台回来时用户可能停在广场页，刷新照样打到首页，卡片在没人看的首页上滑出、
        // 3 秒后落库 —— 这条关怀就这么白说了。回到首页时会再问一次。
        guard isVisible else { return .none }

        // 挂着的那条退场了 —— 卡片跟着收掉。卡片不会自己走（没有兜底定时器），
        // 没有这一条它会一直挂着一句已经作废的话。
        guard let active else { return showingId == nil ? .none : .dismiss }

        // 正演着的就是它，别重放
        if active.id == showingId { return .none }

        // 换了一条：不能直接盖上去 —— 滑出动画会把透明度归零再弹回来，旧话新话会闪一下
        if showingId != nil { return .replace }

        // 「说」还是「在」—— 整个分叉就在这一行。一条关怀会在首页露面很多次
        // （每次进首页、每次切 tab 回来都算），但她**只说了一次**。
        return active.firstSeenAt == nil ? .speak(active) : .linger(active)
    }
}

/// 首页的 ViewModel：今天的蛋孵了没有、关怀卡片该怎么演。
///
/// 09-25 由 `CareViewModel` 扩出来（那个只被首页用，名字也只管得了一半）。
/// 以前首页有个 `laidToday` 从来没被赋值 —— 今天的蛋孵出来了，首页还写着「巢是空的」。
@MainActor
final class HomeViewModel {

    private let messages: CareMessageStore
    private let eggs: DayEggStore
    private let calendar: Calendar
    private let now: () -> Date

    /// 依赖必填；日历和时钟是值，留默认（规则见 CLAUDE.md §5「依赖只从组合根来」）。
    init(messages: CareMessageStore,
         eggs: DayEggStore,
         calendar: Calendar = .current,
         now: @escaping () -> Date = { Date() }) {
        self.messages = messages
        self.eggs = eggs
        self.calendar = calendar
        self.now = now
    }

    /// 今天的蛋孵出来没有。首页那行小字和鸟巢的提示圈跟着它变。
    /// 每次现查：首页进页、回前台、跨零点都会重画，查一次库就一行。
    var hasEggToday: Bool {
        eggs.egg(for: calendar.startOfDay(for: now())) != nil
    }

    /// 关怀卡片这一刻该做什么。判断全在 `CareCardAction.decide`，这里只负责去库里取当前那条。
    func careAction(isVisible: Bool, showingId: UUID?) -> CareCardAction {
        CareCardAction.decide(isVisible: isVisible, active: messages.active(), showingId: showingId)
    }

    /// 这条话**真的被看到了**。
    ///
    /// 调用点在 `HomeViewController`：卡片滑出后活满几秒才调。
    /// 被用户的操作打断的那次不算 —— 下次进首页它仍然享受完整的「首次」待遇。
    ///
    /// 这个方法只写「露面的生命」，**不碰 status**：
    /// 什么时候真正退场仍然是关怀引擎说了算（AI 判替换 / 满 3 天兜底）。
    func markSeen(_ id: UUID, at date: Date = Date()) {
        messages.markFirstSeen(id: id, at: date)
    }
}
