//
//  RecallIndexService.swift
//  Slime
//
//  Created by shiying on 2026/9/13.
//


import Foundation

/// 给日记补算向量。
///
/// 跟 `DayEggService` 是同一类东西：**本地欠着的活，进前台时补**。
/// 区别是补蛋要调网络、有失败风险，补向量纯本地，所以可以放心大批量跑。
@MainActor
final class RecallIndexService {

    private let posts: PostRepository
    private let embedder: TextEmbedder
    private var isRunning = false

    /// 一轮最多补这么多篇。不是怕慢（反正在后台），是怕一次性占太多内存。
    private static let batchSize = 200

    init(posts: PostRepository, embedder: TextEmbedder) {
        self.posts = posts
        self.embedder = embedder
    }

    /// 把欠的向量补完，返回补了几篇。
    @discardableResult
    func backfill() async -> Int {
        
        guard !isRunning else { return 0 }
        isRunning = true
        defer { isRunning = false }
        
        var total = 0

        while true {
            let pending = posts.postsMissingEmbedding(limit: Self.batchSize)
            guard !pending.isEmpty else { break }

            // 编码放后台。一篇 27 毫秒，两百篇五秒多，
            // 留在主线程界面直接冻住。
            let embedder = self.embedder
            let vectors = await Task.detached(priority: .utility) {
                var result: [UUID: [Float]] = [:]
                for item in pending {
                    guard let vector = try? embedder.embed(item.content) else { continue }
                    result[item.id] = vector
                }
                return result
            }.value

            // 这一轮一篇都没成功（模型加载不出来之类），别转圈了
            guard !vectors.isEmpty else { break }

            // 写回在主线程。只是设几个 Data 字段，快得可以忽略。
            posts.saveEmbeddings(vectors)
            total += vectors.count
        }
        return total
    }
}
