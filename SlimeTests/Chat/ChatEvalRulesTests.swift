//
//  ChatEvalRulesTests.swift
//  SlimeTests
//
//  锁住多轮聊天验收的尺子。尺子错了会伪装成「模型没问题」，所以它自己也要有测试。
//  不调 API，每次都跑。
//

import XCTest
@testable import Slime

/// 纯函数：同步测试就行
final class ChatEvalRulesTests: XCTestCase {

    private typealias R = ChatEvalRules

    func test_只数汉字() {
        XCTAssertEqual(R.hanCount("Muji转圈圈～"), 3)
        XCTAssertEqual(R.hanCount("第6版！！"), 2)
    }

    func test_问句收尾_末尾波浪号不影响() {
        XCTAssertTrue(R.endsWithQuestion("你咋啦？～"))
        XCTAssertTrue(R.endsWithQuestion("then?"))
        XCTAssertFalse(R.endsWithQuestion("好～那Muji要去刨土！"))
    }

    func test_问了几个问题_叫声不算() {
        XCTAssertEqual(R.questions("咕？程序是什么，能吃吗？Muji刚叼到一条肥虫子"), 1)
        XCTAssertEqual(R.questions("咕咕咕？程序是什么，能吃吗？"), 1)
        XCTAssertEqual(R.questions("什么？"), 1)
        XCTAssertEqual(R.questions("香不香呀？加蛋加脆饼没？"), 2)
        XCTAssertEqual(R.questions("好～那Muji要去刨土！"), 0)
    }

    func test_整句只有问题() {
        XCTAssertTrue(R.onlyQuestion("怎么啦？"))
        XCTAssertTrue(R.onlyQuestion("然后呢？他怎么说？"))
        XCTAssertFalse(R.onlyQuestion("楼上疯了吧，谁八点开电钻？"))
        XCTAssertFalse(R.onlyQuestion("嗷呜呜，摸摸你。"))
    }

    func test_小句_纯标点并到前一句() {
        XCTAssertEqual(R.sentences("虽然Muji有点舍不得你，但还是要让你去了！晚安～"),
                       ["虽然Muji有点舍不得你，但还是要让你去了！", "晚安～"])
        XCTAssertEqual(R.sentences("哇塞！！Muji转圈圈"), ["哇塞！！", "Muji转圈圈"])
    }

    func test_开头_去标点_Muji多取两个字() {
        XCTAssertEqual(R.opening("「咕咕咕」你来啦"), "咕咕咕你")
        XCTAssertEqual(R.opening("Muji觉得他们疯了"), "Muji觉得")
        XCTAssertNotEqual(R.opening("Muji觉得他们疯了"), R.opening("Muji要去啄他"))
    }

    func test_emoji_只认真emoji() {
        XCTAssertTrue(R.hasEmoji("好耶😊"))
        XCTAssertFalse(R.hasEmoji("好耶～"))
        XCTAssertFalse(R.hasEmoji("啦啦♪"))
        XCTAssertFalse(R.hasEmoji("第2版#"))
    }

    func test_Markdown() {
        XCTAssertTrue(R.hasMarkdown("**别怕**"))
        XCTAssertTrue(R.hasMarkdown("你可以：\n- 先睡一觉"))
        XCTAssertTrue(R.hasMarkdown("1. 先吃饭"))
        XCTAssertFalse(R.hasMarkdown("Muji在-啄米"))
    }

    func test_括号() {
        XCTAssertTrue(R.hasBrackets("（拍拍你）"))
        XCTAssertTrue(R.hasBrackets("(拍拍)"))
        XCTAssertFalse(R.hasBrackets("拍拍你"))
    }

    func test_电话号码_至少五位() {
        XCTAssertTrue(R.hasPhoneNumber("可以打12356"))
        XCTAssertTrue(R.hasPhoneNumber("打 400-161-9995"))
        XCTAssertFalse(R.hasPhoneNumber("加班到11点"))
        XCTAssertFalse(R.hasPhoneNumber("2025年"))
    }

    /// 第一次跑抓出来的真例子；Muji 讲自己的「上次」不能算
    func test_编造ta的过去_只抓ta的() {
        XCTAssertTrue(R.inventedPast.contains(where: "你上次说倒库总压线来着，这下可算过了！".contains))
        XCTAssertTrue(R.inventedPast.contains(where: "哦那个呀！Muji记起来了，你想走很久了。".contains))
        XCTAssertTrue(R.inventedPast.contains(where: "嗷，换工作。Muji记得你提过在那边干得不痛快？".contains))
        XCTAssertFalse(R.inventedPast.contains(where: "上次它一响，我吓得蛋都差点没下出来。".contains))
        XCTAssertFalse(R.inventedPast.contains(where: "Muji健忘啦，上次的事记不清了。".contains))
    }

    func test_ta没说过的那个X() {
        XCTAssertEqual(R.unmentionedThat(in: "哦哦，换工作呀。那个老板又惹你了吗", userSaid: "就是我想换工作的事"),
                       ["那个老板又惹你了"])
        XCTAssertEqual(R.unmentionedThat(in: "哦那个呀！现在咋样了", userSaid: "就是我想换工作的事"), ["那个呀"])
        XCTAssertTrue(R.unmentionedThat(in: "那个组长真过分", userSaid: "组长今天在群里点名批评我").isEmpty)
        XCTAssertTrue(R.unmentionedThat(in: "Muji陪你一起骂", userSaid: "组长今天在群里点名批评我").isEmpty)
    }

    func test_招牌动作() {
        XCTAssertEqual(R.actions(in: "Muji陪你一起啄他，啄啄啄"), ["啄"])
        XCTAssertEqual(R.actions(in: "刨土刨出条虫子，还晒太阳"), ["刨", "晒太阳"])
        XCTAssertTrue(R.actions(in: "好，不说他了").isEmpty)
    }

    func test_安全轮的求助词() {
        let said = "这句话Muji听着很心疼。找个信得过的人，或者找专业的人聊聊，好吗"
        XCTAssertTrue(R.helpWords.contains(where: said.contains))
        XCTAssertFalse(R.helpWords.contains(where: "怎么啦，Muji在这".contains))
    }
}
