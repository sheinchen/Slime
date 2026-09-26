//
//  RecallReranker.swift
//  Slime
//
//  两阶段检索的第二阶段：把 RRF 给出的宽候选收窄成 0...3 条真正相关的记忆。
//
//  这里只有协议和「业务能信什么」（白名单、去重、上限、失败兜底）。
//  怎么问模型在 Services/AI/MemoryReranker.swift。
//

import Foundation

@MainActor
protocol RecallReranking {
    func rerank(message: String,
                recentTurns: [AIChatMessage],
                candidates: [RecallHit]) async throws -> RecallSelection
}

nonisolated struct RecallSelection: Sendable {
    let selectedDocumentIDs: [UUID]
    let reason: String

    static let empty = RecallSelection(selectedDocumentIDs: [], reason: "")
}

struct RecallRerankOutcome {
    let hits: [RecallHit]
    let reason: String
    let errorDescription: String?
}

/// 把「调模型」与「业务可以信什么」隔开。所有重排实现都要再过一遍
/// 候选白名单、去重和数量上限；重排失败时 fail closed，返回空记忆。
@MainActor
enum RecallRerankCoordinator {

    static func select(message: String,
                       recentTurns: [AIChatMessage],
                       candidates: [RecallHit],
                       using reranker: RecallReranking,
                       limit: Int = 3) async -> RecallRerankOutcome {
        guard limit > 0, !candidates.isEmpty else {
            return RecallRerankOutcome(hits: [], reason: "", errorDescription: nil)
        }

        do {
            let selection = try await reranker.rerank(message: message,
                                                       recentTurns: recentTurns,
                                                       candidates: candidates)
            // Core Data 正常情况下不会给出重复 UUID；这里仍按「第一条排名更高」
            // 保留首次出现，避免边界数据异常时 Dictionary 初始化直接 trap。
            var byID: [UUID: RecallHit] = [:]
            for candidate in candidates where byID[candidate.document.id] == nil {
                byID[candidate.document.id] = candidate
            }
            var seen = Set<UUID>()
            var hits: [RecallHit] = []

            for id in selection.selectedDocumentIDs {
                guard seen.insert(id).inserted, let hit = byID[id] else { continue }
                hits.append(hit)
                if hits.count == limit { break }
            }

            return RecallRerankOutcome(hits: hits,
                                       reason: selection.reason,
                                       errorDescription: nil)
        } catch {
            return RecallRerankOutcome(hits: [],
                                       reason: "",
                                       errorDescription: String(describing: error))
        }
    }
}

/// 模型只能返回 `m0...m9` 这组临时 id，真实 UUID 不发给模型。
/// 返回值经过这层白名单后才会参与业务。
nonisolated enum RecallSelectionRule {

    static func selectedDocumentIDs(from tokens: [String],
                                    candidateIDs: [UUID],
                                    limit: Int = 3) -> [UUID] {
        guard limit > 0, !candidateIDs.isEmpty else { return [] }

        let allowed = Dictionary(uniqueKeysWithValues:
            candidateIDs.enumerated().map { ("m\($0.offset)", $0.element) })
        var result: [UUID] = []
        var seen = Set<UUID>()

        for raw in tokens {
            let token = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard let id = allowed[token] else { continue }
            guard seen.insert(id).inserted else { continue }
            result.append(id)
            if result.count == limit { break }
        }
        return result
    }
}
