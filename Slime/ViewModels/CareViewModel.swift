//
//  CareViewModel.swift
//  Slime
//
//  Created by shiying on 2026/7/31.
//

import Foundation

@MainActor
final class CareViewModel {
    
    private let messages: CareMessageStore
    
    init(messages: CareMessageStore? = nil) {
        self.messages = messages ?? CoreDataCareMessageStore()
    }
    
    func activeCare() -> PendingCare? {
            messages.active()
        }
}
