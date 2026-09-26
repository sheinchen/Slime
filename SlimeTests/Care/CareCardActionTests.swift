//
//  CareCardActionTests.swift
//  SlimeTests
//
//  首页关怀卡片「这一刻该做什么」。纯函数，同步测就行。
//  每一条对应 CLAUDE.md「卡片两种形态」里踩过的一个坑。
//

import XCTest
@testable import Slime

final class CareCardActionTests: XCTestCase {

    private let a = UUID()
    private let b = UUID()

    private func care(_ id: UUID, seen: Bool) -> PendingCare {
        PendingCare(id: id, text: "咕", createdAt: Date(timeIntervalSince1970: 0),
                    firstSeenAt: seen ? Date(timeIntervalSince1970: 60) : nil)
    }

    /// 把结果压成字符串好比较（带着的 PendingCare 只看 id）
    private func name(_ action: CareCardAction) -> String {
        switch action {
        case .none: return "none"
        case .dismiss: return "dismiss"
        case .replace: return "replace"
        case .speak(let c): return "speak \(c.id == a ? "a" : "b")"
        case .linger(let c): return "linger \(c.id == a ? "a" : "b")"
        }
    }

    private func decide(visible: Bool = true, active: PendingCare?, showing: UUID?) -> String {
        name(CareCardAction.decide(isVisible: visible, active: active, showingId: showing))
    }

    // 坑：从后台回来停在广场页，卡片在没人看的首页上滑出、3 秒后落库 —— 这条关怀白说了
    func test_不在眼前_什么都不演() {
        XCTAssertEqual(decide(visible: false, active: care(a, seen: false), showing: nil), "none")
        XCTAssertEqual(decide(visible: false, active: nil, showing: a), "none",
                       "不在眼前时连收都不收 —— 回到首页再说")
    }

    func test_第一次露面是说_之后是在() {
        XCTAssertEqual(decide(active: care(a, seen: false), showing: nil), "speak a")
        XCTAssertEqual(decide(active: care(a, seen: true), showing: nil), "linger a")
    }

    // 坑：一天来回切五次 tab，母鸡把同一句话隆重说五遍
    func test_正演着的就是它_不重放() {
        XCTAssertEqual(decide(active: care(a, seen: false), showing: a), "none")
    }

    // 坑：原来的 guard showingCareId == nil 会让新关怀永远进不来
    func test_换了一条_先收旧的() {
        XCTAssertEqual(decide(active: care(b, seen: false), showing: a), "replace")
    }

    // 坑：activeCare() 返回 nil 时直接 return，作废的话会一直挂着
    func test_挂着的那条退场了_卡片跟着收() {
        XCTAssertEqual(decide(active: nil, showing: a), "dismiss")
        XCTAssertEqual(decide(active: nil, showing: nil), "none")
    }
}
