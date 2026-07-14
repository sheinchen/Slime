//
//  SquareViewModel.swift
//  Slime
//
//  Created by shiying on 2026/7/6.
//

import Foundation

final class SquareViewModel {
    
    private let repository: PostRepository
    
    private(set) var items: [SlimeItem] = []
    
    init(repository: PostRepository = CoreDataPostRepository()) {
        self.repository = repository
    }
    
    func loadPosts() {
        items = repository.fetchAll().map({ post in
            SlimeItem(id: post.id, content: post.content, createdAt: post.createdAt, emotion: SlimeEmotion(rawValue: post.emotion) ?? .calm)
        })
    }
    
    func delete(_ item: SlimeItem) {
        repository.delete(id: item.id)
        items.removeAll { $0.id == item.id }
    }
}
