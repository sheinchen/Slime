//
//  DayStampTests.swift
//  SlimeTests
//
//  「哪一天」的存法（DayStamp）。纯函数，同步测。
//  背景：10-02 换时区后日历整片空白、今天的蛋被自动孵掉，见 DayStamp.swift 的注释。
//

import XCTest
@testable import Slime

final class DayStampTests: XCTestCase {

    private let brisbane = TimeZone(identifier: "Australia/Brisbane")!      // +10，没有夏令时
    private let shanghai = TimeZone(identifier: "Asia/Shanghai")!           // +8
    private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!   // -7（10 月是夏令时）
    private let kiritimati = TimeZone(identifier: "Pacific/Kiritimati")!    // +14，世界最早
    private let pagoPago = TimeZone(identifier: "Pacific/Pago_Pago")!       // -11
    private let kathmandu = TimeZone(identifier: "Asia/Kathmandu")!         // +5:45，不是整点

    private func calendar(_ tz: TimeZone) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = tz
        return c
    }

    /// 某时区里 y-m-d 那天的某个时刻
    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0, in tz: TimeZone) -> Date {
        calendar(tz).date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func ymd(_ date: Date, in tz: TimeZone) -> [Int] {
        let p = calendar(tz).dateComponents([.year, .month, .day], from: date)
        return [p.year!, p.month!, p.day!]
    }

    // MARK: - 平时读写

    func test_同一个日历日期_在哪个时区写_库里都是同一个值() {
        let zones = [brisbane, shanghai, losAngeles, kiritimati, pagoPago, kathmandu]
        let values = Set(zones.map { DayStamp.stored(at(2026, 10, 2, 9, in: $0), in: $0) })
        XCTAssertEqual(values.count, 1)
        XCTAssertTrue(DayStamp.isStoredFormat(values.first!))
    }

    func test_一天里的任意时刻_都存成同一天() {
        let early = DayStamp.stored(at(2026, 10, 2, 0, 1, in: brisbane), in: brisbane)
        let late = DayStamp.stored(at(2026, 10, 2, 23, 59, in: brisbane), in: brisbane)
        XCTAssertEqual(early, late)
    }

    /// 这就是 10-02 那个 bug 的核心：在 A 时区写的，到 B 时区读，得是 B 时区「那个日期」的零点
    func test_在一个时区写_换个时区读_还是那个日期_而且正好是那边的零点() {
        let zones = [brisbane, shanghai, losAngeles, kiritimati, pagoPago, kathmandu]
        for writer in zones {
            let stored = DayStamp.stored(at(2026, 10, 2, 22, in: writer), in: writer)
            for reader in zones {
                let local = DayStamp.local(stored, in: reader)
                XCTAssertEqual(ymd(local, in: reader), [2026, 10, 2], "\(writer.identifier) 写、\(reader.identifier) 读")
                XCTAssertEqual(local, calendar(reader).startOfDay(for: local),
                               "得是那边的零点，上层才能拿它跟 startOfDay 精确比对")
            }
        }
    }

    /// 智利夏令时那天从 24:00 直接跳到 01:00，没有 00:00。读出来要跟 `startOfDay` 给的一致，不能凭空造一个零点
    func test_没有零点的那天_读出来跟startOfDay一致() {
        let santiago = TimeZone(identifier: "America/Santiago")!
        let cal = calendar(santiago)
        let noon = cal.date(from: DateComponents(year: 2026, month: 9, day: 6, hour: 12))!
        let stored = DayStamp.stored(noon, in: santiago)
        XCTAssertEqual(DayStamp.local(stored, in: santiago), cal.startOfDay(for: noon))
    }

    // MARK: - 迁移老数据

    /// 旧存法 = 写的时候那个时区的零点
    private func legacy(_ y: Int, _ m: Int, _ d: Int, writtenIn tz: TimeZone) -> Date {
        at(y, m, d, in: tz)
    }

    func test_迁移_在当前时区写的老数据_还原成同一天() {
        let old = legacy(2026, 10, 2, writtenIn: brisbane)
        let migrated = DayStamp.fromLegacy(old, currentTimeZone: brisbane)
        XCTAssertEqual(migrated, DayStamp.stored(old, in: brisbane))
        XCTAssertEqual(ymd(DayStamp.local(migrated, in: brisbane), in: brisbane), [2026, 10, 2])
    }

    func test_迁移_以前出门在别的时区写的_也还原对() {
        // 在 +8 写的，升级时人在 +10；在 -7 写的，升级时人在 +10；反过来也试
        let cases: [(written: TimeZone, upgradeIn: TimeZone)] = [
            (shanghai, brisbane), (losAngeles, brisbane), (brisbane, losAngeles), (kathmandu, pagoPago),
        ]
        for c in cases {
            let migrated = DayStamp.fromLegacy(legacy(2026, 10, 2, writtenIn: c.written), currentTimeZone: c.upgradeIn)
            XCTAssertEqual(ymd(DayStamp.local(migrated, in: c.upgradeIn), in: c.upgradeIn), [2026, 10, 2],
                           "\(c.written.identifier) 写、在 \(c.upgradeIn.identifier) 升级")
        }
    }

    func test_迁移_UTC零时区写的老值本来就等于新值() {
        let old = legacy(2026, 10, 2, writtenIn: .gmt)
        XCTAssertEqual(DayStamp.fromLegacy(old, currentTimeZone: brisbane), old)
    }

    /// 迁移重跑（比如标记没落盘）不能把已经换好的值再换一遍
    func test_迁移跑几遍结果都一样() {
        for writer in [brisbane, shanghai, losAngeles, kathmandu] {
            let once = DayStamp.fromLegacy(legacy(2026, 10, 2, writtenIn: writer), currentTimeZone: brisbane)
            XCTAssertEqual(DayStamp.fromLegacy(once, currentTimeZone: brisbane), once)
            XCTAssertEqual(DayStamp.fromLegacy(once, currentTimeZone: losAngeles), once, "换个时区重跑也不能动")
        }
    }
}
