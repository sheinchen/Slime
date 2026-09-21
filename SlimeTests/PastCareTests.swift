//
//  PastCareTests.swift
//  SlimeTests
//
//  isNew 判据的单测。
//
//  eval 测的是「模型会不会正确使用 isNew」—— 有随机性、要花钱、默认跳过。
//  这里测的是「isNew 本身算得对不对」—— 纯算术、零成本，每次 Cmd+U 都跑。
//  两半缺一不可：判据算错了，eval 分数再高也是蒙对的。
//

import XCTest
@testable import Slime

final class PastCareTests: XCTestCase {

    private let calendar = Calendar.current

    /// 固定的「今天」。测试不能依赖真实日期。
    private var today: Date { calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000)) }

    /// ago 天前的零点
    private func day(_ ago: Int) -> Date {
        calendar.date(byAdding: .day, value: -ago, to: today)!
    }

    /// ago 天前的 hour 点
    private func at(_ ago: Int, _ hour: Int) -> Date {
        calendar.date(byAdding: .hour, value: hour, to: day(ago))!
    }

    /// 代表 ago 天前、在 hatchedAt 这一刻孵出的蛋
    private func egg(dayAgo ago: Int, hatchedAt: Date) -> DayEggRecord {
        DayEggRecord(date: day(ago), text: "", emotion: .calm, createdAt: hatchedAt)
    }

    private func care(saidAt: Date) -> PastCare {
        PastCare(text: "", stillShowing: true, saidAt: saidAt, about: [])
    }

    // MARK: - 跨天：看日期

    func test_关怀之前的日子不算新() {
        let noon = care(saidAt: at(0, 12))
        XCTAssertFalse(noon.isNewEvidence(egg(dayAgo: 1, hatchedAt: at(1, 21)), calendar: calendar))
    }

    func test_关怀之后的日子算新() {
        let yesterday = care(saidAt: at(1, 12))
        XCTAssertTrue(yesterday.isNewEvidence(egg(dayAgo: 0, hatchedAt: at(0, 9)), calendar: calendar))
    }

    func test_迟补的旧蛋不算新() {
        // 5 天前那颗孵失败，今天 18 点才补上：孵出时刻最新，内容却在关怀之前。
        // 这条就是「纯按孵出时刻会乱」的那种情况。
        let noon = care(saidAt: at(0, 12))
        XCTAssertFalse(noon.isNewEvidence(egg(dayAgo: 5, hatchedAt: at(0, 18)), calendar: calendar))
    }

    // MARK: - 关怀当天：看孵出时刻

    func test_关怀当天_孵在关怀之前不算新() {
        let noon = care(saidAt: at(0, 12))
        XCTAssertFalse(noon.isNewEvidence(egg(dayAgo: 0, hatchedAt: at(0, 10)), calendar: calendar))
    }

    func test_关怀当天_晚上重孵算新() {
        // 漏洞一：中午说了关怀，晚上又写了一篇、重按母鸡。只按日期比会漏掉。
        let noon = care(saidAt: at(0, 12))
        XCTAssertTrue(noon.isNewEvidence(egg(dayAgo: 0, hatchedAt: at(0, 18)), calendar: calendar))
    }

    func test_关怀当天_孵出时刻正好等于关怀时刻不算新() {
        // 边界：严格大于才算新
        let noon = care(saidAt: at(0, 12))
        XCTAssertFalse(noon.isNewEvidence(egg(dayAgo: 0, hatchedAt: at(0, 12)), calendar: calendar))
    }

    func test_昨晚的关怀_昨天的蛋今早才补上算新() {
        // 漏洞二：昨晚 8 点说了关怀，之后又写了一篇没按母鸡，今早补蛋才孵出来。
        // 蛋的日期和关怀同一天，只按日期比会被当成已回应的背景。
        let lastNight = care(saidAt: at(1, 20))
        XCTAssertTrue(lastNight.isNewEvidence(egg(dayAgo: 1, hatchedAt: at(0, 8)), calendar: calendar))
    }
}
