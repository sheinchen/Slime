//
//  AIConfig.swift
//  Slime
//
//  Created by shiying on 2026/7/15.
//

import Foundation

enum AIConfig {
    static let baseURL = "https://api.deepseek.com"
    
    static let model = "deepseek-chat"
    
    static var apiKey: String {
        guard
            let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
            let dict = NSDictionary(contentsOf: url),
            let key = dict["DeepSeekAPIKey"] as? String else {
            return ""
        }
        return key
    }
}
