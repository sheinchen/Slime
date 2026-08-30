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
}
