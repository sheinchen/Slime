//
//  TutorialFlowTests.swift
//  SlimeTests
//
//  示范的剧本：每一步等什么、去哪一步、屏幕上露出什么。
//
//  剧本判错的后果是**把人卡在示范里** —— 蒙层挡着所有点击，只放行一个洞，
//  洞里的动作又推不动下一步，用户只能杀 App。页面上很难每条岔路都点到，所以锁在这里。
//

import XCTest
@testable import Slime

/// 纯函数：同步测试就行（没有 isolated deinit，不撞 §5 那个运行时 bug）
final class TutorialFlowTests: XCTestCase {

    /// 按事件一步步推，返回每一步停在哪。某个事件不算数就当场失败
    private func walk(_ events: [TutorialEvent], from start: TutorialStep = .intro,
                      file: StaticString = #filePath, line: UInt = #line) -> [TutorialStep] {
        var step = start
        var visited: [TutorialStep] = []
        for event in events {
            guard let next = TutorialFlow.next(from: step, on: event) else {
                XCTFail("\(step) 收到 \(event) 走不动", file: file, line: line)
                return visited
            }
            step = next.step
            visited.append(step)
        }
        return visited
    }

    // MARK: - 主线

    func test_照剧本走一遍_能走到结束() {
        let steps = walk([
            .continueTapped,                                             // 打招呼
            .composeOpened, .presetTyped, .diarySaved, .composeClosed,   // 写
            .pageChanged(1), .laidEgg, .eggHatched, .continueTapped,     // 孵
            .flippedCard,                                                // 翻卡
            .swipedWeek,                                                 // 翻周
            .monthExpanded(true),                                        // 月历拉下来
            .swipedMonth,                                                // 翻月
            .monthExpanded(false),                                       // 月历里点一天：先收起……
            .pickedDay(isToday: false, entryCount: 2, fromMonth: true),  // ……再报选了哪天
            .editingChanged(true), .deletedEntry, .rehatched, .continueTapped, // 删
            .continueTapped,                                             // 收尾
        ])
        XCTAssertEqual(steps.last, .finished)
        XCTAssertEqual(steps, [
            .tapNest, .typing, .tapSave, .henReplying, .tapCalendar,
            .pressHen, .hatching, .eggExplained, .flipCard,
            .swipeWeek, .pullMonth, .swipeMonth, .pickInMonth, .repullMonth, .longPress,
            .tapDelete, .rehatching, .rehatchExplained, .outro, .finished,
        ])
    }

    func test_哪一步都能跳过() {
        for step in TutorialStep.allCases where step != .finished {
            XCTAssertEqual(TutorialFlow.next(from: step, on: .skipTapped)?.step, .finished, "\(step)")
        }
        XCTAssertNil(TutorialFlow.next(from: .finished, on: .skipTapped))
    }

    // MARK: - 不算数的事件

    func test_不相干的动作不推进() {
        XCTAssertNil(TutorialFlow.next(from: .pressHen, on: .flippedCard))
        XCTAssertNil(TutorialFlow.next(from: .tapNest, on: .continueTapped), "要做动作的步骤不认「继续」")
        XCTAssertNil(TutorialFlow.next(from: .tapCalendar, on: .pageChanged(0)), "点的是首页不是日历")
    }

    /// 翻周那一步要的是滑，点一天不算（「点一天」只在月历里教一次）
    func test_翻周那步_点一天不算() {
        XCTAssertNil(TutorialFlow.next(from: .swipeWeek,
                                       on: .pickedDay(isToday: false, entryCount: 2, fromMonth: false)))
    }

    /// 看月历那一步只认月历里点的 —— 在周条上点一天不能把它混过去
    func test_看月历那步_周条上点一天不算() {
        XCTAssertNil(TutorialFlow.next(from: .pullMonth,
                                       on: .pickedDay(isToday: false, entryCount: 2, fromMonth: false)))
    }

    /// 还没翻月：月历拉下来直接点了一天（月历跟着收起 → 回到「往下拉」），接着来的「选了哪天」不能把翻月混过去
    func test_没翻月就点了一天_不算_还得再拉下来翻() {
        XCTAssertEqual(TutorialFlow.next(from: .swipeMonth, on: .monthExpanded(false))?.step, .pullMonth)
        XCTAssertNil(TutorialFlow.next(from: .pullMonth,
                                       on: .pickedDay(isToday: false, entryCount: 2, fromMonth: true)))
    }

    // MARK: - 岔路

    /// 翻过月之后推回去了：再拉下来点一天就行，不用重新翻月
    func test_翻过月又推回去_再拉下来直接点天() {
        XCTAssertEqual(TutorialFlow.next(from: .pickInMonth, on: .monthExpanded(false))?.step, .repullMonth)
        XCTAssertEqual(TutorialFlow.next(from: .repullMonth, on: .monthExpanded(true))?.step, .pickInMonth)
    }

    /// 月历里点到今天、或者点到示范数据以外的空日子，删不了 —— 让人换一天
    func test_月历里点了删不了的日子_让换一天() {
        let today = TutorialEvent.pickedDay(isToday: true, entryCount: 2, fromMonth: true)
        let empty = TutorialEvent.pickedDay(isToday: false, entryCount: 0, fromMonth: true)
        XCTAssertEqual(TutorialFlow.next(from: .pickInMonth, on: today)?.step, .pickDayToDelete)
        XCTAssertEqual(TutorialFlow.next(from: .repullMonth, on: empty)?.step, .pickDayToDelete)

        XCTAssertNil(TutorialFlow.next(from: .pickDayToDelete, on: today))
        let good = TutorialEvent.pickedDay(isToday: false, entryCount: 2, fromMonth: false)
        XCTAssertEqual(TutorialFlow.next(from: .pickDayToDelete, on: good)?.step, .longPress)
    }

    /// 抖着的时候点了卡片别处，叉没了 —— 回去重新长按，不能停在「点叉」
    func test_退出了编辑模式_回到长按() {
        XCTAssertEqual(TutorialFlow.next(from: .tapDelete, on: .editingChanged(false))?.step, .longPress)
    }

    /// 没孵出来要退回「按住我」，不然停在「等」那一步，蒙层挡着所有点击，人就卡死了
    func test_没孵出来_退回按住母鸡() {
        XCTAssertEqual(TutorialFlow.next(from: .hatching, on: .hatchFailed)?.step, .pressHen)
    }

    func test_能删的日子_过去某天且至少两篇() {
        XCTAssertTrue(TutorialFlow.canDelete(isToday: false, entryCount: 2))
        XCTAssertFalse(TutorialFlow.canDelete(isToday: true, entryCount: 2), "删今天演不出重孵")
        XCTAssertFalse(TutorialFlow.canDelete(isToday: false, entryCount: 1), "删完就没了，也演不出重孵")
    }

    // MARK: - 画面

    /// **最要紧的一条**：母鸡在说话、却既没有「继续」按钮、也没露出任何能点的东西 ——
    /// 蒙层把所有点击都挡了，这一步永远推不动
    func test_每个说话的步骤_要么有按钮_要么露出能点的地方() {
        for step in TutorialStep.allCases {
            let scene = TutorialFlow.scene(for: step)
            guard scene.line != nil else { continue }
            XCTAssertTrue(scene.continueTitle != nil || !scene.spotlight.isEmpty, "\(step) 会把人卡住")
        }
    }

    // MARK: - 教什么就只放行什么

    /// 09-29 模拟器复现过：教翻周时往下拉，月历展开、周条被淡成透明，洞跟着没了，整屏点不动。
    /// 所以只有教月历的那几步才能拉开 / 收起月历
    func test_只有教月历的那几步_能拉开月历() {
        let monthSteps: Set<TutorialStep> = [.pullMonth, .swipeMonth, .pickInMonth, .repullMonth]
        for step in TutorialStep.allCases {
            XCTAssertEqual(TutorialFlow.allowsMonthToggle(at: step), monthSteps.contains(step), "\(step)")
        }
        // 最容易出事的就是这三步：洞只开在周条上，拉下来就没洞了
        for step in [TutorialStep.swipeWeek, .pickDayToDelete] {
            XCTAssertFalse(TutorialFlow.allowsMonthToggle(at: step), "\(step)")
        }
    }

    /// 教翻卡时要是能长按删掉今天一篇，今天就只剩一篇、拖不动了 —— 所以只有教删除的两步能长按
    func test_只有教删除的两步_能长按进删除模式() {
        for step in TutorialStep.allCases {
            XCTAssertEqual(TutorialFlow.allowsCardEditing(at: step),
                           step == .longPress || step == .tapDelete, "\(step)")
        }
    }

    func test_等的那几步_不说话_不露洞() {
        for step in [TutorialStep.typing, .henReplying, .hatching, .rehatching] {
            XCTAssertEqual(TutorialFlow.scene(for: step), .waiting, "\(step)")
        }
    }

    func test_说话的步骤都能跳过_最后一句除外() {
        for step in TutorialStep.allCases where step != .outro {
            let scene = TutorialFlow.scene(for: step)
            guard scene.line != nil else { continue }
            XCTAssertTrue(scene.canSkip, "\(step)")
        }
        XCTAssertFalse(TutorialFlow.scene(for: .outro).canSkip, "最后一句本身就是出口")
    }
}
