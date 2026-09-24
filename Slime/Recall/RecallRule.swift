//
//  File.swift
//  Slime
//
//  Created by shiying on 2026/9/10.
//

import Foundation

nonisolated struct RecallDocument: Hashable {
    let id: UUID
    let date: Date
    let text: String
    /// nil = 写的时候 AI 没读上。情绪那一路给不了它分，关键词和向量照常。
    let emotion: SlimeEmotion?
}

nonisolated struct RecallQuery {
    let keywords: [String]
    let emotion: SlimeEmotion?
}

nonisolated enum RecallChannel: String, CaseIterable {
    case keyword
    case vector
    case emotion
}

nonisolated struct RecallHit: Hashable {
    let document: RecallDocument
    let score: Double
    let ranks: [RecallChannel: Int]
}

nonisolated struct RecallCandidate {
    let document: RecallDocument
    let vector: [Float]?
}


nonisolated enum RecallRule {
    
    static let rrfK = 10.0
    
    static func rank(documents: [RecallDocument],
                     query: RecallQuery,
                     similarities: [UUID: Double] = [:],
                     limit: Int = 5,
                     channelLimit: Int = 10) -> [RecallHit] {
        guard limit > 0, channelLimit > 0 else { return [] }

        // 关键词和向量负责「把候选捞上来」。每路先截断，再做 RRF：
        // 向量对几乎每篇日记都有一个正分，不截断就会让尾部噪声也持续投票。
        let keywordRanking = ranking(documents, limit: channelLimit) {
            keywordScore($0, keywords: query.keywords)
        }
        let vectorRanking = ranking(documents, limit: channelLimit) {
            similarities[$0.id] ?? 0
        }

        // 「都是难过」不等于「是同一件事」。情绪只能给已被关键词/向量
        // 捞上来的候选加分，不能单独创造候选。
        let candidateIndexes = Set(keywordRanking.keys).union(vectorRanking.keys)
        guard !candidateIndexes.isEmpty else { return [] }

        let emotionRanking = ranking(documents,
                                     allowedIndexes: candidateIndexes,
                                     limit: channelLimit) {
            emotionScore($0, query.emotion)
        }

        let rankings: [RecallChannel: [Int: Int]] = [
            .keyword: keywordRanking,
            .vector: vectorRanking,
            .emotion: emotionRanking
        ]

        var hits: [RecallHit] = []
        for (index, document) in documents.enumerated() where candidateIndexes.contains(index) {
            var score = 0.0
            var ranks: [RecallChannel: Int] = [:]

            for (channel, ranking) in rankings {
                guard let rank = ranking[index] else { continue }
                ranks[channel] = rank
                score += 1.0 / (rrfK + Double(rank))
            }

            hits.append(RecallHit(document: document, score: score, ranks: ranks))
        }

        return Array(hits.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            // 时间不参与排名。UUID 只用来让同分结果稳定，
            // 避免候选原始顺序（生产里是新到旧）偷偷变成近因权重。
            return $0.document.id.uuidString < $1.document.id.uuidString
        }.prefix(limit))
    }
    
    //MARK: - 三路各自打分
    private static func keywordScore(_ document: RecallDocument, keywords: [String]) -> Double {
        guard !keywords.isEmpty else { return 0 }
        let text = document.text.lowercased()
        return Double(keywords.filter { text.contains($0.lowercased()) }.count)
    }
    
    private static func emotionScore(_ document: RecallDocument,
                                         _ queryEmotion: SlimeEmotion?) -> Double {
            // 那篇没被 AI 读过就没有情绪 —— 给 0 分，而不是猜一个再比
            guard let queryEmotion, let documentEmotion = document.emotion else { return 0 }
            if documentEmotion == queryEmotion { return 2 }
            return isNegative(documentEmotion) == isNegative(queryEmotion) ? 1 : 0
        }
    
    private static func isNegative(_ emotion: SlimeEmotion) -> Bool {
            switch emotion {
            case .sad, .angry, .anxious, .tired: return true
            case .happy, .calm:                  return false
            }
        }
    
    // MARK: - 打分转排名
    
    private static func ranking(_ documents: [RecallDocument],
                                allowedIndexes: Set<Int>? = nil,
                                limit: Int,
                                score: (RecallDocument) -> Double) -> [Int: Int] {
        let scored = documents.enumerated()
                 .filter { allowedIndexes?.contains($0.offset) ?? true }
                 .map { (index: $0.offset, score: score($0.element)) }
                 .filter { $0.score > 0 }
                 .sorted {
                     if $0.score != $1.score { return $0.score > $1.score }
                     return documents[$0.index].id.uuidString < documents[$1.index].id.uuidString
                 }
                 .prefix(limit)

             var result: [Int: Int] = [:]
             for (position, item) in scored.enumerated() {
                 result[item.index] = position + 1
             }
             return result
    }
}
