//
//  HenPress.swift
//  Slime
//
//  Created by shiying on 2026/8/31.
//

import Foundation
import CoreGraphics

struct HenPress {
    
    struct Config {
        /// 按住多久算蓄满。
        var chargeDuration: TimeInterval = 1.15
        /// 松手后回落到 0 要多久。比蓄力快得多 —— 放弃要干脆，不然像卡住。
        var releaseDuration: TimeInterval = 0.30

        /// 蓄满时压扁多少（占身高比例）。
        var squashAmount: CGFloat = 0.19
        /// 压扁的同时往两边撑开多少。
        /// 只压不撑会像被削掉一截；撑开才是「体积没变，只是被挤了」。
        var stretchAmount: CGFloat = 0.12

        /// 蓄满时的抖动幅度（pt）。
        var shakeAmount: CGFloat = 2.8
        /// 抖动快慢（弧度/秒）。
        var shakeSpeed: TimeInterval = 34

        /// 蓄到这里就把 AI 总结提前发出去，见 `Signal.prefetch`。
        var prefetchAt: CGFloat = 0.45
    }
    
    enum Signal {
        case prefetch
        case lay
    }
    
    struct Output {
        /// 乘到母鸡横向缩放上（>1，被挤宽了）。
        var scaleX: CGFloat
        /// 乘到纵向缩放上（<1，被压扁了）。
        var scaleY: CGFloat
        /// 横向抖动，pt。
        var shake: CGFloat
        var progress: CGFloat
        var signal: Signal?
    }
    
    var config = Config()
    
    private(set) var progress: CGFloat = 0
    private(set) var isPressing = false
    
    private var didLay = false
    private var didPrefetch = false
    
    private var shakeClock: TimeInterval = 0
    
    //MARK: -
    
    mutating func begin() {
        guard !didLay else { return }
        isPressing = true
    }
    
    mutating func end() {
        isPressing = false
        didLay = false
        didPrefetch = false
    }
    
    mutating func reset() {
        isPressing = false
        didLay = false
        didPrefetch = false
        progress = 0
    }
    
    mutating func update(dt: TimeInterval) -> Output {
        shakeClock += dt
        
        if isPressing {
            progress = min(progress + CGFloat(dt / config.chargeDuration), 1)
        } else {
            progress = max(progress - CGFloat(dt / config.releaseDuration), 0)
        }
        
        var signal: Signal?
        if isPressing, !didPrefetch, progress >= config.prefetchAt {
            didPrefetch = true
            signal = .prefetch
        }
        if isPressing, progress >= 1 {
            didLay = true
            isPressing = false
            signal = .lay
        }
        let shake = CGFloat(sin(shakeClock * config.shakeSpeed)) * config.shakeAmount * progress * progress
        
        return Output(scaleX: 1 + config.stretchAmount * progress, scaleY: 1 - config.squashAmount * progress, shake: shake, progress: progress, signal: signal)
    }
}
