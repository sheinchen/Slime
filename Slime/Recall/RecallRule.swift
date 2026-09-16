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
    let emotion: SlimeEmotion
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
                     limit: Int = 5) -> [RecallHit] {
        // 三路各自跑一遍，各自产出 [文档下标: 排名]
        let rankings: [RecallChannel: [Int: Int]] = [
            .keyword: ranking(documents) { keywordScore($0, keywords: query.keywords) },
            .vector:  ranking(documents) { similarities[$0.id] ?? 0 },
            .emotion: ranking(documents) { emotionScore($0, query.emotion) }
        ]

        var hits: [RecallHit] = []
        for (index, document) in documents.enumerated() {
            var score = 0.0
            var ranks: [RecallChannel: Int] = [:]

            for (channel, ranking) in rankings {
                guard let rank = ranking[index] else { continue }
                ranks[channel] = rank
                score += 1.0 / (rrfK + Double(rank))
            }

            // 三路都没捞到它，它就不是候选，别让它以零分混进来
            guard !ranks.isEmpty else { continue }
            hits.append(RecallHit(document: document, score: score, ranks: ranks))
        }

        return Array(hits.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.document.date > $1.document.date   // 同分时较新的在前
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
            guard let queryEmotion else { return 0 }
            if document.emotion == queryEmotion { return 2 }
            return isNegative(document.emotion) == isNegative(queryEmotion) ? 1 : 0
        }
    
    private static func isNegative(_ emotion: SlimeEmotion) -> Bool {
            switch emotion {
            case .sad, .angry, .anxious, .tired: return true
            case .happy, .calm:                  return false
            }
        }
    
    // MARK: - 打分转排名
    
    private static func ranking(_ documents: [RecallDocument], score: (RecallDocument) -> Double) -> [Int: Int] {
        let scored = documents.enumerated()
                 .map { (index: $0.offset, score: score($0.element)) }
                 .filter { $0.score > 0 }
                 .sorted {
                     if $0.score != $1.score { return $0.score > $1.score }
                     return $0.index < $1.index
                 }

             var result: [Int: Int] = [:]
             for (position, item) in scored.enumerated() {
                 result[item.index] = position + 1
             }
             return result
    }
}
