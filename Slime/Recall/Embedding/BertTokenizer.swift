//
//  BertTokenizer.swift
//  Slime
//
//  BERT WordPiece 分词器（中文版）。
//
//  为什么要自己写：Core ML 只能转模型，转不了分词器。
//  模型吃的是 token id 数组，把「今天又被组长说了」变成 [101, 791, 1921, ...]
//  这一步必须在 Swift 这边复刻，而且要跟 Python 那边**逐个 id 对上** ——
//  错一个 id，向量就是错的，而且不会报错，只会静静地检索出一堆不相干的东西。
//  所以 BertTokenizerTests 里钉了一批黄金对照，改这个文件之前先看那些用例。
//
//  两个反直觉的地方（都是 bge-small-zh 的配置决定的，不是我们选的）：
//   ① do_lower_case = false —— **不做小写化**。所以 "ABC" 在词表里查不到，
//      整个变成 [UNK]。看着像 bug，其实是模型本来的行为，改了反而对不上。
//   ② 中文按**字**切，不是按词。「组长」是两个 token，不是一个。
//

import Foundation

nonisolated final class BertTokenizer: Sendable {

    /// 模型转换时固定了序列长度，这里必须一致。
    static let maxLength = 128

    private let vocab: [String: Int32]
    private let unkId: Int32
    private let clsId: Int32
    private let sepId: Int32

    /// 一个词最多这么多字符，超了直接判 [UNK]。BERT 原版就是 100。
    private static let maxCharsPerWord = 100

    enum TokenizerError: Error {
        case vocabNotFound
        case vocabMalformed
    }

    /// - Parameter url: bge-vocab.txt，一行一个 token，行号就是 id。
    init(vocabURL url: URL) throws {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
            throw TokenizerError.vocabNotFound
        }
        var table: [String: Int32] = [:]
        for (index, line) in raw.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let token = String(line)
            guard !token.isEmpty else { continue }
            table[token] = Int32(index)
        }
        guard let unk = table["[UNK]"], let cls = table["[CLS]"], let sep = table["[SEP]"] else {
            throw TokenizerError.vocabMalformed
        }
        vocab = table
        unkId = unk
        clsId = cls
        sepId = sep
    }

    /// 便利构造：从 App bundle 里读词表。
    convenience init() throws {
        guard let url = Bundle.main.url(forResource: "bge-vocab", withExtension: "txt") else {
            throw TokenizerError.vocabNotFound
        }
        try self.init(vocabURL: url)
    }

    // MARK: - 对外

    /// 编码成模型要的三个定长数组。
    ///
    /// [PAD] 的 id 是 0，所以补零就是补 PAD；attention mask 用 1/0 告诉模型
    /// 哪些位置是真内容、哪些是凑数的，不然 padding 会参与注意力算出脏结果。
    /// tokenTypeIds 全零 —— 那是给「句子对」任务用的，我们只有单句。
    func encode(_ text: String) -> (ids: [Int32], mask: [Int32], tokenTypeIds: [Int32]) {
        var ids = tokenize(text)

        // 留两格给 [CLS] 和 [SEP]
        let room = Self.maxLength - 2
        if ids.count > room { ids = Array(ids.prefix(room)) }

        var full = [clsId] + ids + [sepId]
        let realCount = full.count
        full += Array(repeating: 0, count: Self.maxLength - realCount)

        let mask = (0..<Self.maxLength).map { Int32($0 < realCount ? 1 : 0) }
        return (full, mask, Array(repeating: 0, count: Self.maxLength))
    }

    /// 只切词不加特殊 token，测试和调试用。
    func tokenize(_ text: String) -> [Int32] {
        basicTokenize(text).flatMap { wordPiece($0) }
    }

    // MARK: - 第一步：粗切

    /// 清掉控制字符、给中文字和标点两边加空格，再按空白切开。
    ///
    /// 「中文字两边加空格」就是「中文按字切」的实现方式 ——
    /// 加完空格之后，按空白一切，每个汉字自然就单独成词了。
    private func basicTokenize(_ text: String) -> [String] {
        var spaced = String.UnicodeScalarView()

        for scalar in text.unicodeScalars {
            let cp = scalar.value
            // 0 是空字符，0xFFFD 是替换字符，都当噪声丢掉
            if cp == 0 || cp == 0xFFFD || isControl(scalar) { continue }

            if isWhitespace(scalar) {
                spaced.append(" ")
            } else if isChinese(cp) || isPunctuation(scalar) {
                spaced.append(" ")
                spaced.append(scalar)
                spaced.append(" ")
            } else {
                spaced.append(scalar)
            }
        }

        return String(spaced).split(separator: " ").map(String.init)
    }

    // MARK: - 第二步：WordPiece

    /// 贪心最长匹配：从整个词开始试，查不到就砍掉最后一个字符再试。
    /// 第一段之后的每一段都要加 "##" 前缀，这是 WordPiece 表示「词中间」的方式。
    /// 任何一段都查不到，整个词判 [UNK]（注意是整个词，不是那一段）。
    private func wordPiece(_ word: String) -> [Int32] {
        let chars = Array(word.unicodeScalars)
        guard chars.count <= Self.maxCharsPerWord else { return [unkId] }

        var result: [Int32] = []
        var start = 0

        while start < chars.count {
            var end = chars.count
            var matched: Int32?

            while start < end {
                var piece = String(String.UnicodeScalarView(chars[start..<end]))
                if start > 0 { piece = "##" + piece }
                if let id = vocab[piece] {
                    matched = id
                    break
                }
                end -= 1
            }

            guard let id = matched else { return [unkId] }
            result.append(id)
            start = end
        }
        return result
    }

    // MARK: - 字符分类

    /// CJK 统一汉字的各个区段。抄的 BERT 原版范围，别改。
    /// 注意它**不含**中文标点（那些走 isPunctuation），只管汉字本身。
    private func isChinese(_ cp: UInt32) -> Bool {
        (0x4E00...0x9FFF).contains(cp)   || (0x3400...0x4DBF).contains(cp)   ||
        (0x20000...0x2A6DF).contains(cp) || (0x2A700...0x2B73F).contains(cp) ||
        (0x2B740...0x2B81F).contains(cp) || (0x2B820...0x2CEAF).contains(cp) ||
        (0xF900...0xFAFF).contains(cp)   || (0x2F800...0x2FA1F).contains(cp)
    }

    private func isWhitespace(_ s: Unicode.Scalar) -> Bool {
        if s == " " || s == "\t" || s == "\n" || s == "\r" { return true }
        return s.properties.generalCategory == .spaceSeparator
    }

    private func isControl(_ s: Unicode.Scalar) -> Bool {
        if s == "\t" || s == "\n" || s == "\r" { return false }   // 这三个当空白处理
        switch s.properties.generalCategory {
        case .control, .format, .lineSeparator, .paragraphSeparator: return true
        default: return false
        }
    }

    /// ASCII 里那四段非字母数字的区间，BERT 原版也把它们算作标点
    /// （比如 `$`、`+`、`@` 在 Unicode 里不属于标点类，但这里要算）。
    private func isPunctuation(_ s: Unicode.Scalar) -> Bool {
        let cp = s.value
        if (33...47).contains(cp) || (58...64).contains(cp) ||
           (91...96).contains(cp) || (123...126).contains(cp) { return true }

        switch s.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
             .initialPunctuation, .finalPunctuation, .otherPunctuation: return true
        default: return false
        }
    }
}
