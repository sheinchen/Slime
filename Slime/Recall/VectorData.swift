//
//  VectorData.swift
//  Slime
//
//  向量和 Data 的互转。Core Data 存不了 [Float]，只能存 Data。
//
//  这段看着平淡，但读回来那一侧有个坑：Data 的底层缓冲区**不保证按 4 字节对齐**，
//  而 `bindMemory(to: Float.self)` 要求对齐。未对齐时它是未定义行为 ——
//  在模拟器上可能一直正常，到真机上某次就给你一堆垃圾数字，
//  然后你会以为是模型坏了。所以这里老老实实走 copyBytes。
//

import Foundation

nonisolated extension Array where Element == Float {

    /// 存进 Core Data 用。512 个 Float32 = 2048 字节。
    var vectorData: Data {
        withUnsafeBufferPointer { Data(buffer: $0) }
    }
}

nonisolated extension Data {

    /// 从 Core Data 读回来。字节数不是 4 的整数倍就返回 nil ——
    /// 那说明存进去的根本不是向量，宁可当没有，也别解出一串垃圾参与排序。
    var vectorFloats: [Float]? {
        let stride = MemoryLayout<Float>.size
        guard count > 0, count % stride == 0 else { return nil }

        var result = [Float](repeating: 0, count: count / stride)
        _ = result.withUnsafeMutableBytes { buffer in
            copyBytes(to: buffer)
        }
        return result
    }
}
