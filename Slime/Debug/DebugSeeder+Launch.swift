//
//  DebugSeeder+Launch.swift
//  Slime
//

#if DEBUG
import Foundation

extension DebugSeeder {

    /// 按启动参数播种。每一幕是干什么的，见 `LaunchOptions.Seed`。
    ///
    /// 只在测试库上生效 —— 每个播种方法自己会先检查，正式库上直接拒绝。
    /// （以前这串 if / else if 写在 SceneDelegate 里，09-25 挪过来。）
    static func run(_ seed: LaunchOptions.Seed) {
        switch seed {
        case .life:     seedLife()
        case .flat:     seedFlat()
        case .thin:     seedThin()
        case .diaries:  seedDiaries()
        case .legacy:   reset(to: [.sad, .sad, .tired, .sad, .sad], withEggs: true)
        case .showcase: seedShowcase()
        case .careTurn: hatchNow(daysAgo: 1, emotion: .happy,
                                 text: "过了！晚上和朋友吃了顿好的")
        case .careFlat: hatchNow(daysAgo: 2, emotion: .calm,
                                 text: "普通的一天，把手边的事做完了")
        case .careLate:
            // 日期早于关怀那天、但孵出时刻是现在 —— `PastCare.isNewEvidence` 该判 false。
            // 「跨天看日期」那条判据就是为这种迟补的旧蛋写的：
            // 孵出时刻很新，内容却很旧，按时刻比会被误标成新证据。
            hatchNow(daysAgo: 5, emotion: .sad,
                     text: "那天其实也不太好过，只是当时没写")
        case .careAge:  ageActiveCare()
        }
    }
}
#endif
