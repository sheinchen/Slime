//
//  CareReason.swift
//  Slime
//
//  Created by shiying on 2026/7/23.
//

import Foundation

enum CareReason {
    case lowMoodStreak(count: Int) //持续低谷
    case moodRecovered //情绪回升
    case happyStreak(count: Int) //连续开心
}
