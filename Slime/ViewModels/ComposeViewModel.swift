//
//  ComposeViewModel.swift
//  Slime
//
//  Created by shiying on 2026/7/6.
//

import Foundation

final class ComposeViewModel {
    
    //依赖协议，可以测试
    private let repository: PostRepository
    
    init(repository: PostRepository = CoreDataPostRepository()) {
        self.repository = repository
    }
    
    @discardableResult
    func save(content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        repository.create(content: trimmed)
        return true
    }
}

