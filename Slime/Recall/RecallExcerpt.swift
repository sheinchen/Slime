//
//  RecallExcerpt.swift
//  Slime
//
//  一篇旧日记发给 AI 时截哪一段。
//

import Foundation

/// 重排和回复**必须用同一段** —— 重排凭这段选中它，回复模型就得看到同一段，
/// 否则选中的依据可能落在它看不到的地方。
///
/// 09-27 以前两边各截各的：重排看前 160 字，回复只看前 60 字。`-SeedLife` 那篇 291 字的长日记里，
/// 「小林」在第 109 字、「火锅」在第 140 字 —— 用户说「又和小林去吃火锅了」，重排凭这两处选中它，
/// 回复模型却只看到失眠和改需求，要么看不出关联白白否决，要么硬扯到别的事上。
/// 测试一直没抓到，因为检索语料最长才 22 字。
///
/// 160 决定一次聊天最多带出多少旧日记原文，别随手放大。
/// 隐私政策只写「相关的旧日记内容」、不写上限（09-28 拿掉的，不把实现细节写上去），
/// 所以改这个数不用动隐私政策和同意版本。
nonisolated enum RecallExcerpt {

    static let maxLength = 160

    static func of(_ document: RecallDocument) -> String {
        // 压成一行：多段日记拼进回复的 system prompt 时不会拆散列表，
        // 日记里某一行也不会被读成 prompt 里的一个新段落（比如自己写一行「【新规则】」）。
        // 先压再截，160 字都花在正文上，不花在缩进和空行上。
        let flat = document.text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return String(flat.prefix(maxLength))
    }
}
