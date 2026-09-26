//
//  RecallVectorEvalTests.swift
//  SlimeTests
//
//  三种配置跑同一批用例，产出那张对比表：
//    baseline（关键词 + 情绪）/ 仅向量 / 三路融合
//
//  三种配置走的是**同一个 RecallRule.rank**，差别只在传不传 similarities、
//  传不传 keywords 和 emotion。这正是当初把向量做成外部注入的回报：
//  换配置不用改一行实现，也就不存在「对比的是两套不同代码」这种脏结果。
//
//  这个文件会真的加载 Core ML 模型，比纯函数 eval 慢一个量级。
//

import XCTest
@testable import Slime

final class RecallVectorEvalTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func test_三路对比eval() throws {
        let embedder: TextEmbedder
        do {
            embedder = try TextEmbedder()
        } catch {
            throw XCTSkip("模型或词表没打进 bundle：\(error)")
        }

        let documents = RecallEvalCorpus.documents(now: now)

        // 日记不加前缀，查询才加 —— bge 的非对称检索用法。
        let started = Date()
        var docVectors: [UUID: [Float]] = [:]
        for d in documents { docVectors[d.id] = try embedder.embed(d.text) }
        let msPerDoc = Date().timeIntervalSince(started) / Double(documents.count) * 1000

        let labels = ["baseline", "仅向量", "融合·不截断", "生产·每路top10",
                      "融合·仅向量top10", "融合·仅向量top5"]
        var recallSums = [Double](repeating: 0, count: labels.count)
        var recall10Sums = [Double](repeating: 0, count: labels.count)
        var mrrSums = [Double](repeating: 0, count: labels.count)
        var rows: [String] = []

        for c in RecallEvalCorpus.cases {
            let relevant = RecallEvalCorpus.relevantDates(c, now: now)

            // name 就是用户说的那句原话，正好当查询用
            let queryVector = try embedder.embedQuery(c.name)
            var similarities: [UUID: Double] = [:]
            for (id, vector) in docVectors {
                similarities[id] = Double(cosine(queryVector, vector))
            }

            let runs = [
                // 只有关键词和情绪，向量那一路传空字典
                RecallRule.rank(documents: documents, query: c.query,
                                limit: 20, channelLimit: documents.count),
                // 只有向量：keywords 空、emotion nil，另两路自然全不上榜
                RecallRule.rank(documents: documents,
                                query: RecallQuery(keywords: [], emotion: nil),
                                similarities: similarities, limit: 20,
                                channelLimit: documents.count),
                // 三路齐开，向量不截断：它对每篇都有正分，会贡献一个完整排名
                RecallRule.rank(documents: documents, query: c.query,
                                similarities: similarities, limit: 20,
                                channelLimit: documents.count),
                // 生产配置：关键词/向量各只保留前 10，情绪只给这些候选加分
                RecallRule.rank(documents: documents, query: c.query,
                                similarities: similarities, limit: 20,
                                channelLimit: 10),
                // 只让向量贡献它最有把握的前 10 / 前 5
                RecallRule.rank(documents: documents, query: c.query,
                                similarities: topK(similarities, 10), limit: 20,
                                channelLimit: documents.count),
                RecallRule.rank(documents: documents, query: c.query,
                                similarities: topK(similarities, 5), limit: 20,
                                channelLimit: documents.count),
            ]

            var cells: [String] = []
            for (i, hits) in runs.enumerated() {
                let recall5 = RecallMetrics.recallAtK(hits, relevant: relevant, k: 5)
                // 检索层的下游是 LLM 重排，真正要交出去的是十来条候选。
                // recall@10 才是这一层该被考核的指标，@5 只是参考。
                let recall10 = RecallMetrics.recallAtK(hits, relevant: relevant, k: 10)
                let mrr = RecallMetrics.reciprocalRank(hits, relevant: relevant)
                recallSums[i] += recall5
                recall10Sums[i] += recall10
                mrrSums[i] += mrr
                cells.append(String(format: "%.2f/%.2f", recall5, recall10))
            }

            rows.append("""

                ── #\(c.id) \(c.name)
                   \(zip(labels, cells).map { "\($0) \($1)" }.joined(separator: "   "))
                   生产·每路top10 的前 5 名
                \(top5(runs[3], relevant: relevant))
                """)
        }

        let n = Double(RecallEvalCorpus.cases.count)
        var header = """
            检索 eval · 三路对比（每格是 recall@5 / recall@10）
            语料 \(RecallEvalCorpus.entries.count) 篇   用例 \(RecallEvalCorpus.cases.count) 条   rrfK \(RecallRule.rrfK)
            单条编码耗时 \(String(format: "%.1f", msPerDoc)) ms（模拟器，含分词）

            检索层下游还有一次 LLM 重排，真正交出去的是十来条候选，
            所以 recall@10 才是这一层该被考核的指标。

            """
        for (i, label) in labels.enumerated() {
            header += "\(label)\tr@5 \(String(format: "%.2f", recallSums[i] / n))"
                    + "   r@10 \(String(format: "%.2f", recall10Sums[i] / n))"
                    + "   MRR \(String(format: "%.2f", mrrSums[i] / n))\n"
        }

        let attachment = XCTAttachment(string: header + rows.joined(separator: "\n"))
        attachment.name = "recall-vector-eval.txt"
        attachment.lifetime = .keepAlways
        add(attachment)

        // 融合的价值在 recall@10 上：两路各自的命中都该被纳进候选，
        // 至于谁排前面，交给下游的 LLM 重排去分辨。
        XCTAssertGreaterThan(recall10Sums.dropFirst(2).max() ?? 0,
                             max(recall10Sums[0], recall10Sums[1]),
                             "融合的 recall@10 应该严格高于任何单路")
    }

    /// 只保留相似度最高的 k 篇，其余不进这一路的排名。
    /// RRF 的标准做法是各路先各取 top-k 再融合，否则密集的一路会淹掉稀疏的一路。
    private func topK(_ similarities: [UUID: Double], _ k: Int) -> [UUID: Double] {
        Dictionary(uniqueKeysWithValues:
            similarities.sorted { $0.value > $1.value }.prefix(k).map { ($0.key, $0.value) })
    }

    /// 模型里已经做过 L2 归一化，所以点积就是余弦相似度。
    /// 生产代码里这里该换成 Accelerate 的 vDSP_dotpr，512 维乘两千篇会有感觉。
    private func cosine(_ a: [Float], _ b: [Float]) -> Float {
        zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
    }

    private func top5(_ hits: [RecallHit], relevant: Set<Date>) -> String {
        hits.prefix(5).enumerated().map { i, hit in
            let mark = relevant.contains(hit.document.date) ? "✓" : " "
            let ago = RecallEvalCorpus.daysAgo(hit.document.date, from: now)
            let by = RecallChannel.allCases.compactMap { channel -> String? in
                guard let rank = hit.ranks[channel] else { return nil }
                return "\(channel.rawValue)#\(rank)"
            }.joined(separator: " ")
            return "   \(mark) \(i + 1). [\(ago)天前] \(hit.document.text.prefix(22))  ← \(by)"
        }.joined(separator: "\n")
    }
}
