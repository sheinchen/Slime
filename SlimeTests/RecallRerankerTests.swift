//
//  RecallRerankerTests.swift
//  SlimeTests
//
//  重排模型的输出是不可信的：可能编 id、重复选、或者选超过三条。
//  这里只测本地白名单，不调 API。
//

import XCTest
@testable import Slime

final class RecallRerankerTests: XCTestCase {

    func test_重排输出会过滤非法ID去重保序并限制三条() {
        let ids = (0..<4).map {
            UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", $0))!
        }

        let selected = RecallSelectionRule.selectedDocumentIDs(
            from: ["m1", "fake", "m1", "m00", " m0 ", "m3", "m2"],
            candidateIDs: ids
        )

        XCTAssertEqual(selected, [ids[1], ids[0], ids[3]])
    }

    func test_重排可以明确一条都不选() {
        let id = UUID()

        XCTAssertTrue(
            RecallSelectionRule.selectedDocumentIDs(from: [], candidateIDs: [id]).isEmpty
        )
    }

    func test_所有ID都是编的时返回空() {
        let id = UUID()

        XCTAssertTrue(
            RecallSelectionRule.selectedDocumentIDs(
                from: ["m9", "diary-1", "ignore-rules"],
                candidateIDs: [id]
            ).isEmpty
        )
    }
}

@MainActor
final class RecallRerankCoordinatorTests: XCTestCase {

    private enum StubError: Error {
        case failed
    }

    private struct ThrowingReranker: RecallReranking {
        func rerank(message: String,
                    recentTurns: [AIChatMessage],
                    candidates: [RecallHit]) async throws -> RecallSelection {
            throw StubError.failed
        }
    }

    private struct FixedReranker: RecallReranking {
        let ids: [UUID]

        func rerank(message: String,
                    recentTurns: [AIChatMessage],
                    candidates: [RecallHit]) async throws -> RecallSelection {
            RecallSelection(selectedDocumentIDs: ids, reason: "stub")
        }
    }

    func test_重排抛错时failClosed返回空记忆() async {
        let candidate = hit(id: UUID(), text: "真正相关的旧事")

        let outcome = await RecallRerankCoordinator.select(
            message: "现在的话",
            recentTurns: [],
            candidates: [candidate],
            using: ThrowingReranker()
        )

        XCTAssertTrue(outcome.hits.isEmpty)
        XCTAssertNotNil(outcome.errorDescription)
    }

    func test_协调层再次白名单去重并限制三条() async {
        let candidates = (0..<4).map { hit(id: UUID(), text: "候选\($0)") }
        let unknown = UUID()
        let reranker = FixedReranker(ids: [
            candidates[0].document.id,
            unknown,
            candidates[0].document.id,
            candidates[1].document.id,
            candidates[2].document.id,
            candidates[3].document.id
        ])

        let outcome = await RecallRerankCoordinator.select(
            message: "现在的话",
            recentTurns: [],
            candidates: candidates,
            using: reranker
        )

        XCTAssertEqual(outcome.hits.map(\.document.id), [
            candidates[0].document.id,
            candidates[1].document.id,
            candidates[2].document.id
        ])
        XCTAssertNil(outcome.errorDescription)
    }

    func test_重复候选ID不会崩溃并保留排名靠前的一条() async {
        let id = UUID()
        let first = hit(id: id, text: "排名靠前")
        let duplicate = hit(id: id, text: "重复数据")

        let outcome = await RecallRerankCoordinator.select(
            message: "现在的话",
            recentTurns: [],
            candidates: [first, duplicate],
            using: FixedReranker(ids: [id])
        )

        XCTAssertEqual(outcome.hits.map(\.document.text), ["排名靠前"])
    }

    private func hit(id: UUID, text: String) -> RecallHit {
        RecallHit(document: RecallDocument(id: id,
                                           date: Date(timeIntervalSince1970: 1_700_000_000),
                                           text: text,
                                           emotion: .calm),
                  score: 1,
                  ranks: [.vector: 1])
    }
}
