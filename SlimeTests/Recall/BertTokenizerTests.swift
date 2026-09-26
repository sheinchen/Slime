//
//  BertTokenizerTests.swift
//  SlimeTests
//
//  分词器的黄金对照。**这些 id 是从 Python 那边的 transformers 直接导出来的**，
//  不是手算的，也不能手改 —— 它们是「Swift 实现有没有跑偏」的唯一判据。
//
//  为什么值得单独测：分词错了不会报错。它只会安静地把「组长」编成别的 id，
//  然后模型输出一个看着很正常的 512 维向量，检索结果一塌糊涂，
//  而你会以为是模型不行、是融合权重不对，查到天亮都查不到这里。
//
//  重导对照的命令在 docs 里，改词表或换模型之后必须重导。
//

import XCTest
@testable import Slime

final class BertTokenizerTests: XCTestCase {

    private func makeTokenizer() throws -> BertTokenizer {
        let bundle = Bundle(for: BertTokenizer.self)
        guard let url = bundle.url(forResource: "bge-vocab", withExtension: "txt") else {
            throw XCTSkip("""
                词表没打进 bundle。去 Xcode 里看 Slime target 的 Build Phases →
                Copy Bundle Resources，确认 bge-vocab.txt 在里面。
                """)
        }
        return try BertTokenizer(vocabURL: url)
    }

    /// (原文, 期望的完整 id 序列，含首尾的 [CLS] 101 和 [SEP] 102)
    private let golden: [(String, [Int32])] = [
        ("今天又被组长说了",
         [101, 791, 1921, 1348, 6158, 5299, 7270, 6432, 749, 102]),

        ("橘子这两天不太吃东西，带去医院抽了血",
         [101, 3580, 2094, 6821, 697, 1921, 679, 1922, 1391, 691,
          6205, 8024, 2372, 1343, 1278, 7368, 2853, 749, 6117, 102]),

        // do_lower_case = false，所以 "ABC" 查不到，整个变 [UNK]=100
        ("ABC大写", [101, 100, 1920, 1091, 102]),

        // 数字和半角标点各自成 token
        ("今天 3 点开会!", [101, 791, 1921, 124, 4157, 2458, 833, 106, 102]),

        // 小写英文能查到（said/ok），全角冒号是标点单独切
        ("组长said：ok", [101, 5299, 7270, 8385, 8038, 8270, 102]),

        // 空串也要能过，只剩 [CLS][SEP]
        ("", [101, 102]),
    ]

    func test_分词结果与Python逐个id一致() throws {
        let tokenizer = try makeTokenizer()
        for (text, expected) in golden {
            let ids = tokenizer.encode(text).ids
            XCTAssertEqual(Array(ids.prefix(expected.count)), expected,
                           "「\(text)」编出来的 id 跟 Python 对不上")
        }
    }

    func test_padding补零且mask标出真实长度() throws {
        let tokenizer = try makeTokenizer()
        let (ids, mask, types) = tokenizer.encode("今天又被组长说了")
        let real = 10   // golden 里第一条的长度

        XCTAssertEqual(ids.count, BertTokenizer.maxLength)
        XCTAssertEqual(mask.count, BertTokenizer.maxLength)

        // [PAD] 的 id 就是 0，所以补零即补 PAD
        XCTAssertTrue(ids[real...].allSatisfy { $0 == 0 })
        XCTAssertTrue(mask[..<real].allSatisfy { $0 == 1 })
        XCTAssertTrue(mask[real...].allSatisfy { $0 == 0 })

        // 单句任务，token type 全零
        XCTAssertTrue(types.allSatisfy { $0 == 0 })
    }

    func test_超长文本截断后仍以SEP收尾() throws {
        let tokenizer = try makeTokenizer()
        let long = String(repeating: "今天又被组长说了心情很差", count: 40)
        let (ids, mask, _) = tokenizer.encode(long)

        XCTAssertEqual(ids.count, BertTokenizer.maxLength)
        XCTAssertEqual(ids.first, 101)
        // 截断之后最后一个位置必须还是 [SEP]，不能被内容挤掉
        XCTAssertEqual(ids.last, 102)
        XCTAssertTrue(mask.allSatisfy { $0 == 1 }, "满长度时 mask 应该全 1")
    }

    func test_中文按字切不按词() throws {
        let tokenizer = try makeTokenizer()
        // 「组长」是两个 token，不是一个 —— 这是模型的既定行为
        XCTAssertEqual(tokenizer.tokenize("组长"), [5299, 7270])
    }
}
