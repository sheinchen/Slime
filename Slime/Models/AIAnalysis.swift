//
//  AIAnalysis.swift
//  Slime
//
//  Created by shiying on 2026/7/15.
//

import Foundation

struct AIAnalysis {
    /// nil = 模型回了，但情绪词不在六类里。回复照样能用，只是这篇先不带情绪（跟没网时同一个处境）
    let emotion: SlimeEmotion?
    let reply: String
}
