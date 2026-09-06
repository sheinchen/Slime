//
//  PendingCare.swift
//  Slime
//
//  Created by shiying on 2026/7/23.
//

import Foundation

nonisolated enum CareStatus: String {
    case shown  // 正在挂着
    case retired    // 已退休：挂满 3 天
}

//给UI的值类型
nonisolated struct PendingCare {
    let id: UUID
    let text: String
    let createdAt: Date
}
