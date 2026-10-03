//
//  TextEmbedder.swift
//  Slime
//
//  Created by shiying on 2026/9/11.
//

import Foundation
import CoreML

/// 端侧向量：把一句话编码成 512 维向量，给检索的「向量那一路」用。
///
/// **模型第一次用到时才加载，而且只在后台线程上用**（10-02 改）。
/// 装完或更新后第一次加载，Core ML 要为这台设备把模型编译一遍 —— iPhone 13 Pro 实测 **2 秒**，之后有缓存只要 80 毫秒。
/// 以前在 `SceneDelegate` 里同步加载，这 2 秒全是启动白屏。
/// 现在建出来只是个空壳；组合根在首页出来之后让它在后台预热（`warmUp`），用的地方（补向量、聊天检索）本来就在后台。
nonisolated final class TextEmbedder: @unchecked Sendable {
    static let queryPrefix = "为这个句子生成表示以用于检索相关文章："

    private static let inputNames = ["input_ids", "attention_mask", "token_type_ids"]
    private static let outputName = "embedding"

    enum EmbedderError: Error {
        case modelNotFound
        case unexpectedOutput
    }

    /// 模型和分词器，一起加载、一起有
    private struct Loaded {
        let model: MLModel
        let tokenizer: BertTokenizer
    }

    /// nil = 还没加载过。加载过就记下结果 —— **失败也记**，不然每次用到都再花 2 秒失败一次
    private var loaded: Result<Loaded, Error>?
    /// 护着 `loaded`：预热、补向量、聊天检索可能同时在几条后台线程上第一次用到它
    private let lock = NSLock()

    /// 什么都不加载，所以很快
    init() {}

    /// 提前在后台把模型加载好，第一次聊天就不用等。**别在主线程上调** —— 第一次可能要 2 秒
    func warmUp() {
        _ = try? load()
    }

    private func load() throws -> Loaded {
        lock.lock()
        defer { lock.unlock() }
        if let loaded {
            return try loaded.get()
        }
        let result = Result { try Self.loadFromBundle() }
        loaded = result
        return try result.get()
    }

    private static func loadFromBundle() throws -> Loaded {
        guard let url = Bundle.main.url(forResource: "BGESmallZh", withExtension: "mlmodelc") else {
            throw EmbedderError.modelNotFound
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        return Loaded(model: try MLModel(contentsOf: url, configuration: configuration),
                      tokenizer: try BertTokenizer())
    }

    func embed(_ text: String) throws -> [Float] {
        let loaded = try load()
        let (ids, mask, types) = loaded.tokenizer.encode(text)
        let features = try MLDictionaryFeatureProvider(dictionary: [
            Self.inputNames[0]: MLFeatureValue(multiArray: try intArray(ids)),
            Self.inputNames[1]: MLFeatureValue(multiArray: try intArray(mask)),
            Self.inputNames[2]: MLFeatureValue(multiArray: try intArray(types)),
        ])
        let output = try loaded.model.prediction(from: features)
        guard let embedding = output.featureValue(for: Self.outputName)?.multiArrayValue else {
            throw EmbedderError.unexpectedOutput
        }
        return floats(from: embedding)
    }

    func embedQuery(_ text: String) throws -> [Float] {
        try embed(Self.queryPrefix + text)
    }

    private func intArray(_ values: [Int32]) throws -> MLMultiArray {
        let array = try MLMultiArray(shape: [1, NSNumber(value: BertTokenizer.maxLength)], dataType: .int32)
        let buffer = array.dataPointer.bindMemory(to: Int32.self, capacity: values.count)
        for (i, v) in values.enumerated() {
            buffer[i] = v
        }
        return array
    }

    private func floats(from array: MLMultiArray) -> [Float] {
        let buffer = array.dataPointer.bindMemory(to: Float32.self, capacity: array.count)
        return Array(UnsafeBufferPointer(start: buffer, count: array.count))
    }
}
