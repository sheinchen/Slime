//
//  TextEmbedder.swift
//  Slime
//
//  Created by shiying on 2026/9/11.
//

import Foundation
import CoreML

nonisolated final class TextEmbedder: @unchecked Sendable {
    static let queryPrefix = "为这个句子生成表示以用于检索相关文章："
    private let model: MLModel
    private let tokenizer: BertTokenizer
    
    private static let inputNames = ["input_ids", "attention_mask", "token_type_ids"]
    private static let outputName = "embedding"
    
    enum EmbedderError: Error {
           case modelNotFound
           case unexpectedOutput
       }

    
    init() throws {
        guard let url = Bundle.main.url(forResource: "BGESmallZh", withExtension: "mlmodelc") else {
                    throw EmbedderError.modelNotFound
                }
                let configuration = MLModelConfiguration()
                configuration.computeUnits = .all
                model = try MLModel(contentsOf: url, configuration: configuration)
                tokenizer = try BertTokenizer()
    }
    
    func embed(_ text: String) throws -> [Float] {
           let (ids, mask, types) = tokenizer.encode(text)
           let features = try MLDictionaryFeatureProvider(dictionary: [
               Self.inputNames[0]: MLFeatureValue(multiArray: try intArray(ids)),
               Self.inputNames[1]: MLFeatureValue(multiArray: try intArray(mask)),
               Self.inputNames[2]: MLFeatureValue(multiArray: try intArray(types)),
           ])
           let output = try model.prediction(from: features)
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
