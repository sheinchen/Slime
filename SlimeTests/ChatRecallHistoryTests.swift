//
//  ChatRecallHistoryTests.swift
//  SlimeTests
//

import XCTest
@testable import Slime

@MainActor
final class ChatRecallHistoryTests: XCTestCase {

    func test_检索历史不重复携带当前用户消息() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let messages = [
            ChatMessageItem(id: UUID(), role: .slime, content: "旧回复", createdAt: now),
            ChatMessageItem(id: UUID(), role: .user, content: "旧问题", createdAt: now),
            ChatMessageItem(id: UUID(), role: .user, content: "当前这句", createdAt: now)
        ]

        let turns = ChatViewModel.recallTurns(from: messages, limit: 8)

        XCTAssertEqual(turns.map(\.role), ["assistant", "user"])
        XCTAssertEqual(turns.map(\.content), ["旧回复", "旧问题"])
        XCTAssertFalse(turns.contains { $0.content == "当前这句" })
    }
}
