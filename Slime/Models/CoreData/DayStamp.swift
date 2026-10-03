//
//  DayStamp.swift
//  Slime
//

import Foundation

/// 「哪一天」在库里怎么存（`Post.dayKey`、`DayEgg.date` 这两列）。
///
/// **存的是那个日历日期在 UTC 的零点**：10 月 2 日写的，不管人在哪个时区，库里都是 `2026-10-02 00:00 UTC`。
/// 读出来再换成**当前时区**那一天的零点 —— 所以 App 上层拿到的仍然是「本地零点」，跟以前一样，
/// 页面、Service、关怀闸门一行都不用改。换算只发生在仓库里（外加 DEBUG 的播种）。
///
/// **为什么要改**（10-02）：以前存的是「写的时候所在时区的零点」这个绝对时刻
/// （在 UTC+10 写 10 月 2 日 → 存 10-01 14:00 UTC）。换了时区，上层按「新时区的零点」去精确比对，
/// 永远对不上。模拟器上复现过：从 UTC+10 换到 UTC+8 重开 ——
///   · 日历页整片空白（库里 32 篇一篇不少，只是一天都对不上）
///   · 今天的日记被当成「过去欠蛋的一天」（UTC+10 的今天零点比 UTC+8 的早两小时），
///     打开 App 的补蛋把今天的蛋自动孵了 —— 今天的蛋本该只由用户按母鸡孵
///
/// 存成 UTC 零点而不是加一个字符串列：两列还是 Date，不用加模型版本、不用在 Xcode 里走迁移。
/// 代价是这两列的值**不是「某个时刻」**，只能经由这里的函数读写 —— 直接拿去跟别的时刻比是错的。
nonisolated enum DayStamp {

    // MARK: - 平时读写

    /// 本地的某一天（那天里的任意时刻都行）→ 存进库的值
    static func stored(_ localDay: Date, in timeZone: TimeZone) -> Date {
        let parts = gregorian(timeZone).dateComponents([.year, .month, .day], from: localDay)
        return utc.date(from: parts) ?? localDay
    }

    /// 库里的值 → 当前时区那一天的零点（跟 `calendar.startOfDay(for:)` 是同一个时刻，上层可以直接拿去比）
    static func local(_ storedValue: Date, in timeZone: TimeZone) -> Date {
        var parts = utc.dateComponents([.year, .month, .day], from: storedValue)
        // 先落到正午、再求那天的零点：有的时区夏令时切换那天没有 00:00，直接要零点会拿到奇怪的结果
        parts.hour = 12
        let calendar = gregorian(timeZone)
        guard let noon = calendar.date(from: parts) else { return storedValue }
        return calendar.startOfDay(for: noon)
    }

    /// 是不是已经是新存法（UTC 零点）
    static func isStoredFormat(_ value: Date) -> Bool {
        utc.startOfDay(for: value) == value
    }

    // MARK: - 迁移老数据用

    /// 旧存法（写的时候所在时区的零点）→ 新存法。**对同一个值调多少遍结果都一样**，所以迁移重跑不会把数据改坏。
    ///
    /// - Parameter timeZone: 升级时手机所在的时区。老数据绝大多数就是在这个时区写的。
    static func fromLegacy(_ old: Date, currentTimeZone timeZone: TimeZone) -> Date {
        // ① 已经是 UTC 零点：要么已经是新存法，要么是在 UTC+0 写的旧值 —— 两者本来就是同一个值，原样留着。
        //    （旧值只有在偏移为 0 的时区才会正好落在 UTC 零点上，所以不会把别的时区的旧值误认成新值）
        if isStoredFormat(old) { return old }

        // ② 正好是当前时区的零点：就是在这个时区写的（绝大多数情况），按这个时区读出日期
        if gregorian(timeZone).startOfDay(for: old) == old {
            return stored(old, in: timeZone)
        }

        // ③ 在别的时区写的（以前出过远门）：旧值 = 那天的 UTC 零点 − 写入时区的偏移，
        //    取离它最近的那个 UTC 零点（往后挪半天再取当天零点）。
        //    偏移在 ±12 小时以内都能还原对；+13 / +14 的时区（汤加、基里巴斯）会早一天 —— 只影响
        //    「在那里写过、又在别处升级」的那几篇，接受
        return utc.startOfDay(for: old.addingTimeInterval(12 * 3600))
    }

    // MARK: - 私有

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    /// 一律用公历换算：用户手机设成佛历、和历时，`Calendar.current` 的「年」不是公历年，
    /// 拿它的年月日去 UTC 公历里组日期会差出几百年。零点是哪个时刻跟历法无关，所以上层照样用 `.current`
    private static func gregorian(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}
