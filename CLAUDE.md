# CLAUDE.md — 母鸡日记 项目常驻背景

> Claude Code 每次启动会自动读这个文件。它是本项目的"常驻记忆":锁死的决策、带我的方式、当前进度都在这里。请全程遵守。
>
> **我的工作分两条线**:这里是**执行线**(推进项目、写代码);我另有一个**教学对话**专门弄懂 iOS 概念。执行线负责往前做,遇到我不懂的概念,给够上手的解释即可,深挖我会拿到教学对话去问。

---

## 1. 项目一句话

一个有主动关怀能力的 AI 情绪日记 App:用户随手记录碎碎念,**一天的记录收束成一颗情绪蛋**(样貌由当天总结情绪驱动);一只 AI 母鸡在合适时机主动关心用户。记录是主干,主动关怀是差异化亮点。iOS 是呈现层。

> 📌 **产品形态已从「一篇日记一只史莱姆」改成「一天一颗蛋」**。首页是草地小岛 + 母鸡 + 鸟巢,点鸟巢写日记、按住母鸡孵今天的蛋;左滑是周条 + 当天日记列表。
> 代码里仍沿用 `Slime*` 命名(`SlimeEmotion` / `SlimeItem` / `SlimeView`),`SlimeView` 现在是 `EggView` 里那团情绪。`SlimeCell` 已废弃(广场改用 `DiaryEntryCell`)。**看到 Slime 不要以为是旧代码。**

---

## 2. 技术决策(已锁死,不要改变或建议替换方案)

- **UI**:全 UIKit(不用 SwiftUI)
- **列表/集合**:现代 UICollectionView —— Compositional Layout + Diffable Data Source(不要用老的 UITableView + cellForRowAt 写法)
- **布局**:SnapKit(不要手写大量 NSLayoutConstraint)
- **存储**:Core Data
- **架构**:MVVM + Repository。View 只负责显示,业务逻辑在 ViewModel,数据读写全部走 Repository;跨仓库+网络的业务流程放 `Services/`
- **并发**:工程开了 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` —— **一切默认主线程隔离**,纯值类型/纯函数要显式标 `nonisolated`。注意默认参数表达式是**非隔离**的,不能在那里 new 隔离类型(要用 `= nil` + init 体内构造)
- **形态**:本地为主(纯单机,无登录、无账号);唯一网络依赖是 AI 调用(经轻后端中转藏 key,尚未做)
- **情绪与 AI 输出(已锁死)**:情绪枚举 6 类 —— happy / calm / sad / angry / anxious / tired。`SlimeEmotion`、prompt 枚举约束、颜色映射均以此为准,不再增减。
  AI 目前三个用途,各自独立调用:①单篇日记 `analyze` → `AIAnalysis(emotion, reply)`;②一天收束 `summarizeDay` → `DayEggSummary(text, emotion)`;③多轮聊天 `chat` / `chatstream`(SSE)。
  ~~摘要/心愿/心愿时间点/话题分类那套六字段结构~~ **已放弃,不要按它实现**。情绪强度(`intensity` 1-3)是主动关照 payload 需要的,**待补到 `DayEgg` 上**。
- **UI 启动**:纯代码搭 UI,无 Storyboard。`SceneDelegate` 是组合根

---

## 2.1 主动关照系统 v2(已定稿,实现时按此,不要另提方案)

> **完整规格见 [`docs/主动关照-v2.md`](docs/主动关照-v2.md) —— 那份是唯一权威,有冲突以它为准。** 这里只列不能违反的红线。
>
> ⚠️ **v1(切片 7 的三条本地规则)已废弃**。原因:规则在用数数的方式下情绪断言(「连续三篇 sad = 低谷」),而且趋势是「天与天」之间的事、不是「篇与篇」之间的事。

- **决策权分层**:本地闸门(算术)→ AI 决策(语义)→ 本地边界(记账)。
  **权限不对称:AI 有一票否决权,没有一票通过权** —— AI 可以说「这次不值得说」,但本地闸门不放行,它根本没机会开口。
- **本地层红线**:闸门代码里**不允许出现任何 `emotion` 字样**。它只回答三件算术:有新蛋吗 / 窗口内够 3 天吗 / 距上条关怀退休满 3 天吗。**一旦本地开始判断「低谷」「回升」,就是跑回 v1 了。**
- **关怀只看蛋,不看日记**。单篇日记的 emotion 服务于写完那一刻的 reply;蛋的总结情绪才是趋势载体。
- **生成 ≠ 展示,而且合并在打开时做**:写日记**不触发**任何关怀逻辑(`postSaved` 事件已废弃);唯一事件是 `appOpened`(**进前台 + 跨自然天**)。打开时才调 AI 生成文案 —— 这样文案永远基于最新窗口,情绪反转不会弹出过时关怀。
- **顺序依赖**:打开 App 必须**先补完欠的蛋,再跑关怀闸门**。反了就缺最新一天,而那正是情绪反转的藏身处。已落在 `SceneDelegate.onAppActive()`。
- **关怀退场只有两条规则,谁先到算谁**(代码里就是两个时刻取 `min`):
  ① **关怀之后诞生了新蛋** —— 判据 `蛋.date >= 关怀那天 且 蛋.createdAt > 关怀生成时刻`。**补蛋也算**(用户当天没按母鸡、第二天补出来的,同样是翻篇);两个条件缺一不可,只看 date 会被关怀生成前就存在的当天蛋退掉。
  ② **生成满 3 天** —— 内容保质期,用户停写日记时的兜底。
  实际效果:天天写日记的话关怀通常只活 1 天,3 天那条基本是兜底。
- **两个 3 天**:关怀最长挂 3 天(内容保质期,同时充当露面次数上限)、退休后冷却 3 天。这个数不能放大。
- **日志即状态**:不要为冷却/上次检查再建独立状态表,全部从 `CareCheck` / `CareMessage` 派生。
- **文案铁律**:安全底线最高 > **绝不暴露判断依据**(不出现"连续""检测到""记录显示") > 探询不断言 > 不说教不给建议。另加**不说清单**:宁可不说,也不要说一句正确但没用的话。
- **不要主动加**:自适应频控、心愿提醒、把 `get_mood_history` 做成 tool call、关怀卡片的聊天入口(卡片纯只读是明确的产品选择)。

---

## 3. 怎么带我(重要 —— 请严格按这个来)

**我的真实画像:**
- **Swift 语言本身我熟**:变量、函数、类、闭包、可选值这些语法不用解释。
- **但 iOS 框架层和工程工具我不熟**:UIViewController 生命周期、Core Data、Auto Layout、Git、Xcode 工程结构这些概念我**不懂**,需要你讲清楚。**不要假设我懂任何 iOS 框架或工程概念。**

**带我的方式:**
- **整块给代码,但配足够解释**。一次给一个完整文件,不要一行行带我敲、不要把简单的东西拆成小碎步(那样太慢)。但每给一段代码,要用中文说清:这个文件/这段在干嘛、涉及的 iOS 概念是什么、为什么这么写。
- **先读我的代码再给建议**。不要凭印象说「把某处改成什么」—— 我可能已经改过了。给改动要**锚定到实际行号和实际内容**。
- **写代码时每一步讲清"在干嘛"**,尤其出现新的 iOS 框架概念(生命周期、Core Data、代理、闭包回调等)时,简短点明它是什么、起什么作用。
- **深入原理放到另一条线**:我另开了一个"教学对话"专门弄懂概念。所以在这条执行线里,你点到概念、给够上手需要的解释即可,**不用长篇展开原理**;我想深挖时会拿到教学对话去问。执行线保持往前推。
- **卡住时**:如果我说"这个概念我不懂",你简短解释一下够我继续就行,或提示我"这个建议到教学对话深聊",别在执行线停太久。

## 3.1 谁来写代码(重要)

- **核心代码 —— 只给我看 + 讲解,不要写入文件,我自己敲**:
  - Core Data(栈、数据模型、增删改查的核心逻辑)
  - 分层结构(Repository / Service / ViewModel 的设计与职责划分)
  - 并发(async/await、@MainActor、actor)
  - 关怀引擎(闸门 / AI 决策 / 边界)
  - 这几块是我要吃透、面试要讲的,必须亲手敲。你给代码 + 讲清原理,我自己写进文件。
- **其余代码 —— 可以直接生成写入文件**:
  - 常规 UI(ViewController 布局、cell、自定义 view)、样板(CRUD 模板、重复配置)、工程杂项、文档
  - 直接写入,但要用中文说清这段在干嘛、涉及什么 iOS 概念。
- 不确定某段算核心还是其余时,**先问我**再决定写不写入。

## 3.2 我的学习责任(我对自己的约定,请帮我盯着)

- 每段生成的代码我都要**读懂**,不能"能跑就划过去"。
- 每条切片做完,我要能回答:"这段代码在干嘛、为什么这么写?" 能讲清才算过。
- 讲不清的概念,我会拿到**教学对话(普通聊天)**去弄懂。
- 如果你发现我在没读懂的情况下想直接往下走,**提醒我一句**。

---

## 4. 开发方式:垂直切片

- 一次只做**一条从界面到数据的完整线**,端到端跑通,再做下一条。不要一次性把整个 App 建出来。
- 每条切片开始前:先用中文讲清这条切片涉及哪些文件、每个文件负责什么、为什么这么分层;再动手。
- 每条切片做通后:带我 `git commit`(给出 commit message 建议),并更新本文件第 6 节"当前进度"。

---

## 5. 常用约定

- 语言:全程用中文讲解。
- 代码风格:清晰优先,命名见名知意。
- 依赖:SnapKit(SPM)、Rive(母鸡动画)。
- 工程用 **PBXFileSystemSynchronizedRootGroup** —— 新建文件放进目录即自动进 target,不用手动加。
- 目录分层:
  `Models/`(Core Data 实体 + 领域模型)、`Repositories/`(仓库读写)、`Services/`(AI 网络层 + 跨仓库业务流程,如 `AIService` / `DayEggService`)、`Care/`(关怀引擎)、`ViewModels/`、`ViewControllers/`、`Views/`、`Core/`(配色/字体/中文日期/缓动等工具)。
- 单测在 `SlimeTests/`(XCTest,`@testable import Slime`)。只测纯函数,不碰 Core Data。
- 编译验证:`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Slime.xcodeproj -scheme Slime -destination 'generic/platform=iOS Simulator' build`
  (系统 `xcode-select` 指向 Command Line Tools,直接 `xcodebuild` 会失败)
- 跑测试:把 `build` 换成 `test`,且 destination **必须指定具体机型**(`generic/...` 跑不了测试):
  `... -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`
  查可用机型:`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl list devices available`

---

## 6. 当前进度(每条切片做完更新这里)

> 这一节是我的跨对话存档点。开新对话时看这里就知道做到哪了。
> 已完成的切片只留一句话 —— 细节在 git 历史里,不必占常驻上下文。

### 已完成

| # | 切片 | 一句话 |
|---|---|---|
| 1 | 最小闭环 | 输入 → ComposeVM → PostRepository → Core Data → 广场(Compositional Layout + Diffable) |
| 2 | 点击详情 | `itemIdentifier(for:)` 取 item → 注入 DetailVM → push |
| 3 | 删除 | `PostRepository.delete(id:)`;长按菜单 + 详情页垃圾桶两个入口 |
| 4 | SlimeView + 动效 | `UIBezierPath` 果冻 blob、`CASpringAnimation` 呼吸、点击 squash&stretch |
| 5 | 孵化揭晓 | Post 加 `emotion`;`hatch()` 未定形→凝结→揭晓 |
| 6 | 接入 AI 情绪分析 | `AIService` 协议 + `DeepSeekAIService`(json_object);Post 加 `reply`;**失败不伪造不存帖,上抛让 VC 弹提示** |
| 7 | 主动关心 v1 | 五段管道跑通(Event→Rule→引擎→AI 话术→气泡演出)。**已被 v2 取代,代码已于切片 11 删净** |
| 8 | AI 聊天 | `ChatSession`/`ChatMessage`;SSE 流式(`URLSession.bytes` + `AsyncThrowingStream`) |
| 9 | 母鸡日记(产品大改) | 一天一颗蛋:`DayEgg` 实体 + `DayEggStore` + `summarizeDay`;首页草地小岛 + Rive 母鸡 + 鸟巢;`RootPagerViewController` 左右分页;周条 + 日记列表 |
| 10 | 补蛋抽成服务 | `DayEggService`(`hatchAllPending` / `prefetchToday` / `finishToday`)+ `EggDebt` 判定规则;`SquareViewModel` 瘦身 60 行;组合根建唯一实例,补蛋从「进广场页」改到 `sceneDidBecomeActive` |
| 11 | 主动关照 v2·本地层 | 数据层迁移(`CareMessage` 两态 + `retiredAt`/`referencedDates`、新增 `CareCheck`、删 `RuleCooldown`);`CareGateRule` 纯函数闸门 + `CareGate` 取数;`CareEngine` 编排退场→闸门→记日志;**新建 SlimeTests target,10 条单测**;v1 代码删净 |

### 正在做:主动关照 v2

按 [`docs/主动关照-v2.md`](docs/主动关照-v2.md) 第 0 节的十步走。第 1–6 步已完成,当前在**第 7 步**:

- ✅ 1–3 `DayEggService` 抽出、`SquareViewModel` 瘦身、补蛋挪到 App 激活
- ✅ 4 `DayEggStore.delete(for:)` + 孤儿蛋清理
- ✅ 5 数据层迁移:`CareMessage` 两态 + `retiredAt` + `referencedDates`;新增 `CareCheck`;删 `RuleCooldown`
- ✅ 6 删三条老规则与 `postSaved`,写 `CareGate` + 单测(10 条全绿)
- 🚧 **7 AI 决策层**:`MoodWindow` → prompt → 结构化返回(`shouldShow` / `text` / `referencedDates` / `pattern` / `confidence`)
- ⬜ 8 产品边界 + 卡片生命周期(卡片挂首页,`CareViewModel` 目前无使用者)
- ⬜ 9 可观测(`CareCheck` 后半段字段写全 + debug 页)
- ⬜ 10 eval(20 场景 golden set)

**本地层已完整,接线在 `CareEngine.handle` 的 `case .pass` 分支**(现在只写了 `dropReason = "AI 决策层未接入"`)。

#### 实现时踩过的两个坑(别再踩)

- **退休必须同时写 `status` 和 `retiredAt`**。v1 只改 `status`,`retiredAt` 永远是 nil → 冷却锚点查不到 → 关怀天天弹。现在两行绑死在 `CoreDataCareMessageStore` 的私有 `retire(_:at:)` 里,全类只有这一个出口。
- **退休时刻记「实际死的那一刻」,不是 `now`**。隔一周才打开 App,三天前就该走的关怀若记成"今天退休",冷却又白等 3 天。

### 已知待清理

- `SlimeCell.swift` 无人引用,可删
- `SceneDelegate` 第 30 行 `DayEggService(posts:)` 漏传 `eggs: eggStore`,会自己 new 一个仓库实例(今天不出错,两者共享同一 `viewContext`,但组合根应当只有一份)
- `DayEggStore` 里 `private let calendar` 已无人使用(判据搬进 SQL 谓词后就不需要了),连同 init 参数一起删
- `ChatMessageItem` 缺 `nonisolated`(同 `SlimeItem` 的修法)
- `PendingCare.swift` 注释「或用户主动关掉」已失效 —— 退场只有两条规则

### 关键待确认项

- 轻后端中转藏 key(现为客户端直连 DeepSeek + `Secrets.plist`,**上线前必换**)
- 真机 / 开发者账号、隐私处理

---

## 7. 范围红线(本期不做,别主动加)

- 登录 / 账号体系
- 他人回复 / 社区功能
- 帖子久无回应时的 AI 回应(依赖"他人回复",与其同期)
- 挑战 / 奖励 / 游戏化
- 多用户、数据同步、内容审核

如果我要求加这些,提醒我一句它在本期范围外,再按我意愿处理。
