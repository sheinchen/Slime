//
//  LaunchOptionsTests.swift
//  SlimeTests
//
//  启动参数的解析。纯值类型，同步测就行。
//

#if DEBUG
import XCTest
@testable import Slime

final class LaunchOptionsTests: XCTestCase {

    func test_什么都不带_什么都不开() {
        let o = LaunchOptions(arguments: ["Slime"])
        XCTAssertFalse(o.useTestStore)
        XCTAssertFalse(o.resetTutorial)
        XCTAssertEqual(o.stubs, LaunchOptions.Stubs())
        XCTAssertNil(o.seed, "不带参数 = 不播种、用上次的库，这一档是必需的")
    }

    func test_StubAI_四路全打桩_包括检索() {
        let s = LaunchOptions(arguments: ["-StubAI"]).stubs
        XCTAssertTrue(s.care && s.egg && s.chat && s.recall)
        XCTAssertFalse(s.quiet || s.offline || s.slow, "-StubAI 只管换不换，不管桩怎么演")
    }

    func test_单开一路_不影响别的路_检索没有单独开关() {
        let s = LaunchOptions(arguments: ["-StubCare"]).stubs
        XCTAssertTrue(s.care)
        XCTAssertFalse(s.egg || s.chat || s.recall)
    }

    func test_桩怎么演的三个开关() {
        let s = LaunchOptions(arguments: ["-StubChat", "-StubOffline", "-StubSlow", "-StubQuiet"]).stubs
        XCTAssertTrue(s.chat && s.offline && s.slow && s.quiet)
    }

    func test_播种_同时给了几个只认优先级最高的() {
        // 以前 SceneDelegate 那串 if / else if 的顺序：Seed* 在前，Care* 在后
        XCTAssertEqual(LaunchOptions(arguments: ["-CareAge", "-SeedLife"]).seed, .life)
        XCTAssertEqual(LaunchOptions(arguments: ["-CareLate", "-CareTurn"]).seed, .careTurn)
    }

    func test_播种_旧名字照样认() {
        XCTAssertEqual(LaunchOptions(arguments: ["-CareStep2"]).seed, .careTurn)
        XCTAssertEqual(LaunchOptions(arguments: ["-CareStep3"]).seed, .careFlat)
    }

    func test_SeedFlat和CareFlat不会认混() {
        XCTAssertEqual(LaunchOptions(arguments: ["-SeedFlat"]).seed, .flat)
        XCTAssertEqual(LaunchOptions(arguments: ["-CareFlat"]).seed, .careFlat)
    }

    func test_测试库开关() {
        XCTAssertTrue(LaunchOptions(arguments: ["-UseTestStore", "-SeedDiaries"]).useTestStore)
    }

    func test_重看示范开关() {
        XCTAssertTrue(LaunchOptions(arguments: ["-ResetTutorial"]).resetTutorial)
    }
}
#endif
