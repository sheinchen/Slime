//
//  LaunchOptions.swift
//  Slime
//

#if DEBUG
import Foundation

/// Debug 构建的启动参数。**全项目只在这里读 `CommandLine.arguments`**（09-25 收拢）。
///
/// 以前散在三处：SceneDelegate（打桩、播种）、`StubAIService.init`（-StubQuiet / -StubSlow / -StubOffline）、
/// `CoreDataStack`（-UseTestStore）。查一个开关是干什么的要翻三个文件，新加一个也不知道该写在哪。
/// 现在：解析在这里、每个开关的说明在这里、单测在 `LaunchOptionsTests`。
///
/// 在 Xcode 里配：Edit Scheme → Run → Arguments → Arguments Passed On Launch。
/// 整个类型只在 Debug 构建里存在 —— Release 里没有任何开关可开。
nonisolated struct LaunchOptions: Equatable {

    // MARK: - 存储

    /// `-UseTestStore`：用测试库 Slime-Test.sqlite（跟正式库分开，跨启动保留）。
    /// **播种只在测试库上生效** —— 不开这个，DebugSeeder 会拒绝写入，一个字节都不碰真数据。
    let useTestStore: Bool

    // MARK: - 示范教程

    /// `-ResetTutorial`：每次启动都当成「没看过示范」，同意之后先进示范。
    /// 产品上示范只出现一次、不能重看，这个开关只给开发时反复验它用。
    /// 示范用的是内存里的假数据，开着它不会碰到测试库或正式库
    let resetTutorial: Bool

    // MARK: - AI 打桩

    /// 哪几路 AI 换成 `StubAIService`，以及桩怎么演。
    ///
    /// 每一路**各自**能换，靠的是 AI 能力一开始就拆成了窄协议 ——
    /// 于是「测关怀」和「测检索」可以互不干扰。
    struct Stubs: Equatable {
        /// `-StubCare`：关怀决策固定（配 `-StubQuiet` 翻成固定不说）
        var care = false
        /// `-StubEgg`：孵蛋总结固定，省掉等待和 API 调用
        var egg = false
        /// `-StubChat`：聊天回复固定（写日记的 analyze 也走这一路）
        var chat = false
        /// 检索那两路（提炼检索词 + 重排）。**只有 `-StubAI` 会打开它** ——
        /// 桩只会朴素切词，一打桩检索质量就掉下来，所以没有单独的开关
        var recall = false

        /// `-StubQuiet`：关怀的桩每次都判「不说」（默认每次都说）—— 验 AI 的一票否决权有没有落地
        var quiet = false
        /// `-StubOffline`：打了桩的那几路全部假装没网。验「没网也能写」用 `-StubChat -StubOffline`；
        /// 配 `-StubAI` 就是整个 App 断网
        var offline = false
        /// `-StubSlow`：打了桩的那几路每次都拖 10 秒（弱网），看等待中的样子：「孵着呢…」「咕，在听呢」
        var slow = false
    }
    /// `-StubAI` = 上面四路全部打桩 —— 只用来验管道，验不了检索质量。
    let stubs: Stubs

    // MARK: - 播种

    /// 启动时往测试库里造什么数据。同时给了好几个的话，按下面的顺序**只认第一个**。
    ///
    /// ⚠️ **不带任何播种参数 = 什么都不播**，直接用上次留下的库。这一档是必需的：
    /// 关怀「下次进首页还在吗」、聊天记录还在吗、蛋有没有落库，都得能重启 App 而**不清库**才验得了。
    enum Seed: Equatable {
        // —— 造数据，**会清库**（连关怀和检查日志一起清，所以启动时会重新评估一次）——
        /// `-SeedLife`：半年生活，近 14 天连着低落 + 往前半年埋了检索用例。**主力语料**
        case life
        /// `-SeedFlat`：14 天全平稳 → 闸门会放行，但 AI 该否决（验一票否决权）
        case flat
        /// `-SeedThin`：只有 2 天 → 闸门②天数不足，**根本不调 AI**
        case thin
        /// `-SeedDiaries`：20 天具体日记，给删除 / 卡片堆 / 周条 / 月历用
        case diaries
        /// `-SeedLegacy`：老的 5 天 sad，留着对照
        case legacy
        /// `-SeedShowcase`：新手示范那套剧本写进测试库，拍 App Store 截图用
        case showcase

        // —— 在上次留下的库上动一点，**不清库、不清关怀**（接着上一幕演）——
        /// `-CareTurn`（旧名 `-CareStep2`）：把昨天重孵成 happy → 有新证据且是转折，看 AI 换不换新话
        case careTurn
        /// `-CareFlat`（旧名 `-CareStep3`）：补一颗平淡的蛋 → 能过闸门但没实质变化，看 AI 保不保持
        case careFlat
        /// `-CareLate`：补一颗 5 天前的蛋 → 日期早于关怀那天，isNew 该是 false
        case careLate
        /// `-CareAge`：把挂着的关怀推老 4 天 → 验「满 3 天必退」这条本地兜底
        case careAge
    }
    let seed: Seed?

    /// 参数 → 哪一幕。**顺序就是优先级**，跟以前 SceneDelegate 里那串 if / else if 一致。
    private static let seedFlags: [(flag: String, seed: Seed)] = [
        ("-SeedLife", .life),
        ("-SeedFlat", .flat),
        ("-SeedThin", .thin),
        ("-SeedDiaries", .diaries),
        ("-SeedLegacy", .legacy),
        ("-SeedShowcase", .showcase),
        ("-CareTurn", .careTurn), ("-CareStep2", .careTurn),
        ("-CareFlat", .careFlat), ("-CareStep3", .careFlat),
        ("-CareLate", .careLate),
        ("-CareAge", .careAge),
    ]

    init(arguments: [String]) {
        let has = Set(arguments).contains
        useTestStore = has("-UseTestStore")
        resetTutorial = has("-ResetTutorial")

        let all = has("-StubAI")
        stubs = Stubs(care: all || has("-StubCare"),
                      egg: all || has("-StubEgg"),
                      chat: all || has("-StubChat"),
                      recall: all,
                      quiet: has("-StubQuiet"),
                      offline: has("-StubOffline"),
                      slow: has("-StubSlow"))

        seed = Self.seedFlags.first { has($0.flag) }?.seed
    }

    /// 这次启动的参数。第一次用到时解析一次。
    static let current = LaunchOptions(arguments: CommandLine.arguments)
}
#endif
