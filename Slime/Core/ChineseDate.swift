import Foundation

/// 「八月十六」。系统的中文日期格式给的是「8月16日」，
/// 跟这一页的手写调性对不上，所以自己拼汉字。
enum ChineseDate {
    private static let digits = ["", "一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]

    /// 1...31 → 一 / 十 / 十六 / 二十 / 二十七 / 三十一
    static func numeral(_ n: Int) -> String {
        switch n {
        case 1...10: return digits[n]
        case 11...19: return "十" + digits[n - 10]
        case 20: return "二十"
        case 21...29: return "二十" + digits[n - 20]
        case 30: return "三十"
        case 31: return "三十一"
        default: return String(n)
        }
    }

    static func title(for date: Date = Date(), calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.month, .day], from: date)
        guard let month = parts.month, let day = parts.day else { return "" }
        return numeral(month) + "月" + numeral(day)
    }

    /// 「前几天」「两个多月前」这种**模糊**的时间距离。
    ///
    /// 专门给 AI 看的。检索到旧日记之后要告诉母鸡这事有多久了，
    /// 但 prompt 里明令它不许说出具体日期（说日期像在查档案，不像朋友）。
    /// 与其给了精确日期再叮嘱它别说，不如**根本不给** —— 说不出口才是真说不出口。
    static func vague(_ date: Date, from now: Date = Date(), calendar: Calendar = .current) -> String {
        let from = calendar.startOfDay(for: date)
        let to = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: from, to: to).day ?? 0

        switch days {
        case ..<0:    return "最近"      // 未来时间，不该出现，兜底
        case 0:       return "今天"
        case 1:       return "昨天"
        case 2...6:   return "前几天"
        case 7...13:  return "上周"
        case 14...29: return "半个多月前"
        case 30...59: return "一个多月前"
        case 60...89: return "两个多月前"
        case 90...179: return "几个月前"
        case 180...364: return "半年多前"
        default:      return "很久以前"
        }
    }
}
