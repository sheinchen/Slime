//
//  CareGateRuleTests.swift
//  SlimeTests
//
//  Created by shiying on 2026/9/4.
//

import XCTest
@testable import Slime

final class CareGateRuleTests: XCTestCase {

    /// 固定时刻。**测试绝不能依赖「今天」**，否则跨零点跑就会飘。
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func egg(daysAgo: Int) -> DayEggRecord {
        let day = now.addingTimeInterval(TimeInterval(-daysAgo * 86_400))
        return DayEggRecord(date: day, text: "第 \(daysAgo) 天前", emotion: .calm, createdAt: day)
    }

    /// 默认是「四个条件都满足」的健康场景，各条测试只改自己关心的那一个参数。
    private func decide(hasActiveCare: Bool = false,
                        eggs: [DayEggRecord]? = nil,
                        lastCheckedAt: Date? = nil,
                        lastRetiredAt: Date? = nil) -> CareGateResult {
        CareGateRule.decide(
            hasActiveCare: hasActiveCare,
            eggsInWindow: eggs ?? [egg(daysAgo: 1), egg(daysAgo: 2), egg(daysAgo: 3)],
            lastCheckedAt: lastCheckedAt,
            lastRetiredAt: lastRetiredAt,
            now: now)
    }

    // MARK: - 四条挡人的路

    func test_有关怀挂着时不生成第二条() {
        XCTAssertEqual(decide(hasActiveCare: true), .blocked(.careAlreadyShowing))
    }

    func test_没有新蛋时挡下() {
        // 蛋都是过去造的，上次检查就在刚才 → 没有新的
        XCTAssertEqual(decide(lastCheckedAt: now), .blocked(.noNewEgg))
    }

    func test_不足三天时挡下() {
        XCTAssertEqual(decide(eggs: [egg(daysAgo: 1), egg(daysAgo: 2)]), .blocked(.notEnoughDays))
    }

    func test_冷却期内挡下() {
        XCTAssertEqual(decide(lastRetiredAt: now.addingTimeInterval(-86_400)), .blocked(.cooling))
    }

    // MARK: - 放行

    func test_条件都满足时放行() {
        guard case .pass(let window) = decide() else { return XCTFail("该放行却被挡了") }
        XCTAssertEqual(window.eggs.count, 3)
    }

    func test_放行的窗口按日期升序() {
        let 乱序 = [egg(daysAgo: 1), egg(daysAgo: 3), egg(daysAgo: 2)]
        guard case .pass(let window) = decide(eggs: 乱序) else { return XCTFail("该放行") }
        XCTAssertEqual(window.eggs.map(\.date), window.eggs.map(\.date).sorted())
    }

    // MARK: - 两个 nil 边界（最容易写反的地方）

    func test_从没检查过时不算没有新蛋() {
        XCTAssertNotEqual(decide(lastCheckedAt: nil), .blocked(.noNewEgg))
    }

    func test_从没关怀过时不算在冷却中() {
        XCTAssertNotEqual(decide(lastRetiredAt: nil), .blocked(.cooling))
    }

    // MARK: - 边界值与顺序

    func test_冷却正好满时放行() {
        let 刚满三天 = now.addingTimeInterval(-CareGateRule.cooldown - 1)
        guard case .pass = decide(lastRetiredAt: 刚满三天) else { return XCTFail("冷却满了该放行") }
    }

    func test_前置优先于其他条件() {
        // 同时踩了「有关怀挂着」和「天数不足」，应该报前者
        XCTAssertEqual(decide(hasActiveCare: true, eggs: []), .blocked(.careAlreadyShowing))
    }
}
