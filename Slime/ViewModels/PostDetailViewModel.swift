//
//  PostDetailViewModel.swift
//  Slime
//
//  Created by shiying on 2026/7/6.
//

import Foundation

final class PostDetailViewModel {
    
    private let item: SlimeItem
    private let repository: PostRepository
    
    init(item: SlimeItem, repository: PostRepository = CoreDataPostRepository()) {
        self.item = item
        self.repository = repository
    }
    
    var contentText: String {
        item.content
    }
    
    var dateText: String {
        Self.formatter.string(from: item.createdAt)
    }
    
    func delete() {
        repository.delete(id: item.id)
    }
    
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
    
}
