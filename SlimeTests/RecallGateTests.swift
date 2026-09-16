//
//  RecallGateTests.swift
//  SlimeTests
//
//  聊天检索的本地闸门。跟 CareGateRuleTests 一个性质：只测算术。
//
//  这里能测的东西很少 —— 因为闸门只剩一条规则。
//  原本还有一条「隔几轮才能再提旧事」，砍掉了：
//  用户追问「上次那个你还记得吗」和母鸡自作多情地翻旧账，
//  在本地眼里都只是「距上次过了几轮」，分不开。那是语义判断，归 AI。
//

import XCTest
@testable import Slime

final class RecallGateTests: XCTestCase {

    func test_太短的句子不查() {
        XCTAssertFalse(RecallGate.shouldTry(message: "嗯"))
        XCTAssertFalse(RecallGate.shouldTry(message: "好呀"))
    }

    func test_空白不算长度() {
        XCTAssertFalse(RecallGate.shouldTry(message: "  好  "))
    }

    func test_够长就放行() {
        XCTAssertTrue(RecallGate.shouldTry(message: "今天又被组长说了"))
        // 放行不等于一定会检索 —— AI 那边还有一次否决权
        XCTAssertTrue(RecallGate.shouldTry(message: "你还记得上次那件事吗"))
    }

    // MARK: - 模糊时间

    func test_给AI的时间必须是模糊的() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        func ago(_ days: Int) -> String {
            ChineseDate.vague(now.addingTimeInterval(TimeInterval(-days * 86_400)), from: now)
        }

        XCTAssertEqual(ago(0), "今天")
        XCTAssertEqual(ago(1), "昨天")
        XCTAssertEqual(ago(3), "前几天")
        XCTAssertEqual(ago(10), "上周")
        XCTAssertEqual(ago(45), "一个多月前")
        XCTAssertEqual(ago(75), "两个多月前")
        XCTAssertEqual(ago(200), "半年多前")
        XCTAssertEqual(ago(400), "很久以前")

        // 阿拉伯数字一个都不能出现，不然母鸡会顺口把日期说出来。
        // 注意不能直接用 isNumber —— 中文数字「一」「两」也满足它，
        // 而「一个多月前」这种模糊说法正是我们要的。
        for days in [0, 1, 3, 10, 45, 75, 200, 400] {
            XCTAssertFalse(ago(days).contains { $0.isASCII && $0.isNumber },
                           "「\(ago(days))」里有阿拉伯数字")
        }
    }
}
