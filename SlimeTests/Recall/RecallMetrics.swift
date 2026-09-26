//
//  RecallMetrics.swift
//  SlimeTests
//
//  两个检索指标。单独拎出来是为了让纯函数 eval 和向量 eval 用**同一把尺子** ——
//  各写一份的话，某天改了其中一个，那张对比表就不再可比了，
//  而你会以为是检索变好了。
//

import Foundation
@testable import Slime

nonisolated enum RecallMetrics {

    /// 前 k 名里盖住了多少条标注为相关的。
    static func recallAtK(_ hits: [RecallHit], relevant: Set<Date>, k: Int = 5) -> Double {
        guard !relevant.isEmpty else { return 0 }
        let topK = Set(hits.prefix(k).map(\.document.date))
        return Double(relevant.intersection(topK).count) / Double(relevant.count)
    }

    /// 第一个相关结果排第几的倒数。排第 1 得 1.0，排第 4 得 0.25，一个都没有得 0。
    /// 它比 recall 更能反映「用户第一眼看到的是不是对的」。
    static func reciprocalRank(_ hits: [RecallHit], relevant: Set<Date>) -> Double {
        for (i, hit) in hits.enumerated() where relevant.contains(hit.document.date) {
            return 1.0 / Double(i + 1)
        }
        return 0
    }
}
