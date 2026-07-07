//
//  PostDetailViewModel.swift
//  Slime
//
//  Created by shiying on 2026/7/6.
//

import Foundation

final class PostDetailViewModel {
    
    private let item: SlimeItem
    
    init(item: SlimeItem) {
        self.item = item
    }
    
    var contentText: String {
        item.content
    }
    
    var dateText: String {
        Self.formatter.string(from: item.createdAt)
    }
    
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
    
}
