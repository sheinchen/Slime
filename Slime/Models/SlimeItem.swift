//
//  SlimeItem.swift
//  Slime
//
//  Created by shiying on 2026/7/6.
//

import Foundation

nonisolated struct SlimeItem: Hashable {
    let id: UUID
    let content: String
    let createdAt: Date
    let emotion: SlimeEmotion
}
