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
- **关怀退场交给 AI,本地只兜底**(2026-09-09 改;规格里那条「新蛋诞生就退场」已废弃):
  · **被替换** —— 关怀挂着时,AI 每次都能看到它(`PastCare` 带 `stillShowing` / `saidAt` / `about`),
    自己判断「旧的还贴不贴切」。判 `shouldShow: true` 就是「换成新的」,`show()` 会把旧的退掉。
    所以**替换和退场是同一个动作的两半**。
  · **满 3 天必退** —— `retireIfNeeded` 里唯一剩下的本地规则。**不能删**:AI 不可达时(断网、
    API 挂了),关怀不能永远挂在那儿。
  > **为什么废弃「新蛋诞生就退场」**:用「有没有新蛋」代理「语境翻篇了没」是拿算术猜语义 ——
  > 用户写「今天还是很累」,蛋出来了,关怀就被判死,可那句话还贴切着。而且它和冷却叠加会
  > **吃掉每一次转折**:关怀第二天被新蛋杀掉 → 冷却立刻开始 → 「你好起来了」永远说不出口。
  > 这跟 v1 用「连续三篇 sad」猜低谷是同一类错误,只是藏得更深。
  > ⚠️ 已知缺口:AI 只能表达「保持」或「替换」,没法说「撤掉但不换新的」。所以一句略过时的话
  > 最多多挂到第 3 天。等真觉得难受再上三元契约(keep/replace/retire)。
- **关怀最长挂 3 天**(内容保质期,同时充当露面次数上限)。这个数不能放大。
- **冷却 1 个自然天**(原来 3 天)。「要不要换」交给 AI 之后,本地这条只剩兜底作用;
  而「同一天不会重复」已经由闸门条件①(有新蛋)保证了。
  **按自然天算,不按小时** —— 今天 10 点开、明天 9 点开只差 23 小时,按小时会被挡下,
  但那只是打开时刻的随机偏差。日历换算在 `CareGate` 里做,纯函数只比数字。
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
| 12 | 聊天检索·检索层 | `RecallRule` 三路召回(关键词/向量/情绪同调)+ RRF 融合;`bge-small-zh-v1.5` 转 Core ML 端侧推理;手写 `BertTokenizer`;eval 29 篇语料 4 条标注,**融合 recall@10 = 1.00** |
| 13 | 周条翻周 + 底部 tab | 周条改成横向分页 collectionView(`weeks` 一次算全部周,**最后一个永远是本周**＝翻不到未来);`RootPagerViewController` 删掉,换成 `RootTabBarController` + 自绘 `FloatingTabBar`(左胶囊 2 个 tab + 右独立圆) |
| 14 | 月历 | **在周条上下拉**(或点月份标题)展开成月历(`MonthGridView` = 表头 + 6 行 `WeekRowView`);格子抽成共用的 `WeekRowView`,`Style.strip` / `.month` 两种摆法;选完日期收起并把周条带到那一周 |

#### 月历这块的判断(别推翻)

- **月历里「有蛋就不画日期」是不行的**。周条里可以(一行七天,扫一眼就知道哪天),
  但月历里**记得越多的月份、日期越读不到** —— 正好把最有价值的那些月变成不可用。
  所以 `.month` 下日期永远画,蛋缩到 30 挂在日期下面。
- **日期在上、蛋在下**。反过来(蛋在上)蛋会被读成上一行日期的,行距再大也纠正不过来。
- **月历能选的范围,周条必须跟得上**。`weeks` 的起点因此从「最早那篇日记所在的**周**」
  改成「所在的**月**的第一周」—— 否则月历第一行(上个月末那几天)点下去,
  `weekIndex(containing:)` 找不到,周条跳不过去,选中的日子在屏幕上看不见。
  **这不是凭空补 padding,是被月历的显示范围倒逼的对齐。**
- **约束动画的套路**:先把目标值写进约束,再在 `UIView.animate` 块里 `layoutIfNeeded()`。
  约束变化本身不是动画,是那句「重新布局」在动画块里执行才产生过渡。
- **旋转 180° 别写满 `.pi`** —— 两个方向等距,Core Animation 会随机挑一边,
  箭头有时顺时针有时逆时针。写 `.pi * 0.999`。
- **跟手拖动:进度只能有一份**。`applyMonthProgress(t)` 把 t∈[0,1] 施加到
  月历高度 / 周条 alpha / 卡片 alpha / 箭头角度上;拖动时每帧调,松手回弹时
  在动画块里调目标值。拖动和回弹各写一份迟早会漂。
- **下拉手势要同时装在周条和月历上**。只装周条不行:展开后周条 alpha 归 0,
  而 **UIKit 的 hitTest 会跳过 alpha ≤ 0.01 的 view**,它收不到手势,月历就推不上去了。
- **横滑翻周 vs 竖拉展开:两个手势要互斥,不是共存**。
  分工线在 `gestureRecognizerShouldBegin`:`|v.y| > |v.x|` 才接管,
  而且方向要对(收起只认下拉、展开只认上推)。
  一开始用 `shouldRecognizeSimultaneouslyWith` 返回 true 让它们共存 —— **错的**:
  竖拉时手指那点横向分量会同时被周条吃掉,一拉就误翻页。
  正解是 `weekStrip.horizontalPan.require(toFail: 竖向pan)`,让周条的横向滚动
  **等竖向手势先判定**:横拖时 shouldBegin 返回 false(= 失败)→ 周条立刻接管;
  竖拖时竖向手势进入 began → 周条永远不会开始,一点都不动。

#### 容器这块踩过的坑(别再踩)

- **`UITabBarController` 是懒加载的**。老的 pager 把每页的 `view` 都塞进 stack,
  等于强制所有子 VC 立刻 `viewDidLoad`;tab 只加载选中那页。
  于是 `SceneDelegate.onAppActive()` 那次 `broadcastDataChange()` 打到 `dataSource`
  还是 nil 的广场页,`applySnapshot()` 强解包直接崩。
  **广播一律先过 `isViewLoaded`** —— 没加载的页第一次出现时 `viewWillAppear` 会自己读,不会漏数据。
- **pager 切页不走 `viewWillAppear`,tab 会走**。pager 的每一页都同时挂在 stack 上、只是滚动
  位置不同,所以刷新只能靠 `pageVisibilityDidChange`;换成 tab 之后切页会正常走
  `viewWillAppear`,那个回调就成了冗余(白跑一遍 `fetchAll`)。
  **顺带暴露一个一直都在的问题**:选中日存在 VM(组合根建的单例)里,切走切回不会重置 ——
  停在过去某天时,写完日记回来看到的是那天的空列表,像是没存上。
  现在 `viewWillAppear` 里 `resetToToday()` + `refresh(jumpToCurrentWeek: true)`,
  每次进页都当成重新打开。
- **「周条要不要挪回本周」是 `refresh` 的参数,不是成员变量**。
  一开始用的是 `hasPositionedStrip` 这么个 flag,它实际编码的是「这次 refresh 是谁调的」——
  隐式状态,而且一个值要同时伺候三个语义不同的入口。
  改成显式参数之后:只有 `viewWillAppear` 传 true;`dataDidChange()`(数据在别处变了)、
  点某一天、孵蛋失败重画一律用默认值 false。
  **注意不能反过来「每次都跳本周」** —— `weekStrip.onSelect` 也走 refresh,
  那样你翻到上周、点上周三,周条会把自己弹回本周,那天就点不开了。
- **`UITabBarController` 每次布局都会重写子 VC 的 `additionalSafeAreaInsets`**
  (那本来是它给系统 tabBar 让位用的)。在 `viewDidLoad` 里设一次会被静静抹掉 ——
  **不报错、不崩,只是页面底部的东西被浮动条盖住看不见**。
  要设就设在 `viewDidLayoutSubviews`,并加相等判断防止改 inset 又触发布局来回震荡。
- **周条那种「横向 scrollView 套在横向分页 scrollView 里」的组合不要再造**。
  UIKit 的规则是:内层在**手势开始那一刻**就已经在边界、无法再朝该方向滚,
  这次拖动直接让给外层。`alwaysBounceHorizontal` 只覆盖「拖到一半撞上边界」,
  管不了「一开始就在边界」—— 表现出来就是「滑到头之后整页跳走」,看着像 bug。
- **`Day` / `Week` 这类要进 Diffable snapshot 的嵌套 struct 必须显式 `nonisolated`**。
  snapshot 的 item 类型要求 Sendable,而工程默认 MainActor 隔离、嵌套类型跟着隔离。
  (同 `SlimeItem` / `DayEggRecord` 的修法。)

### 正在做:主动关照 v2

按 [`docs/主动关照-v2.md`](docs/主动关照-v2.md) 第 0 节的十步走。**第 1–7、10 步已完成**,当前在**第 8 步**:

- ✅ 1–3 `DayEggService` 抽出、`SquareViewModel` 瘦身、补蛋挪到 App 激活
- ✅ 4 `DayEggStore.delete(for:)` + 孤儿蛋清理
- ✅ 5 数据层迁移:`CareMessage` 两态 + `retiredAt` + `referencedDates`;新增 `CareCheck`;删 `RuleCooldown`
- ✅ 6 删三条老规则与 `postSaved`,写 `CareGate` + 单测(9 条)
- ✅ 7 AI 决策层:`decideCare(window:recentlySaid:)` → `CareDecision`;退场判断也交给了 AI(见 §2.1)
- 🚧 **8 卡片生命周期**:`CareCardView` 已挂首页(滑出 / 10 秒兜底淡出已实测)。
  剩「点鸟巢·点母鸡·左滑时淡出」和「下次进首页它还在」要手点验证。
  **产品边界层(Layer 3)决定不做** —— 见下方「砍掉的东西」
- ⬜ 9 可观测:`CareCheck` 字段已写全,还差 debug 页(现在靠 `SceneDelegate` 里一段临时 print)
- ✅ 10 eval:24 条 golden set,5 次采样 **precision 0.91 / recall 1.00**,17 条完全稳定

#### 砍掉的东西(规格里有,实现时决定不做)

- **Layer 3 产品边界**:去重归 AI(本地只认得出字面复读,认不出「意思一样换个说法」,
  而后者才是真问题;本地硬做语义判断就是跑回 v1);总开关等真有设置页再加。
  **所以「三段管道」在实现上是两段** —— 闸门 + AI。
- **关怀卡片沉淀回蛋上**(规格 §5):`referencedDates` 已经存对了,展示还没做。

#### 实现时踩过的坑(别再踩)

- **退场必须同时写 `status` 和 `retiredAt`**。v1 只改 `status`,`retiredAt` 永远是 nil →
  冷却锚点查不到 → 关怀天天弹。现在两行绑死在 `CoreDataCareMessageStore` 的私有
  `retire(_:at:)` 里,全类只有这一个出口。
- **退场时刻记「实际死的那一刻」,不是 `now`**。隔一周才打开 App,三天前就该走的关怀若记成
  「今天退场」,冷却又白等一轮。
- **`ISO8601DateFormatter` 默认时区是 GMT**,`DateFormatter` 才跟随本地。`referencedDates`
  用前者编码过,UTC+8 下整体差一天 —— 而且**只有查数据库才看得见**,print 看不出来。
- **eval 里模型摇摆,往往是标注不自洽**。踩过三次(#6/#19、#7/#8、#18/#24):
  两条几乎相同的场景标了相反答案,模型不可能对齐。
  **先并排比对同类场景的标注,再去改 prompt。**
- **prompt 里规则越多,每条越弱**。实测:同一条「至少三个日期」的改动,在 89 行的 prompt 里
  失效,精简到 68 行后就生效了。加规则前先想能不能删。
- **eval 用 3 次采样噪声太大**。实测同样的输入两轮跑,24 条里 8 条结果不同、3 条多数决翻转。
  **至少 5 次**(`TEST_RUNNER_EVAL_RUNS=5`)。

### 正在做:母鸡聊天的检索(RAG)

目标:聊天时按用户这句话检索相关的历史日记,让母鸡能像朋友一样「拿起来说」。
**跟主动关照是两套东西** —— 关怀看蛋的趋势,检索看日记的语义。

管线:提炼检索词 → 三路召回 → RRF 融合 → LLM 重排 → 生成(可以选择不说)。
中间两格已通,两头还没动。

- ✅ `RecallRule` 纯函数:三路打分 + RRF。**不碰 Calendar / 仓库 / 网络**,跟 `CareGateRule` 同规矩
- ✅ 端侧向量:`bge-small-zh-v1.5` → Core ML(45MB,fp32 输出)+ 手写 `BertTokenizer`
- ✅ eval:29 篇虚构语料 + 4 条标注,五种配置对比
- ✅ AI 提炼检索词:`extractRecallIntent` → 同义词扩展 + `shouldRecall` 否决权
- ⬜ LLM 重排 + 决定说不说
- ⬜ 接进 `ChatViewModel`

实测(2026-09-11):baseline(关键词+情绪) r@10 **0.95**,仅向量 **0.90**,三路融合 **1.00**。
Apple `NLEmbedding` 中文句向量 r@5 只有 0.11,**比随机的 0.17 还差**,有 hub 现象
(一条日记跟所有 query 都近)。已放弃,别再试。

同义词扩展的价值:三路全开时看不出来(向量已经把 r@10 拉满),**关掉向量**才露出来 ——
手工词 0.95 → AI 扩展词 1.00,差别全在「组长/领导/上司」那条上(0.80 → 1.00)。

#### 检索这条线踩过的坑(别再踩)

- **时间近因绝不能进排名**。相关回忆的价值恰恰在于久远;近因一参与打分,三个月前
  那件真正相关的事就永远上不来,整套检索退化成「最近 N 天」—— 那还不如直接把最近
  几天塞进 prompt。时间只在取数层做候选截断。**这条线一松,整个 RAG 就白做了。**
- **检索层考核 recall@10,不是 @5**。下游还有一次 LLM 重排,交出去的是十来条候选。
  @5 上三路互相挤、融合看不出优势,@10 上融合才是满分。**指标定错会得出反结论。**
- **RRF 里两张票压过一张票**:两路都排第 11 的会赢过单路排第 1 的。所以某一路在某个
  query 上整个跑偏时,融合一定被拖累,调 k 和加截断都救不回来。
- **Core ML 输出默认 fp16**,Swift 按 fp32 读 512 个数会越界 SIGABRT。转换时要显式
  `dtype=np.float32`。
- **Xcode 生成的模型类继承工程的 MainActor 默认隔离**。在 `nonisolated` 的类里用,
  析构时被调度回主线程,跨 executor 释放直接崩。改用 `MLModel` 通用 API 绕开
  (ObjC 类,不吃 Swift 的默认隔离)。
- **转换链路**:`transformers<5`,并且要绕过 `BertModel.forward`(直接调 `embeddings`
  和 `encoder`,显式传 position_ids 和 extended mask)。5.x 和那个 forward 里都有
  coremltools 转不了的算子。
- **分词器错了不会报错**,只会静静地编出错的 id,然后你会去怀疑模型和融合权重。
  `BertTokenizerTests` 的黄金对照是从 Python 导出的,换模型必须重导。
- **eval 已经饱和**:4 条用例里 3 条怎么测都是 1.00,新改动的好坏它分辨不出来。
  想继续调参就得先把 golden set 做难做大(更多换词、更多干扰、更长跨度)。
  **看到满分先怀疑是题太简单,不是做得太好。**

### 已知待清理

- `SlimeCell.swift` 无人引用,可删
- `ChatMessageItem` 缺 `nonisolated`(同 `SlimeItem` 的修法)
- `SceneDelegate` 里那段 `#if DEBUG` 的关怀检查 print,以及 `-CareStep2` / `-CareStep3`
  两幕开关 —— 第 9 步做完 debug 页之后可以收掉
- `CareViewModel` 目前只被首页用;`PendingCare.swift` 注释里「或用户主动关掉」已失效
- `PostDetailViewController.swift` 无人引用(详情已改成 `DiaryDetailView` 卡片内切换),可删
- `SceneDelegate` 里包着 `RootTabBarController` 的那层 `UINavigationController` 是摆设 ——
  全项目没有一处 `pushViewController`,compose / chat 都是 present。可以去掉

### 调试关怀系统的固定套路

1. Scheme 勾 `-UseTestStore`(Edit Scheme → Run → Arguments),否则 `DebugSeeder` 拒绝播种
2. 跑 App → 看控制台那段 `🔍 关怀检查`
3. 退出 App → `bash check.sh` 查库(**print 说的是代码以为干了什么,库里才是真发生了什么**)
4. 多幕场景:不加参数是第一幕(清库+播种);`-CareStep2` 保留关怀只补一颗转折的蛋;
   `-CareStep3` 补一颗平淡的蛋
5. 跑 eval:`TEST_RUNNER_RUN_EVAL=1 TEST_RUNNER_EVAL_RUNS=5 xcodebuild test-without-building
   ... -only-testing:SlimeTests/CareEvalTests -resultBundlePath X.xcresult`,
   然后 `xcrun xcresulttool export attachments --path X.xcresult --output-path DIR` 取报告
   (命令行跑测试时 `print` 会丢,所以报告走 `XCTAttachment`)

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
