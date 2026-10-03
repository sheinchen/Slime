# CLAUDE.md — 母鸡日记 项目常驻背景

> Claude Code 每次启动会自动读这个文件。它是本项目的"常驻记忆":锁死的决策、带我的方式、当前进度都在这里。请全程遵守。
>
> **我的工作分两条线**:这里是**执行线**(推进项目、写代码);我另有一个**教学对话**专门弄懂 iOS 概念。执行线负责往前做,遇到我不懂的概念,给够上手的解释即可,深挖我会拿到教学对话去问。

---

## 1. 项目一句话

一个有主动关怀能力的 AI 情绪日记 App:用户随手记录碎碎念,**一天的记录收束成一颗情绪蛋**(样貌由当天总结情绪驱动);一只 AI 母鸡在合适时机主动关心用户。记录是主干,主动关怀是差异化亮点。iOS 是呈现层。

> 📌 **产品形态已从「一篇日记一只史莱姆」改成「一天一颗蛋」**。首页是草地小岛 + 母鸡 + 鸟巢,点鸟巢写日记(点母鸡她只缩一下,10-02 起不再打开聊天);底部 tab 切到广场(日历)页是周条(可下拉成月历)+ 鸟巢 + 当天日记,**在日历页按住母鸡孵今天的蛋**;聊天入口只有 tab 条右边那个圆。
> ⚠️ 支持页(`relay/public/support.html`)和审核备注(`docs/App审核备注.md`)照着这些交互写,改了入口要回去改 —— 10-02 两处都写错过(孵蛋写成首页、聊天写成点母鸡)。
> 代码里仍沿用 `Slime*` 命名(`SlimeEmotion` / `SlimeItem` / `SlimeView`),`SlimeView` 现在是 `EggView` 里那团情绪。`SlimeCell` 已废弃。**看到 Slime 不要以为是旧代码。**

---

## 2. 技术决策(已锁死,不要改变或建议替换方案)

- **UI**:全 UIKit(不用 SwiftUI)
- **列表/集合**:现代 UICollectionView —— Compositional Layout + Diffable Data Source(不要用老的 UITableView + cellForRowAt 写法)
- **布局**:SnapKit(不要手写大量 NSLayoutConstraint)
- **存储**:Core Data
- **架构**:MVVM + Repository。View 只负责显示,业务逻辑在 ViewModel,数据读写全部走 Repository;跨仓库+网络的业务流程放 `Services/`
- **并发**:工程开了 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` —— **一切默认主线程隔离**,纯值类型/纯函数要显式标 `nonisolated`。注意默认参数表达式是**非隔离**的,不能在那里 new 隔离类型(要用 `= nil` + init 体内构造)
- **形态**:本地为主(纯单机,无登录、无账号);唯一网络依赖是 AI 调用(经 Cloudflare Worker 中转藏 key,代码在 `relay/`,见 §6「后端中转」)
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
- **本地层红线**:闸门代码里**不允许出现任何 `emotion` 字样**。它只回答三件算术:有新蛋吗 / 窗口内够 3 天吗 / 距上条关怀退场满冷却期吗。**一旦本地开始判断「低谷」「回升」,就是跑回 v1 了。**
- **关怀只看蛋,不看日记**。单篇日记的 emotion 服务于写完那一刻的 reply;蛋的总结情绪才是趋势载体。
- **生成 ≠ 展示,而且合并在打开时做**:写日记**不触发**任何关怀逻辑(`postSaved` 事件已废弃);唯一事件是 `appOpened`(入口在 `sceneWillEnterForeground`,外面套了防重入;09-24 从 `sceneDidBecomeActive` 挪过来,见「实现时踩过的坑」)。打开时才调 AI 生成文案 —— 这样文案永远基于最新窗口,情绪反转不会弹出过时关怀。
  > 2026-09-17 改:**窗口含今天**(原来是 `before: today`,暗中实现「跨自然天」)。今天的蛋只在按住母鸡时出现,那个动作本身就是「收束今天」。
  > 代价:铁律「关怀不出现在写日记那次会话里」不再有硬保证 —— 在 App 里连续写、孵不会触发,但切走两分钟再回来就可能评估。
- **顺序依赖**:打开 App 必须**先补完欠的蛋,再跑关怀闸门**。反了就缺最新一天,而那正是情绪反转的藏身处。已落在 `AppOpenFlow.runOnce()`(09-25 从 SceneDelegate 搬出来),`AppOpenFlowTests` 锁着顺序和防重入。
- **关怀退场交给 AI,本地只兜底**(2026-09-09 改;规格里那条「新蛋诞生就退场」已废弃):
  · **被替换** —— 关怀挂着时,AI 每次都能看到它(`PastCare` 带 `stillShowing` / `saidAt` / `about`),
    自己判断「旧的还贴不贴切」。判 `shouldShow: true` 就是「换成新的」,`show()` 会把旧的退掉。
    所以**替换和退场是同一个动作的两半**。
  · **「新证据」本地算好再给 AI**:有关怀挂着时每颗蛋带 `isNew`,AI 不自己比日期。
    判据 `蛋.date > 关怀那天 || (蛋.date == 关怀那天 && 蛋.createdAt > 关怀生成时刻)`。
    **跨天看日期**(迟补的旧蛋孵出时刻很新、内容很旧,不会被误标);**当天看时刻**(日记只能写进今天,这颗蛋不可能是旧账)。
    纯按孵出时刻会乱,纯按日期会漏掉「中午说了关怀、晚上重孵今天的蛋」和「昨晚说了关怀、之后又写一篇、今早补蛋」。
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
- 目录分层(09-25 整理过一次)。**按层分是主轴**(MVVM + Repository 的层次一眼看得出),层里面再按页面 / 子系统分:
  ```
  Slime/
  ├── App/              AppDelegate、SceneDelegate(组合根)
  ├── Models/           领域值类型(SlimeItem、PendingCare、CareDecision…)
  │   └── CoreData/     CoreDataStack、Slime.xcdatamodeld、实体类
  ├── Repositories/     仓库(只吐值类型)
  ├── Services/         不属于某个子系统的跨仓库流程:AppOpenFlow、DayEggService
  │   └── AI/           AI 网络层,见下方「AI 层」
  ├── Care/             关怀子系统:CareEngine、CareGate
  ├── Tutorial/         新手示范:剧本(TutorialFlow)、预设数据、假仓库、蒙层、导演。组合根在 App/TutorialAssembly
  ├── Recall/           检索子系统:RecallService(编排)、RecallIndexService、RecallRule…
  │   └── Embedding/    端侧向量:BertTokenizer、TextEmbedder、模型、词表
  ├── ViewModels/       ViewControllers/
  ├── Views/            Common / Style(配色字体缓动)/ Home / Square / Egg / Chat / Hen
  ├── Core/             跨层小工具:ChineseDate、母鸡的本地台词(HenGreeting / HenUnread)
  ├── Debug/            只在 Debug 构建存在:LaunchOptions、DebugSeeder、CareDebugViewController
  ├── Resources/        Assets.xcassets、Fonts、Images、Hen.riv
  └── Info.plist        **不能挪**:工程设置 INFOPLIST_FILE 写死了这个路径
  ```
  · **Care / Recall 是两个子系统,各自连编排带算法放一起**(RecallService 以前在 Services/,09-25 挪进 Recall/)。
    `Services/` 只放不归哪个子系统的流程。AI 的具体实现一律在 `Services/AI/`,子系统只认协议
  · 资源文件放哪个子文件夹都行:构建时一律平铺进 .app 根目录,代码按名字取(`Bundle.main.url(forResource:)`、`UIImage(named:)`)。
    09-25 挪完比对过 .app 里的 50 个条目,一个没变
  · `StubAIService` 虽然也只在 Debug 里有,但留在 `Services/AI/`:加新的 AI 协议时得同时改它,放在协议旁边不会漏
- 单测在 `SlimeTests/`(XCTest,`@testable import Slime`)。只测纯函数,不碰 Core Data。
  按子系统分:`App/`、`Care/`、`Recall/`;**要真调 API 的 eval 在各自的 `Eval/` 子文件夹里**(默认跳过)。
  `-only-testing:SlimeTests/CareEvalTests` 按类名找,不受文件夹影响
  ⚠️ **碰 App 里的类(VM / Service / 仓库)的测试,一律写成 `@MainActor` + `async`**,哪怕里面一个 `await` 都没有:
  ```swift
  @MainActor
  final class XxxTests: XCTestCase {
      func test_xxx() async { ... }
  }
  ```
  原因是 Swift 运行时的 bug(swiftlang/swift#85663、#87316):工程默认 MainActor 隔离 → 每个类的 deinit 都是
  isolated deinit;**对象在 Task 之外被释放**时,运行时给 task-local 建的标记用错了分配器,释放时
  `pointer being freed was not allocated` 直接崩(栈:`swift_task_deinitOnExecutorMainActorBackDeploy` → `StopLookupScope`)。
  同步测试方法跑在 Task 之外,所以对象一释放就崩;async 测试方法跑在 Task 里,不会。Xcode 26.4 修了,本机是 26.2。
  · 09-25 实测:同一个 `CoreDataPostRepository()` / `SquareViewModel()`(嵌套 `DayEggService`),同步测试 4/4 崩,async 3/3 过
  · **App 里撞不到**:开关一次聊天,`heap` 看 `ChatViewModel` 1 → 0 真的释放了,进程没崩
  · **别用** `keepAlive` 把对象留到进程结束(09-24/25 临时用过,是在掩盖而不是绕开),
    **也别**给每个类加 `nonisolated deinit {}` —— 为一个只在测试里出现的运行时 bug 改产品代码,升级 Xcode 之后全是死代码
  · 纯函数、`nonisolated` 值类型的测试照旧写同步的,它们没有 isolated deinit
- **依赖只从组合根来**(09-25 定):Service / ViewModel 的依赖参数一律必填,**不给默认值**。
  默认值只留给两类:① 值(`Calendar`、`now` 时钟、`AIConfig` 里的配置)② 本来就只有一个的共享资源
  (仓库的 `context` 默认 `CoreDataStack.shared.viewContext` —— 多建几个仓库对象也是同一个库,无害)。
  **判据:这个默认值被悄悄用上时,会不会多出一个有状态的实例,或者绕过打桩开关打到真 AI?会就不许给。**
  以前 `DayEggService` / `SquareViewModel` / `ComposeViewModel` / `CareViewModel` 都有默认值;
  去掉之后编译器当场揪出组合根**漏传了 `eggStore`**(VM 一直在用自己另建的那个)。
  例外两个都是 DEBUG 工具:`CareDebugViewController` 自己 new 仓库(注释里写了理由)、`DebugSeeder`。
- **AI 层**(09-25 拆,原来是一个 713 行的 `DeepSeekAIService`)。`Services/AI/` 下:
  · `AIClient` —— **唯一发请求的地方**:URL、安装 ID、状态码、外层信封、SSE。不懂任何业务。
    发给自己的中转(`AIConfig.baseURL`),**App 里没有 key,请求体里也没有 `model`**(中转定)
  · 一个能力一个文件,自带 prompt 和返回结构:`HenChatService`(写完日记回一句 + 聊天)、`DayEggSummarizer`、
    `CareDecider`、`RecallIntentExtractor`、`MemoryReranker`;共享人设在 `HenPersona`,聊天的 system 在 `ChatPrompt`
    (聊天上下文是 ChatViewModel 拼的,所以它不跟 HenChatService 放一起)
  · 协议没变(`AIService` / `DayEggSummarizing` / `CareDeciding` / `RecallIntentExtracting` / `RecallReranking`),组合根照样按位置换桩
  · **等多久由每个能力自己声明**(`AIClient.Patience`):写日记 `.total(8)`、重排 `.idle(15)`、其余 `.standard`(60 秒空闲)
  · ⚠️ **挪 prompt 必须整段原样搬**。多行字面量的缩进是内容的一部分(`HenPersona` 结尾 `"""` 顶格 → 正文带 4 个空格、末尾没换行)。
    09-25 是用脚本按行号从老文件切出来贴的,没手抄;搬完起一个本地假服务器(ATS 要在副本里开 `NSAllowsLocalNetworking`),
    老新两份代码各打一遍同一组调用:**6 份 system prompt 逐字节一致**,12 个请求按内容全等,8 秒 / 15 秒 / 不限时三种超时行为不变
  · 🔎 **发给模型的 JSON 载荷要加 `.sortedKeys`**(09-25 加上):不加的话 `JSONEncoder` 每次吐出来的键顺序都不一样,
    同一次运行里两次请求就一次「近14天」在前、一次「最近对ta说过的话」在前 —— 模型每次看到的排版不同,是 eval 的噪声源。
    **以后新加任何发给模型的 JSON,都要带 `.sortedKeys`**。加完重跑了关怀和重排两份基线(见各自一节)
- **仓库只吐值类型**(09-25 定):`Post` 等托管对象出不了 `Repositories/`。`PostRepository` 以前返回 `[Post]`,
  结果「转 SlimeItem + 按天归堆」写了两份、「这篇算哪天」散在 5 处、依赖它的 Service 没法用普通数组做假仓库。
  · **「这篇算哪天」只在 `CoreDataPostRepository` 里**(`day(of:)` + `dayRange` 谓词),下游直接用 `SlimeItem.day`
  · 老日记没有 `dayKey`,谓词里单独捞(`dayKey == nil AND createdAt 在区间里`)。**只写前半句,老日记会从广场上整片消失,不报错**
  · 10-02 起启动迁移(`DayStampMigration`)已经把缺的 `dayKey` 补上了,那半句只剩兜底。把它改成必填就能删 —— 改必填要加模型版本
  · `dayKey` / `DayEgg.date` 存的是**日历日期**,不是本地零点 —— 见 §6「换时区后日记消失」
- **改 Core Data 模型必须加新版本,不许就地改**(09-23 定):
  `Models/CoreData/Slime.xcdatamodeld/` 下每个 `.xcdatamodel` 是一个版本,`.xccurrentversion` 指向当前那个。
  **旧版本要留在仓库里** —— 老库的 metadata 存的是旧模型的 hash,Core Data 要在 bundle 里
  找到那份旧模型,才能推断出迁移映射。就地改等于把源模型删了 → `loadPersistentStores` 报错
  → 装过旧版的设备**每次打开都停在「日记本打不开了」**(10-02 前是 `fatalError` 直接崩),
  **而且只坏装过旧版的设备,你自己删了 App 重装反而看不见**。
  · Xcode 里走 Editor → Add Model Version(比手写文件靠谱),然后在右侧 File Inspector 里
    把 Model Version 设成新的那个
  · 验证:构建后看 `Slime.app/Slime.momd/`,里面该有每个版本的 `.mom`,
    `VersionInfo.plist` 的 `NSManagedObjectModel_CurrentVersionName` 是新版本名
  · **真验一次迁移**:`git worktree add` 一个旧 commit → 用旧版建一个库 →
    `simctl install` 覆盖装新版(容器会保留)→ 看列加上了没、行还在不在。09-23 这么验过一次
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
| 6 | 接入 AI 情绪分析 | `AIService` 协议 + `DeepSeekAIService`(json_object);Post 加 `reply`;**失败不伪造不存帖,上抛让 VC 弹提示**(「不存帖」已被切片 15 推翻,「不伪造」保留) |
| 7 | 主动关心 v1 | 五段管道跑通(Event→Rule→引擎→AI 话术→气泡演出)。**已被 v2 取代,代码已于切片 11 删净** |
| 8 | AI 聊天 | `ChatSession`/`ChatMessage`;SSE 流式(`URLSession.bytes` + `AsyncThrowingStream`) |
| 9 | 母鸡日记(产品大改) | 一天一颗蛋:`DayEgg` 实体 + `DayEggStore` + `summarizeDay`;首页草地小岛 + Rive 母鸡 + 鸟巢;`RootPagerViewController` 左右分页;周条 + 日记列表 |
| 10 | 补蛋抽成服务 | `DayEggService`(`hatchAllPending` / `prefetchToday` / `finishToday`)+ `EggDebt` 判定规则;`SquareViewModel` 瘦身 60 行;组合根建唯一实例,补蛋从「进广场页」改到 `sceneDidBecomeActive` |
| 11 | 主动关照 v2·本地层 | 数据层迁移(`CareMessage` 两态 + `retiredAt`/`referencedDates`、新增 `CareCheck`、删 `RuleCooldown`);`CareGateRule` 纯函数闸门 + `CareGate` 取数;`CareEngine` 编排退场→闸门→记日志;**新建 SlimeTests target,10 条单测**;v1 代码删净 |
| 12 | 聊天检索·检索层 | `RecallRule` 三路召回(关键词/向量/情绪同调)+ RRF 融合;`bge-small-zh-v1.5` 转 Core ML 端侧推理;手写 `BertTokenizer`;eval 29 篇语料 4 条标注,**融合 recall@10 = 1.00** |
| 13 | 周条翻周 + 底部 tab | 周条改成横向分页 collectionView(`weeks` 一次算全部周,**最后一个永远是本周**＝翻不到未来);`RootPagerViewController` 删掉,换成 `RootTabBarController` + 自绘 `FloatingTabBar`(左胶囊 2 个 tab + 右独立圆) |
| 14 | 月历 | **在周条上下拉**(或点月份标题)展开成月历(`MonthGridView` = 表头 + 6 行 `WeekRowView`);格子抽成共用的 `WeekRowView`,`Style.strip` / `.month` 两种摆法;选完日期收起并把周条带到那一周。**展开后横滑翻月**(月历也改成横向分页 collectionView,`months` 同 `weeks` 一次算全,最后一个永远是本月) |
| 15 | 没网也能写日记 | **先存后分析**:点「收好」先落库(情绪、回复留空),再问 AI 补上;问不上母鸡说一句本地的「收好了」(`HenUnread`)。模型 **Slime 3**:`Post.emotion` 改可选、去掉默认 calm;`Post.slimeEmotion` 是唯一读口。`analyzeSession` 8 秒总时限,等待中不给取消 |
| 16 | 孵今天·弱网 | 「今天正在孵」进 VM(`hatchingToday`),鸟巢画空白蛋 +「孵着呢…」;结果回来走 `refresh()`,不再画到别的日子上;`finishToday` 落库前再对一次日记;失败的预取不留着。**孵蛋不加总时限** |
| 17 | 后端中转藏 key | Cloudflare Worker(`relay/`,线上 `slime-relay.hen-diary-2026.workers.dev`):认门 → 限流 → 白名单重建请求 → **原样边收边转**。App 只带安装 ID;模型、`max_tokens` 由中转定;`Secrets.plist` 挪出 `Slime/`。eval 也走中转 + 开发者通行证 |
| 18 | AI 同意(上架合规) | **不同意就用不了**:没同意时根页面是 `AIConsentViewController`,主界面不在窗口上;`AIConsentStore`(UserDefaults 存同意的版本号);`AIClient.makeRequest` 第一行的闸;首页齿轮 → `SettingsViewController` 撤回。单测 11 条(含闸的反向验证) |
| 19 | 隐私政策页 | `relay/public/privacy.html`(中英双语),中转 Worker 用 `assets` 顺带托管 → `…workers.dev/privacy`;`AppLinks.privacyPolicy`;设置页「隐私政策」+ 同意页「阅读完整的隐私政策」(`SFSafariViewController`);同意页补「DeepSeek 可能用来改进模型」→ **同意版本 1 → 2**。09-28 填好开发者名字 / 邮箱并部署,同时上线支持页 `/support` |
| 20 | 新手示范 | 同意之后先进示范:母鸡带着用**真页面 + 内存假数据**走一遍「写预设日记 → 按住母鸡孵蛋 → 翻卡 → 翻周 → 下拉月历 → 翻月 → 点一颗蛋 → 删一篇看重孵」。蒙层是单独一个窗口(洞里的点穿透到下面);剧本是纯函数 `TutorialFlow`;能跳过、只出现一次、不能重看。模拟器全程走过 |

#### 新手示范(09-29 定,别推翻)

- **真页面 + 内存假数据**,不是另画示范屏,也不是写进真库再删。页面只认协议,`TutorialAssembly` 换上 `InMemoryPostRepository` / `InMemoryDayEggStore` / `EmptyCareMessageStore` / `TutorialAI` 就能跑。
  写进真库的话,假蛋会进关怀的趋势、假日记会被检索搜到,中途杀 App 还有残留。**09-29 模拟器走完查过测试库:示范的日记和蛋 0 条**
- **先试过「情境提示」又整个删了**(首页底部换句话、母鸡下面「按住我」、橙色小胶囊)。用户要的是「带着走一遍」,两套并存信息会重复
- **能跳过、只出现一次、不能重看**。`Tutorial.finished`(UserDefaults)只记「看完 / 跳过」,不存进度 —— 中途被杀下次从头来。开发时用 `-ResetTutorial`
- **蒙层在自己的窗口里**(`windowLevel = .normal + 1`):写日记页是 present 出来的,addSubview 到主窗口会被它盖住。洞里的点 `hitTest` 返回 nil,系统接着问下面的窗口
- **画出来的洞比能点的范围大**:首页鸟巢旁边站着母鸡,洞的边上点到的该是鸟巢不是她（以前点她会打开聊天，10-02 去掉了）。放行的只是锚点 view 本身的 frame
- **锚点靠 `accessibilityIdentifier` 找**(`TutorialAnchor` 的 rawValue),页面不用为示范开口子。改名要两边一起改。每帧重算洞的位置(岛在浮、月历在展开)
- **页面怎么告诉示范「做到了」**:`SquareViewController.onUserAction`、`RootTabBarController.onPageChange`、写日记页的工厂被调用 / `onClose`、假仓库的 `onCreate`。**正式 App 里这些都没人听**
- **剧本的前提靠示范数据撑着**:今天早上预置一篇(写完才有两篇可翻)、过去每天正好两篇且蛋比日记新(点哪天都能删、删完能重孵)。
  数据分两段:最近 10 天 + **32~41 天前的 6 天** —— 只有最近 10 天的话,月底打开时全在本月,月历只有一页,「翻月」滑不动。
  `TutorialSandboxTests` 把一整年每一天都当「今天」试过(上一周有日记、上个月有蛋),改 `TutorialScript` 要跑它
- **「点一天」只教一次,在月历里**(10-02 用户指出重复):原来周条上点一天、月历里又点一颗蛋,教的是同一件事。
  留月历那次 —— 点完日子跳过去、月历自己收起,「选一天」和「从月历回来」一下都会了,删除也接着在那天上做。
  「换一天试试」(`pickDayToDelete`)只是点到今天 / 空日子时的兜底,正常走不到。
  (删掉周条那次,也顺带去掉了一个坑:今天是周日时本周没有过去的日子可点)
- **翻周 / 翻月认的是 `onSwipedWeek` / `onSwipedMonth`**(松手停稳、而且真换了一页才报),不是原来的 `onWeekChange`:
  那个拖到一半就报(标题要跟手),`jump` / `configure(jumpTo:)` 这种代码跳页也会报
- **翻月这步不能混过去**:月历拉下来直接点一天(月历先收起、再报选了哪天)→ 回到「往下拉」;翻过月再推回去才进「再拉下来点一颗」(`repullMonth`),不用重新翻
- **教什么就只放行什么**(09-29 用户实测踩到):蒙层只管「点哪里」,可洞里的东西身上不止一种手势。
  教翻周时往下拉 → 月历展开、周条淡成透明、洞没了,整屏点不动;教翻卡时长按 → 能把今天一篇删掉、只剩一篇拖不动。
  → 日历页两个开关 `allowsMonthToggle` / `allowsCardEditing`(正式 App 一直开着),导演每换一步照 `TutorialFlow.allowsMonthToggle(at:)` / `allowsCardEditing(at:)` 去拨。
  只有教月历那四步能拉月历、只有教删除那两步能长按。**以后加新步骤,先想洞里那个东西还有哪些别的手势**
  · 没选「拉下来了再教推回去」:试过,能走通,但那是给一条本不该开的路补出口
- **每个说话的步骤,要么有「继续」、要么露出能点的东西**,否则蒙层把人卡死。`TutorialFlowTests` 有一条专门查这个;「没孵出来」也要退回「按住我」,不能停在「等」
- 已知:示范期间正式那套的 AppOpenFlow 照常在后台跑(补蛋、关怀),碰的是真库,跟示范互不相干

#### 后端中转(09-26 定,别推翻)

- **key 只在 Cloudflare 的 secret 里**(`wrangler secret put`),代码、配置、App 里都没有。
  以前 `Slime/Secrets.plist` 会被打进 App —— `Slime/` 是自动同步的文件夹,**放进去的任何文件都进包**。
  现在 `Secrets.plist` 在**仓库根目录**(`DeepSeekAPIKey` 留作部署用、`RelayDevToken` 给 eval),`.gitignore` 照旧忽略。
  **验证方式**:干净构建(`clean build`,增量构建可能残留删掉的资源)后,拿 key 的真实内容 `grep -rlF` 整个 `.app` → 0 个文件
- **中转不懂业务**:不看 prompt、不解析回答、不记内容(日记是最私密的东西),只记上游状态码。
  所以 prompt 还在 App 里,eval 照旧在客户端跑
- **白名单重建,不原样转发**:只挑 `messages` / `response_format` / `temperature` / `stream` 四个字段,
  `model` 和 `max_tokens`(2048)由中转定。原样转发 = 别人塞 `tools`、换贵模型,中转成了免费的通用 DeepSeek。
  顺带:**换模型不用发 App 新版**(改 `wrangler.jsonc` 的 `MODEL`,先跑 eval)
- **必须边收边转,不能攒完再回**(跟「写日记:先存后分析」里那条总时限 / 空闲超时是一回事):
  DeepSeek 拥堵时先回 200 再一直发空行保活,App 的 60 秒空闲超时靠「有字节在到」续命。
  所以是 `new Response(upstream.body)` 直接交出字节流,并加 `Cache-Control: no-transform`
  (防 Cloudflare 边缘压缩把零碎小块攒起来)。09-26 用假上游在 Node 模拟和本地 workerd 里各验过:空行每 0.5 秒到一个
- **错误分两类**:中转自己拒的是 4xx(`bad_*` / `too_*` / `rate_limited`),上游的错一律 502 `upstream_<状态码>`。
  **`upstream_401` = key 没设对,`upstream_402` = 余额不足**。App 不区分,非 2xx 都是 `AIError.badStatus`
- **限流是减速带,不是墙 —— 09-26 线上实测量出来的**:每个安装 ID 30 次/分、每个 IP 60 次/分。
  同一条连接连发:第 32 次开始 429 ✅;**每次新开连接连发 105 次:一次都没拦住**(连 IP 那道也没有)。
  Cloudflare 的限流是按机器缓存、异步同步的,新连接被打散到同机房不同机器上。
  正常 App 会复用连接(HTTP/2),计数基本准;**刻意每次新开连接的脚本拦不住**。
  → **真正封顶损失的是 DeepSeek 余额(预付费),账户里只充小额是硬要求,不是建议**。
  要做实:Durable Objects 强一致计数,或 App Attest(要真机 + 开发者账号)。等真看到异常流量再做
- **安装 ID 不是凭证**:`AIConfig.installID`,第一次用到时生成的 UUID,存 UserDefaults。谁都能伪造,所以才有 IP 那道
- **eval 也走中转,不留直连后门**:模型是中转定的,直连的话中转一换模型,eval 测的还是旧的,基线跟 App 对不上。
  **开发者通行证**(`X-Dev-Token`,中转那边是 `DEV_TOKEN` secret)只给 eval:重排 eval 并发 4 路、一分钟上百次,
  被限流时重排返回空选 —— **跟「模型判断不提旧事」一模一样,eval 会静默算错**。
  通行证从仓库根目录的 `Secrets.plist` 读(`#filePath` 定位,模拟器里的进程能读 Mac 上的文件),**永远不进 App**。
  比对用恒定时间比较(`crypto.subtle.timingSafeEqual`),不用 `===`
- 🔎 **DeepSeek 会在背后换 `deepseek-chat` 指向的模型**:09-26 发 `deepseek-chat`,回复的 `model` 字段是 `deepseek-flash`。
  以前直连也一样,不是中转造成的。**eval 莫名漂移时先看这个字段**
- **09-26 端到端验过**(改中转相关的东西后照这个再验一遍):
  · 线上:重排 eval 全量 26×5 走中转,和 09-25 直连基线一致(逐条全对 24/25、must 100%、exclude 4/125、空选守住 56/60,
    唯一判错仍是 #5);**130 次 4 路并发无一被限流**(被限流会表现成正例莫名空选);关怀 #1–#4 4/4、禁词 0
  · 模拟器 `-UseTestStore`:写一篇 → 库里情绪、回复都补上了(中转 0.95 秒);聊一轮 = 3 个请求
    (提炼 / 重排 / `Accept: text/event-stream` 流式)全 200,中转 CPU ≤ 1 毫秒(免费版上限 10)
  · 看线上请求:`relay/` 下 `npx wrangler tail`(只有状态码和请求头,不含内容)
  · ⚠️ 模拟器工具的 `text` 打中文会变乱码(UTF-8 被当 MacRoman 解)。绕法:`LANG=en_US.UTF-8` 下
    `printf '%s' "中文" | xcrun simctl pbcopy <udid>`,再在输入框里点两下调出菜单点 Paste

##### 部署 / 运维踩过的坑

- **`wrangler` 命令必须在 `relay/` 下跑**。在仓库根目录跑 `secret put` 报「Required Worker name missing」,
  而且 `../Secrets.plist` 会指到 `Desktop/` 去、读出空串。命令开头写 `cd .../relay &&` 最保险
- **secret 要用 `printf %s "$(…)"` 喂**,去掉末尾换行 —— 带着换行存进去,key 变成 `sk-xxx\n`
- **新注册的 workers.dev 子域名,头几分钟 TLS 握手失败**(`sslv3 alert handshake failure`),等证书签好就行,不是代码问题
- 完整部署步骤、换 key、看日志、错误码表:见 [`relay/README.md`](relay/README.md)

#### AI 同意:不同意就用不了(09-26 定,别推翻)

- **为什么要有**:审核规则 5.1.2(i) —— 把个人数据交给第三方(**明确点名了第三方 AI**)之前,要讲清楚并拿到明确许可。
- **选了「必须同意」,没选「可以拒绝、App 退化成本地日记」**。后者看着像「切片 15 的路现成」,其实只有写日记那条是现成的:
  蛋靠 AI 总结,关掉就孵不出来(鸟巢永远「还在孵」、按母鸡说「等会儿再按我试试」—— 都在骗人),聊天整个就是 AI。
  要为「关着 AI」的状态改鸟巢文案、写日记台词、聊天入口 —— 为不用核心功能的人付一整套成本。
  代价:5.1.1(iv) 不许强迫同意「不必要的」数据访问,有小概率审核员认为「写日记不需要 AI」打回来。**真被打回再做「可以拒绝」那版**。
- **撤回入口不能省**:5.1.1(ii) 要求 App 内有「容易找到、看得懂」的撤回方式。撤回 = 回到同意页,日记留在本机,重新同意接着用。
- **两道闸,各管一件事**:
  · `AIClient.makeRequest` 第一行 —— **合规**。三种调用(JSON / 文本 / 流式)都经过它,哪条路出 bug 都漏不出去。
    放 `complete` 里会漏掉流式。`isSendingAllowed` 必填、没默认值:漏传就编译不过,不会悄悄放行
  · `sceneWillEnterForeground` 的守卫 —— **体验**。冷启动时同意页还在,流程已经开跑;只靠 AIClient 挡的话,
    补蛋会记一次失败、**30 秒内不重试**,用户读完点「同意」正好卡在冷却里,欠的蛋要等下次回前台。
    所以没同意就整条不跑,`didAgree()` 里手动补跑一轮
- **存版本号,不存 Bool**。发给 AI 的内容变了(多一种数据、换接收方)→ `AIConsent.currentVersion` +1,
  同意页文字同步改 → 所有人重新看一次。存 Bool 就没法让旧同意作废
- **同意页是根页面,不是弹窗**:`setRoot` 换 `window.rootViewController`。弹窗的话主界面就在底下,有路绕过去
- **验证**:`AIClientConsentGateTests` 用本机没人监听的 9 号端口 —— 真发出去了报 URLError,发之前被拦才是 `notAllowed`。
  **把闸删掉,「没同意」那两条会挂**(09-26 反向验过)。模拟器走过:新装 → 同意页 → 同意 → 首页 → 齿轮 → 撤回 → 同意页 → 杀掉重开仍是同意页
- **DeepSeek 那两句是 09-26 对着原文核过的**:它的隐私政策写明在中华人民共和国境内收集、处理、存储,并会用个人数据训练模型;
  但它**明说不管开放平台下游 App**,而开放平台条款没说 API 数据存哪、存多久、训不训练,只要求开发者自己向用户交代。
  → 所以按最保守的写:「在中国境内处理和存储,可能会保存、用来改进自己的模型」。**宁可多告知,不能少告知**
- **同意版本 2(09-26)**:补了上面那句「可能用来改进模型」。发的东西没变,但接收方会怎么用变了 ——
  看过第 1 版的人没被告知这一条,所以 +1。**这是版本号机制第一次真用上**

#### 隐私政策页(09-26)

- **挂在中转 Worker 上,不另开网站**:`wrangler.jsonc` 的 `assets` 指向 `relay/public/`,请求先找静态文件、找不到才进 `index.ts`,
  所以 `/chat/completions` 不受影响。`/privacy` 直接对到 `privacy.html`(`/privacy.html` 会 307 过去)。
  本地 `wrangler dev` 验过:`/privacy` 200、中转照旧认门(不带安装 ID 400)、别的路径照旧 404
- **三处要一起改**:页面(`relay/public/privacy.html`)、同意页(`AIConsentViewController`)、`AIConsent.currentVersion`。
  改了发给 AI 的东西或接收方,三处不同步 = 页面在骗人
- **页面上每一句都对着代码写,但只写「发什么数据」,不写实现参数**(09-28 拿掉了「关怀看 14 天」「旧日记片段每篇最多 160 字」,改成「最近一段时间的蛋」「相关的旧日记内容」—— 跟同意页一个粒度。说法宁可往宽了写,不能比实际发的窄)。
  10-01 又收了一轮(用户觉得实现讲太多):去掉文本向量、密钥藏在哪、状态码、限流计数过期这些;四张功能卡片并成一张「发什么」的清单;通篇改成第一人称「我」(个人开发)。
  仍然写着、不能再删的:发出去的有**写下的时间**、**母鸡说过的话**、**相关旧日记**;安装 ID 和 IP 只用于防滥用;中转不保存内容。
  **聊天不保存**(10-03 起,见「聊天不存库」):页面、同意页「留在手机上的」、设置页撤回说明都写的是「聊天不保存,关掉聊天就没了」。
  以后要是加回聊天历史,这三处要一起改回来
- **App Store Connect 的「隐私政策网址」填 `https://slime-relay.hen-diary-2026.workers.dev/privacy`**,跟 `AppLinks.privacyPolicy` 必须一致
- **09-28 已部署**。开发者名字(陈诗莹 / Shiying Chen)、联系邮箱(chenshiying2002@163.com)在隐私政策和支持页里各有中英两处,改的话两页一起改
- **支持页** `relay/public/support.html` → `…workers.dev/support`,填 App Store Connect 的「支持网址」。「常见问题」照着 App 的实际交互写(点鸟巢写、按住母鸡孵、日历页长按卡片删),**改了交互要回来改**。「如果你现在很难受」那节是本地写死的求助指引(findahelpline.com),不经过 AI —— prompt 规定母鸡不编号码,App 里真实的求助资源只有这里

#### 写日记:先存后分析(09-23 定,别推翻)

- **日记是用户的,回复是母鸡的,不能绑在一起**。切片 6 的「失败不存帖」当时是对的:一篇日记就是
  一只按情绪画的史莱姆,没情绪画不出来。改成一天一颗蛋之后,卡片只画时间和正文,
  单篇情绪只剩三处当参考(一天总结的输入标签、检索的情绪那一路、关怀聊天的背景)——
  前提没了,规则就该跟着走。再绑着,日记能不能写 = DeepSeek 能不能用(没网、拥堵、402、以后的中转后端)。
- **没读上 = `nil`,不是 calm,也不是第七种情绪**。6 类情绪锁死;也别拿本地关键词猜一个 ——
  猜的和 AI 给的存在同一列,以后分不出来。`?? .calm` 是这里最大的坑:以前 emotion 必填、默认 calm,
  **切片 5 之前的老帖子就是被迁移这样悄悄填成 calm 的**。所以 Slime 3 连默认值一起删了,
  读情绪只走 `Post.slimeEmotion`。`RecallRuleTests` 里有一条专门防这个回潮。
- **本地那句不存进 `reply`**。它只是「收到了」,不是她读完的回应,存进去就是冒充。
  文案也不许诺「等会儿再看」—— **没做补读**(reply 过后不显示,情绪只是参考,缺几篇影响很小)。
  真觉得检索差了再加补读。
- **等待中不给取消,只靠 8 秒总时限**。「到点」在这里不等于失败(日记已经存了),所以敢设短;
  如果是「保原文」方案,到点 = 失败,设短误伤、设长困人,只能卡在 15 秒这种两头不舒服的位置。
  不取消也就省掉了一整套 `Task.cancel` + 区分「取消 / 失败」。
  等待中点背景回一句「咕,在听呢」(`listeningHint`)—— 不取消,但不能毫无反应,那才是「像卡死了」。
- **总时限必须是 `timeoutIntervalForResource`**。`URLRequest.timeoutInterval`(默认 60 秒)是**空闲**超时,
  有字节陆续到就重新计时,而 DeepSeek 拥堵时会一直发空行占着连接(最长 10 分钟)。
  09-23 本地实测:每 0.5 秒吐一个空行的假服务器,3 秒空闲超时 8.1 秒后照样成功;3 秒总时限 3.4 秒就 `timedOut`。
  `waitsForConnectivity` 保持 false —— 开了没网也要干等满时限。
- **`EggDebt` 那条「最多只欠一天」的前提不在了**:断网几天就攒几天债。`hatchAllPending` 本来就按天补,不用改逻辑。
- **验证**:`-StubChat -StubOffline`(配 `-StubAI` = 整个 App 断网)。09-23 在临时模拟器上真验过迁移
  (旧版播 32 篇 → 覆盖装新版 → 32 篇、情绪分布一条没变,store 元数据里 Post 的哈希换成了 Slime 3 的),
  以及断网写一篇(emotion / reply 都是 NULL)、真 AI 写一篇(补上了情绪和回复)。
  ⚠️ 模拟器工具打字走硬件键盘,软键盘会收起、「收好」按钮掉回下方 —— 按键盘弹起时的位置点会点空。

#### 按母鸡孵今天:弱网(09-24 定,别推翻)

- **孵蛋不加总时限**(跟写日记相反)。写日记要时限,是因为人被锁在弹窗里;孵蛋不锁人,
  等的时候可以随便切走。真断线有 60 秒空闲超时兜底;DeepSeek 拥堵时请求其实还活着在排队,
  等下去有机会孵出来,加时限只会「按一次失败一次」;慢但通的网,时限反而掐掉本来能成的。
  代价只有一条:打开 App 补蛋卡住时,关怀要晚几分钟才评估 —— 关怀本来就不急。
- **「今天正在孵」是 VM 里的状态**(`hatchingToday`,跟 `rehatching` 同一个思路),鸟巢按它画:
  空白蛋 +「孵着呢…」,`canHatchToday` 为 false。以前是等的时候切走再回来,
  蛋还没存、今天照实算还「欠」着,母鸡会被画回来、还能再按一次。
- **结果回来不直接往鸟巢上画,走 `refresh()`**。以前 VC 拿到总结就 `revealEgg` + `setCaption`,
  不管台上摆的是哪天 —— 等的时候点了周二,周二那颗蛋被翻成今天的表情、配上今天的总结。
  现在 configure 自己认「还是今天、台上还是那颗空白蛋 → 原地揭晓」,`revealEgg` 改成了私有。
- **`finishToday` 落库前再对一次「基于哪几篇」**,对不上就按现在的日记重孵。
  等的时候去首页写了一篇 / 在广场删了一篇,拿过时的总结落库,蛋会漏掉新的 / 带着删掉的,
  而且蛋比日记新 → `EggDebt` 判不欠,再也补不回来。以前等两三秒很难撞上,不加时限之后等待可能很长。
- **失败的预取不留着**。按到一半没网 → 松手 → 网好了按满,以前会直接拿到那次旧的失败。
- 失败文案「咕…没孵出来,等会儿再按我试试」,只在选中今天、还能再按时才说 —— 没网时「再试一次!」马上按只会再失败。
- **验证**:DayEggService 那两处用临时单测验过(假总结器 + 独立内存库,**跑完删了**,副本在会话 scratchpad):
  新逻辑 3 条全过;**换回旧逻辑 3 条全挂** —— 证明测试真能抓住这两个 bug。
  鸟巢那几种画面**还没在模拟器上亲眼验**(工具授权没给上)。自己验:`-UseTestStore -StubAI -StubSlow`
  (每一路拖 10 秒),按母鸡 → 看「孵着呢…」→ 点周条别的日子 → 切回今天 → 等揭晓。

#### 聊天不存库(10-03 定)

- **聊天只活在这一次对话里**:`ChatViewModel.messages` 就是全部,关掉聊天页 ViewModel 跟着释放,话就没了;下次打开是新的一段。
  `ChatRepository`、`ChatSessionInfo`、`ChatOrigin`(`.resume`)整个删了,组合根不再建聊天仓库
- **为什么**:以前每句都落库,可 App 里没有任何地方能翻看或删除旧对话(`.resume` 从来没被构造过)—— 越攒越多,
  用户看不到也删不掉,隐私政策还得写「聊天记录 App 里删不了」。没有「看历史」这个功能,存着就只剩风险。
  **没选「做一个历史页 + 删除」**:那是一整套 UI,为一个没人提过的需求
- **同意版本没 +1**:发给 AI 的东西和接收方都没变,变的只是手机上少存了一样。同意页那句「留在手机上的」照实改了,
  但不需要让所有人重新同意(只有「发出去的变了」才 +1)
- **`ChatSession` / `ChatMessage` 两个实体还在模型里**(Slime 3),代码已经一行不用。删实体 = 改模型 = 要加新版本(Xcode 里做),
  所以留到下次改模型时顺手删。到时轻量迁移会把两张表连同开发机 / 测试机上的旧聊天一起删掉。
  实体类文件(`ChatSession+CoreData*.swift` 等)跟着实体一起删,不要先删:实体还在而类没了,Core Data 会报找不到类
- 关聊天页时取消这一轮(`roundTask`)照样要:检索、流式请求停下来,不白花钱。半句不进 `messages` 那两个检查点也照样要 ——
  `messages` 是下一次发给模型的历史
- 模拟器验过:聊一轮(桩)→ 两张表 0 行 → 关掉再开,只剩母鸡的招呼

#### 聊天:发送与断线(09-27 定,别推翻)

> 10-03 起聊天不存库(见上一节)。下面讲「落库」「库里」的地方是当时的说法,现在对应的是「进 `messages`」。

- **用户那句先上屏,不等检索**:发送拆成两步 —— `addUserMessage`(同步:落库 + 进 `messages`)→ `reply`(检索 + 流式)。
  以前是一个 `send`,用户那句要等检索(两次 AI 调用,网慢时能挂一分钟)做完才出现,输入框已清空、列表里又没有,像消息丢了。
  **`addUserMessage` 没有 `async` 就是契约本身**:里面写不了 `await`,以后谁想往里加网络调用,得先改签名。
  `-StubAI -StubSlow` 模拟器实测过:点发送立刻出现,二三十秒后回复才到
- **关掉聊天页 = 这一轮作废**:VC 存着 `roundTask`,`viewDidDisappear` 里 `isBeingDismissed` 时取消
  (不写在 `closeTapped`:以后从哪条路关都不用记得来取消)。以前 Task 没人存、还强持有 VC,
  关了页面检索 + 流式照跑完,回复写进一个看不见的会话。
  ⚠️ **只 cancel 不够,两个检查点缺一不可**(`streamReply` 里的 `try Task.checkCancellation()`):
  · **流结束后**:取消时 `for try await` 是**正常退出**(流以 `.cancelled` 结束,不抛错),
    不拦的话半句被当成说完的话落库 —— 09-27 实测过,就是「断在半路」那个坑从取消这边又进来一次
  · **开流前**:检索把所有错误都吞了(`try?` / 重排 catch 全部),取消也被吞,检索照常返回 → 接着开流、白发请求
  `ChatIncompleteReplyTests` 两条锁着,**注释掉检查点两条都挂**(09-27 反向验过)。
  模拟器:`-StubAI -StubSlow` 发一句、检索期间关页面,73 秒后库里只有用户那句

- **`messages` 就是下一次发给模型的历史**。以前流断了会把半句落库、进 `messages`,
  重试时上下文最后一条是母鸡自己的半句 —— 模型以为自己已经回过话;之后每一轮、`.resume` 也都带着它。
  现在断了就丢:不落库、不进历史,屏幕上那半句换成「走神了」重试提示。**重试的上下文和第一次一模一样**
- **「连接关了」不等于「说完了」**:`AIClient.streamText` 只认 `finish_reason == "stop"`,否则抛 `AIError.incompleteStream`。
  没发 `[DONE]` 就断开、DeepSeek 资源不足中断(`insufficient_system_resource`)、写到上限(`length`),
  以前循环都正常退出,半句伪装成完整回复。最后一片内容为空、只带 `finish_reason`,**不能先按内容为空跳过**
- **没选「存半句 + 标未完成」,也没选「断点续写」**:前者要加模型版本 + UI 状态;后者要 DeepSeek 的 prefix 接口,
  中转白名单只放四个字段。母鸡回复 ≤40 字,重新生成一两秒,都不值
- 副作用:断了不重试、直接发下一句 → 历史里两条 user 连着。现在的模型能接受(没网失败本来就会这样);
  以后中转换成要求一问一答严格交替的模型,要回来处理
- **验证**:`SlimeTests/Chat/ChatIncompleteReplyTests`(假 AI + `URLProtocol` 假 SSE 服务器)5 条,旧代码上除「正常说完」外全挂;
  `RecallChatE2ETests` 真走中转一轮,正常说完不受影响(真 DeepSeek 最后一片确实带 `stop`)

#### 多轮聊天验收(09-27 建)

- `SlimeTests/Chat/Eval/`:`ChatEvalCases`(9 个场景，用户台词写死、**不接母鸡的问题**,每次跑的是同一段对话)、
  `ChatEvalRules`(尺子)、`ChatEvalTests`(同一个 ChatViewModel 里一句句聊，跟 App 同一条路)。尺子的单测 `ChatEvalRulesTests` 每次都跑
- 跑法同关怀 eval:`TEST_RUNNER_RUN_EVAL=1 ... -only-testing:SlimeTests/ChatEvalTests -resultBundlePath X.xcresult`,
  报告走 XCTAttachment。9×5 = 190 句，4 路并发约 1 分钟。`EVAL_ONLY=7,9` / `EVAL_RUNS=10` 照旧
- 三层：红线(prompt 逐字点名的 + 安全轮没说求助，XCTAssert)/ 验收指标(能数的，只报 ✅❌)/ 人工看点(每个场景写明，读记录)。
  **红线 0 + 指标全 ✅ 只说明机器能判的过了**,会不会聊天还要读记录
- ⚠️ 用户台词**不能撞 ChatPrompt 的示例**,模型会照抄示例那句回复
- **尺子是跑了四次才调准的，❌ 先读例句**:字面接住率 73%,读下来几乎都接住了(用「他」、用动作接)→ 降为参考;
  超 40 字 11 句里 10 句是安全轮 → 长度不算安全轮;「咕？」是叫声不是问题;问母鸡今天干嘛时说刨土是回答、不算动作重复;
  旧事按「件」数(只收「方案/PPT/九点」时漏掉了「早会」)
- **基线(第四次，最终版尺子)**:红线 1(#9 安全轮没说求助)、指标 13/17
- **四次合计(每个场景 20 段)读记录的结论**:
  · 稳的：安全轮说出求助 39/40;被追问身份 20/20 岔开、不承认不否认;不答应提醒 20/20;说了不聊就不再提 40/40;
    「他」指谁(#2)20/20;话题突然转(#3)20/20 跟上;平常回复 ~91% 在 30 字以内
  · **最大的问题：假装记得**。#7 第 1 句 20/20 说「Muji健忘啦」,第 2 句用户说出「换工作」后 **20/20 装作记得**
    (「哦那个呀」「还在憋着吗」),约三分之一编出具体细节(「Muji记得你提过在那边干得不痛快」「舍不得那几个天天一起摸鱼的」)。
    别处也会凭空编:「你上次说倒库总压线」「那个老让你加班的」「你上次说的那个面」。prompt 三只管住了第一问
  · **安全底线在「轻松 → 突然沉重」时不稳**:#9 有 1/20 完全没说求助(「你还没看我下完今天这个蛋呢」),约一半带着咕咕 / 感叹号;
    情绪慢慢往下走的 #5 只有 1/20 带咕。**多轮里前面的轻松语气会带进安全轮**
  · 旧事张冠李戴 1/20:「Muji上次跟小林吃火锅」—— 把 ta 的日记说成自己的(memoryContext 里「当成你自己记得的」可能被读歪)
  · 小毛病：同一个反应动作(啄 / 刨 / 蹲)一段对话里用两遍，约 20% 的对话;红线词「早点睡」1/190
- **09-27 改了 ChatPrompt 的一、三两条**(改动和数字的细节在 `ChatPrompt.swift` 的注释里)。
  做法：先补尺子(#7 第 2 句的「装作记得」词表、「不是安全轮却搬出求助」),再对 #5 #7 #9 **同一把尺子**各跑 10 次改前 / 改后，最后全量回归
  · 装作记得：改前 30/30 → 改后 0/25。**没改掉**:顺手给 ta 的处境补负面背景(「那个老板又惹你了吗」)约三成，改前改后差不多。
    猜测跟规则里「先接住那个东西(那个甲方…)」的「那个 X」句式有关 —— 没验证，要试就单独 A/B
  · 安全轮带咕咕 / 感叹号 14/60 → 4/30;说出求助 59/60 → 30/30(差在噪声里);「想哭」没被误判成危机(0 例)
  · ⚠️ **第一版写了「不咕」,#5 安全轮 10/10 开口念「不咕。」**,换成「拟声词」才没了。**规则里别放能直接说出口的短词**
  · 全量回归：红线 0(改前基线是 1)、指标 12/18;身份、话题转向、翻篇、长度都没被改坏
- 同一天又试了第 44 行：删掉「先接住它」后面的举例「(那个甲方、那家店、那份一个字没写的作业)」。
  猜测「那个 X」句式教会了模型去指 ta 没说过的东西。#1 #2 #3 #5 #7 各 20 次、同一把尺子:
  · 编 ta 的背景(#5 第 1 句 + #7 第 2 句)6/40 → 2/40;接住(#1~#3 字面)159/240 → 155/240,读下来照样点名「砸墙」「流水账」
  · **方向对但还不显著**(p≈0.26),留着：它是删不是加(规则少加)，还顺手堵了「那个甲方」被当成 ta 过去的漏
  · 为此加了参考指标「提到 ta 没说过的『那个…』」(`ChatEvalRules.unmentionedThat`):「那个 X」的 X 跟 ta 说过的话一个相邻字对都不重合就记。
    会误报(ta 说「他」、Muji 说「那个人」),只报不判
  · 全量回归：红线 0。字面接住率 76% → 67%,拆到场景看是 #3 #4 各掉几句 —— 读原句是用「她」「多大呀？」接住的，尺子认不出。
    **动作重复 10 → 16**,n=45 看不出是不是这次改的，下次全量盯一眼
- **现在的基线(删完第 44 行举例后全量)**:红线 0、指标 14/19。剩下的：动作重复、偶尔一句问两个、#9 安全轮偶尔还讲刨土;
  还有零星的凭空编过去(「你上次说的那种脆脆的饼干」「你上次坐过的那块地砖」),每轮 0~2 句，约 1%

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
  月历能横滑翻月之后是同一个问题,`monthGrid.horizontalPan.require(toFail: gridPan)` 同一个解法。

##### 翻月(09-18 定)

- **横滑换时间,竖拉换粒度**。收起时横滑翻周、展开时横滑翻月、上下拉在周和月之间切。
  **没选**标题旁加箭头(收起时箭头是翻周还是翻月说不清)和年月滚轮(历史只到第一篇日记那个月,范围太短)。
- **每页固定 6 行(6×7 = 42 格)**,不按月份算 5 行 / 6 行。翻到一半两个月同时在屏幕上,
  高度说不清该听谁的;改成跟着滑动位置插值的话,`monthGridHeight` 就有了两个写入方
  (展开进度 + 翻页位置),违反上面那条「进度只能有一份」。所以 `contentHeight` 是个常量。
  多出来的第 6 行最远只会超出本周几天,那些格子都是未来、不能点,所以「月历能点到的,
  `weeks` 里都有」这条对齐仍然成立。
- **不属于这一页那个月的日子:数字变淡、不画蛋、不画选中高亮**。同一天(8/31)会同时出现在
  八月页和九月页,这一页的「情绪地图」里只该有这个月的蛋。
  `isOutsideMonth` 描述的是「这一天在这一页上是什么身份」,**不是这一天本身的属性**,
  只能在生成那一页时算(`day(for:inMonth:)`),周条里永远是 false。
- **收起那一下标题不能跳**。展开时看的是七月,收起后标题变回九月会很突兀。
  `weekIndex(forMonth:current:)` 按候选队列挑:① 周条原来停的那周(展开再收起、什么都没做
  = 什么都没发生)→ ② 选中日所在的周 → ③ 这个月的第一周。**三条都要过同一个口径(`anchorDay`,见下一条)**,
  包括 ②:展开后从十月翻到九月再收起,选中的还是 10/2,那一周算十月,直接跳过去标题会从九月变成十月。
- **周条标题看 `anchorDay`**(10-02 定):选中的日子在这周里 → 写它所在的月;不在(翻到别的周看看)→ 取第四天。
  一周从周日开始,第四天是**周三**,也就是这周占天数多的那个月。⚠️ 以前注释和本文件都写成「周四判月」,**代码一直是周三**。
  为什么改:10/2 打开日历页,那周 9/27–10/3 按多数算是九月,可人正看着十月二号的日记。
  标题、展开到哪页、收起停哪周都走 `anchorDay`,改它三处一起变,「展开 / 收起标题不跳」照样成立。
  副作用(是想要的):同一周里点跨月的两天,标题跟着在九月 / 十月之间切。
  **没选「永远写今天的月」**:翻回八月的周,标题还写十月就错了
- **藏着的那一边,要在它露出来之前就对好位置**(`alignHiddenSide()`)。月历从高度 0 长出来,
  周条从 alpha 0 显出来,等动画结束再挪,会看到它在眼皮底下跳一下。
  所以调用点是拖动的 `.began` 和点标题,**不是**动画的 completion。
- **在月历里点某一天,不走「标题不跳」规则**。点的是上月末那几格时,周条就该去那一天,
  标题跟着变才是对的。
- **`refresh()` 要连月历一起刷**。月历展开时数据照样会变(切出 App 再回来会补蛋、
  鸟巢在月历下面照样按得到)。以前月历只在展开那一刻 configure,展开期间的变化看不见。
- 已知边角,没处理:最早那篇日记所在月份的 1 号如果是周四、周五或周六,那一周的第四天(周三)落在上个月(且选中的不在那周),
  `monthIndex(ofWeek:)` 返回 nil,就近取第一页 → 在这一周上展开,标题会从「四月」变成「五月」。
  只在翻到最开头时才会碰到。

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
  现在 `viewWillAppear` 里 `resetToToday()` + `refresh(jumpTo: viewModel.currentWeekIndex, ...)`,
  每次进页都当成重新打开。
- **「周条要挪到哪一周」是 `refresh(jumpTo:)` 的参数,不是成员变量**。
  一开始用的是 `hasPositionedStrip` 这么个 flag,它实际编码的是「这次 refresh 是谁调的」——
  隐式状态,而且一个值要同时伺候三个语义不同的入口。
  改成显式参数之后:`viewWillAppear` 传本周、月历选完日期传那天所在的周;
  `dataDidChange()`(数据在别处变了)、点周条上某一天、孵蛋失败重画一律用默认值 nil(不动)。
  (中间一版是 `jumpToCurrentWeek: Bool`,加月历时多了「跳到任意一周」才改成 `Int?`。)
  **注意不能反过来「每次都跳本周」** —— `weekStrip.onSelect` 也走 refresh,
  那样你翻到上周、点上周三,周条会把自己弹回本周,那天就点不开了。
- **`UITabBarController` 每次布局都会重写子 VC 的 `additionalSafeAreaInsets`**
  (那本来是它给系统 tabBar 让位用的)。在 `viewDidLoad` 里设一次会被静静抹掉 ——
  **不报错、不崩,只是页面底部的东西被浮动条盖住看不见**。
  要设就设在 `viewDidLayoutSubviews`,并加相等判断防止改 inset 又触发布局来回震荡。
- **切 tab 时 `pageVisibilityDidChange` 比 `viewWillAppear` 先到;页面还没挂上窗口时别开关 Core Animation 动画**(09-25)。
  首页的 `isOnScreen` 以前在 `viewDidDisappear` 里不复位,切回首页时 `syncRunningState` 在窗口外就把动画开了。
  窗口外加的动画挂上窗口后会丢,窗口外删的动画删不掉 —— 模型层 `animationKeys()` 是空的,屏幕上提示圈却一直闪
  (代码再也够不着的「幽灵动画」)。现在 `viewDidAppear` / `viewDidDisappear` 只报告在不在屏幕上,开关动画只走 `syncRunningState`。
  以前 `laidToday` 永远是 false、提示圈本来就该闪,所以一直没露出来
- **周条那种「横向 scrollView 套在横向分页 scrollView 里」的组合不要再造**。
  UIKit 的规则是:内层在**手势开始那一刻**就已经在边界、无法再朝该方向滚,
  这次拖动直接让给外层。`alwaysBounceHorizontal` 只覆盖「拖到一半撞上边界」,
  管不了「一开始就在边界」—— 表现出来就是「滑到头之后整页跳走」,看着像 bug。
- **`Day` / `Week` 这类要进 Diffable snapshot 的嵌套 struct 必须显式 `nonisolated`**。
  snapshot 的 item 类型要求 Sendable,而工程默认 MainActor 隔离、嵌套类型跟着隔离。
  (同 `SlimeItem` / `DayEggRecord` 的修法。)

#### 首次打开 Muji 晚出现(09-28 查清,别再为它改代码)

**结论:真实用户不会遇到。** 看到它只有两种情况,都是开发环境造成的:
- **模拟器 + 删 App 重装**:首页岛出来了 Muji 晚约 1 秒(933 / 967 ms)。模拟器缺一种 GPU 能力,Rive 用不上预编译着色器,
  第一帧只能现编、主线程干等。编译结果缓存在 App 自己的 `Library/Caches`,覆盖安装(Xcode 点 Run)还在,删 App 才清
- **真机 + 从 Xcode 挂着调试器跑 + 删 App 重装**:点同意后主线程卡 ~770 ms、首页上又卡 1255 / 886 ms,
  挨着 Metal 编译 Rive 着色器源码(控制台 `Compilation succeeded … program_source`)。关掉 Metal API Validation /
  GPU Frame Capture 没用,**取消 scheme 里的 Debug executable 就不卡了**。同一台真机不挂调试器:同意 → 首页 58 ms,
  没有一帧超过 50 ms,着色器是冷的时候也一样
- → 验「第一次打开」的体验要在真机上、**不挂调试器**(Edit Scheme → Run → Info → 取消 Debug executable,或者装好后从桌面点图标)

弯路(别再走):
- 读 Rive 源码推断「真机不会等」→ 真机挂着调试器看到了晚出现 → 以为推断错了、做了「同意页预热」(`HenWarmupView`,
  在按钮区底下偷画一只 Muji 先把着色器编好)→ 真机日志显示不挂调试器根本不等,挂着调试器预热也挡不住 → **已删**。
  **分清是 App 的问题还是调试环境的问题,先拿不挂调试器的真机跑一次**
- 同意 → 首页的淡入改成了「新页面先放好、旧页面截图盖在上面淡掉」(`SceneDelegate.setRoot`),不再用
  `UIView.transition(with: window…)`。它是不是真修了什么没验死(不挂调试器各看了一次:旧写法「好像一下子就冒出来了」,
  新写法不闪 —— 各一次、靠肉眼,不算数),留着是因为首页从第一帧起就是真画面,对 Metal 内容更稳

真修好的一个 bug:
- **母鸡第一帧必须先摆好位置**(`IslandView.layoutSubviews` 里 `place`):以前 position 只在帧循环里写、第二下才摆,
  之前停在 (0, 0) = 岛左上角外面。平时一两帧看不出,赶上第一帧等编译就是「从外面卡住再飞进来」(录屏逐帧看到过,修后没有)

怎么测的:模拟器录屏(`simctl io recordVideo`)+ 按像素颜色量「岛出现 → 母鸡出现」;真机用 `devicectl device process launch --console`
不挂调试器跑、读 print。Mac 没给摄像头权限,录不了 iPhone 屏幕

#### 冷启动白屏(10-02 修,别退回去)

**病根:向量模型在启动路径上同步加载**。`SceneDelegate` 以前 `try? TextEmbedder()` 在主线程加载 45MB 的 Core ML 模型,
首页出来之前。**装完或更新后第一次加载,Core ML 要为这台设备编译模型:iPhone 13 Pro 实测 1993 ms**,之后有缓存 80 ms。
其它全部(Core Data、Rive 母鸡、各页面)加起来不到 200 ms。→ 用户在**第一次安装和每次更新后**看 2 秒白屏

| 真机不挂调试器,首页 viewDidAppear 距进程启动 | 改前 | 改后 |
|---|---|---|
| 装完 / 覆盖安装后第一次 | 2205 ms | **166 ms** |
| 平时冷启动 | 197 ms | **133 ms** |

- **`TextEmbedder` 懒加载**:`init()` 什么都不做,第一次 `embed` 才 `load()`。调用方(补向量、聊天检索)本来就在 `Task.detached` 里,
  所以加载自然在后台。`NSLock` 护着「只加载一次」(预热、补向量、检索可能同时第一次用到);**失败也缓存**(`Result`),不会每次再花 2 秒失败一次
- **组合根在 `makeKeyAndVisible()` 之后 `Task.detached(priority: .utility) { embedder.warmUp() }`**。必须 `detached`:
  普通 `Task {}` 继承 SceneDelegate 的主线程隔离,2 秒又压回主线程。冷的时候后台要 4~5 秒,**首页一帧没掉**(>34 ms 的帧间隔 0 次)
- 行为变化:模型加载失败时 `recallService` 不再是 nil(以前整个不检索),检索退回关键词 + 情绪两路。`RecallVectorEvalTests` 改成拿第一次编码检查模型在不在
- 验过:单测 131 过 / 0 挂;`RecallVectorEvalTests` 跟基线一致(仅向量 r@10 0.90、融合不截断 1.00)
- **启动屏(`LaunchScreen.storyboard`)背景改成 `Sky.top`(#FEFCF4,sRGB)**。以前是 `systemBackgroundColor`:浅色模式白 → 米色闪一下,
  **深色模式是黑屏**再跳米色(App 颜色是写死的,不跟深色模式)。⚠️ iOS 会缓存启动屏截图,开发时覆盖安装可能还看到旧的,要全新安装才看得到
- **以后往 `willConnect`(启动路径)里加东西前先想:它首页第一帧要不要?** 不要就懒加载 / 放后台。本地的重资源(模型、大文件)尤其要当心「装完第一次」这个冷路径

量法(下次照这个):
- 临时探针用 `sysctl(KERN_PROC_PID)` 拿进程启动时刻,打印每个点距它多少毫秒(连 `main` 之前都算进去)。**测完删,删完 `grep` 一遍**
- 真机:`devicectl device install app` 覆盖安装 = 造出冷的 Core ML 缓存(不用删 App、不丢数据);
  `perl -e 'alarm 12; exec @ARGV' xcrun devicectl device process launch --device <id> --console --terminate-existing com.shiying.muji`。
  ⚠️ 别用「后台跑 + kill」:devicectl 的输出是攒着的,被 kill 就全丢。手机要解锁,锁着会报 `device was not, or could not be, unlocked`
- 方案先在**拷出来的副本**里改 + 加探针上真机验,验过再进项目 —— 项目里不留探针

#### 换时区后日记消失(10-02 修,别退回去)

**症状**:在 UTC+10 写的日记,换到 UTC+8 重开 App → 日历页整片空白(库里 32 篇都在);**今天的蛋被打开 App 的补蛋自动孵掉了**
(今天的日记被当成「过去欠蛋的一天」—— 违反「今天只能按住母鸡孵」)。

**病根**:`dayKey` / `DayEgg.date` 存的是「写的时候那个时区的零点」这个**绝对时刻**(+10 的 10-02 零点 = UTC 10-01 14:00),
上层拿「现在这个时区的零点」跟它**精确比对**(`==`、字典 key)。换了时区,两边差两小时,一天都对不上。

**修法:库里存「几月几号」,不存「零点那个时刻」**。不改模型(两列还是 `Date`),值换成「那个日历日期的 **UTC 零点**」:
- `DayStamp`(`Models/CoreData/`,纯函数):`stored(本地零点, in: 时区)` 写进库,`local(库里的值, in: 时区)` 读出来 =
  **当前时区那个日期的零点**。**上层一行没改** —— 它们拿到的还是「现在这个时区的零点」,照旧跟 `startOfDay` 比
- **换算只在两个仓库里做**:`CoreDataPostRepository`(`create` / `day(of:)` / `dayRange`)、`CoreDataDayEggStore`(每个查询先 `stored`、每条结果再 `local`)。
  漏一处,换了时区那处就对不上。DebugSeeder、两份 eval 直接写实体的地方也都改了
- 换算一律用**公历**(用户手机设成佛历 / 和历时 `Calendar.current` 的「年」不是公元年)
- `local` 先取那天**正午**再求 `startOfDay`:智利这类时区夏令时那天没有 00:00,直接拼零点会拼出一个不存在的时刻

**老数据迁移**(`DayStampMigration`,`CoreDataStack` 打开库之后、任何仓库读数据之前跑一次):
- 标记存在**库的 metadata**(`DayStampVersion = 1`),**不放 UserDefaults** —— 测试库和正式库共用一份 UserDefaults,
  放那儿的话迁了测试库、正式库就被跳过
- 保存失败要 `rollback` **并把 metadata 也还原**:不还原的话,内存里那个标记会在下一次随便哪个 `save` 时落盘,以后再也不迁
- `DayStamp.fromLegacy` 认三种值:① 已经是 UTC 零点 → 不动(幂等,迁两遍不会错)② 是当前时区的零点 → 按当前时区换
  ③ 别的(以前出门在别的时区写的)→ `+12 小时` 再取 UTC 那天。③ 覆盖 UTC−11 ~ UTC+12;**在 +13 / +14 写的老数据、又在别的时区升级,会差一天**(汤加、基里巴斯,接受)
- 缺 `dayKey` 的老日记顺手按 `createdAt` 补上

**验证**:
- 单测:`DayStampTests`(8 条,纯函数:六个时区互写互读、夏令时那天、迁移幂等)、
  `TimeZoneRepositoryTests`(5 条,**内存库 + 真仓库** —— bug 在「怎么存 ↔ 怎么比」这道缝上,只测纯函数测不到;`@MainActor` + `async` 见 §5)。
  **反向验过**:把 `DayStamp` 换回旧行为,5 条全挂,挂法跟症状一样(读到空 / 蛋的 key 差两小时 / 今天被补孵)
- 模拟器真升级:旧构建在 +10 播 32 篇 + 13 颗蛋 → 覆盖装新版、在 +8 打开 → 32 / 13 一条没少、值全是 UTC 00:00、每天几篇跟迁移前一致、
  今天没被自动孵、关怀窗口看到 10 天;再换回 +10 打开 → 一样,metadata 里有标记
- **换时区复现**:`SIMCTL_CHILD_TZ=Asia/Shanghai xcrun simctl launch <udid> com.shiying.muji -UseTestStore …`(只影响这一次启动的进程,不用改 Mac 的时区)

**已知边角,没处理**:
- **App 开着不重启、人跨了时区**:仓库、VM、Service 手里的 `Calendar` 是创建时的快照,要等进程重启才换。
  日记不会丢(存的是日期),只是这段时间里「今天」按旧时区算。要做就监听 `NSSystemTimeZoneDidChange`,跟 `syncToday()` 一个思路
- 卡片上的「几点写的」按**当前**时区显示:+10 凌晨 03:38 写的,在 +8 看是 01:38;在西边的时区看可能显示成「前一天晚上的钟点」,但还挂在写的那天。
  这是有意的:**日记属于「写的那天」**,不跟着人搬

#### 保存失败 / 库打不开(10-02 修,别退回去)

**以前的崩溃链**:仓库存失败只 `print` → 没存上的改动留在 context 里 → 页面以为存上了(写日记照样说「收好了」,App 一被杀就没了)→
下一次随便哪个仓库保存都带着它一起失败 → 切后台时 `saveContext()` 再存一次,那里是 `fatalError` → **崩**。最现实的触发是手机存储满了。
库打不开(迁移失败、空间满、文件坏)时 `loadPersistentStores` 里也是 `fatalError` → **每次打开都崩**,用户连自己的日记都看不到。

**保存**:
- 所有仓库只走 `context.saveOrRollback()`(`Models/CoreData/NSManagedObjectContext+Save.swift`):存不进去就 `rollback()` 再抛。
  撤回只撤得掉「这一次」—— 前提是仓库都在主线程、改完当场就存,context 里没有别处攒着的改动。**以后谁要攒一批再存,得先想这条**
- **往上抛的只有两处**,因为只有这两处有地方接:
  · `PostRepository.create` → `ComposeViewModel.save` → 写日记页停在输入页、字留在框里,弹「没存上」。
    VM 拆成 `save`(同步、会抛)+ `reply(to:)`(异步、不抛),跟聊天的 `addUserMessage` / `reply` 一个思路:**存是同步的,没有 `async` 就是契约**。
    存不上母鸡不上台 —— 上了台再退下来,看着像存上了又反悔
  · `DayEggStore.save` → 孵蛋本来就有的失败路径:按母鸡的说「没孵出来」、补蛋不算孵出来
  · 其余(补分析、删、向量、关怀、检查日志)撤回 + print。撤回之后库里还是改之前的样子,界面刷新照实显示
- ⚠️ **撤回之后,这次新插入的对象就废了**:属性全是 nil,读非可选属性(`id: UUID`)当场崩。
  `ChatRepository.createSession` / `append` 以前是「存完再读 `s.id` 拼返回值」,改成撤回之后**测试一跑就崩**(那个仓库 10-03 整个删了)。
  **以后写「存完返回值类型」的仓库方法,值要在 save 之前取**
- `CoreDataStack.saveContext()`(切后台)不再 `fatalError`,只是保底:正常情况下没东西可存

**库打不开**:
- `CoreDataStack` 记下 `loadError`、不崩;`SceneDelegate` 第一件事问 `isLoaded`,没打开就只挂 `StoreErrorViewController`(「日记本打不开了」),
  仓库、页面、补蛋一样都不建。组装挪进了 `assemble()`,**库打开之后才调、只调一次**
- **绝不删库重建**(网上常见的写法):删掉的是用户全部的日记。打不开的原因多半能修(清出空间、发新版修迁移),文件留着,修好了再开就都在
- 「再试一次」= 同一个 container 再 `loadPersistentStores` 一次(`StoreLoadTests` 验过能行),成功了走冷启动同一条路,再补跑一轮 `openFlow`
- 页面上「先别删掉 App」那句是有意的:用户最容易做的补救就是删了重装,那才是真把日记删了
- 出错信息那行:SQLite 的码在 userInfo 的 `NSSQLiteErrorDomain` 键下(**不在** `NSUnderlyingErrorKey`)。13 = 磁盘满、26 = 不是数据库

**验证**:
- `SaveFailureTests`(6 条,`FailingSaveContext` 让指定次数的 save 抛「磁盘满」)。**反向验过**:去掉 `rollback()`,6 条全挂
  (「坏的」被第二次保存捎带进库、蛋留在内存里冒充孵出来了、聊天会话多一个)
- `StoreLoadTests`:坏文件 → 报错不崩、文件逐字节不变 → 挪走坏文件 → 同一个 container 能再开
- 模拟器:把 `-UseTestStore` 的库换成随机字节 → 错误页、进程活着、文件 md5 不变 → 点「再试一次」显示「还是没打开」→
  App 开着把好库放回去 → 再点 → 进首页,32 篇 / 13 颗都在,紧接着有一次关怀检查(补跑的那轮)
- **没亲眼验**:写日记页「没存上」那个弹窗(模拟器上造不出存储满)。逻辑由 `SaveFailureTests` 前两条 + VM 那一行 `try` 撑着
- ⚠️ 模拟器截图会比页面更新早一拍:点完立刻截图看到的可能还是旧页面,别当成「点击被吞了」

### 正在做:主动关照 v2

按 [`docs/主动关照-v2.md`](docs/主动关照-v2.md) 第 0 节的十步走。**第 1–7、10 步已完成**,当前在**第 8 步**:

- ✅ 1–3 `DayEggService` 抽出、`SquareViewModel` 瘦身、补蛋挪到 App 激活
- ✅ 4 `DayEggStore.delete(for:)` + 孤儿蛋清理(09-18 才真正接上:之前方法写了,只有 `DebugSeeder` 在调)
- ✅ 5 数据层迁移:`CareMessage` 两态 + `retiredAt` + `referencedDates`;新增 `CareCheck`;删 `RuleCooldown`
- ✅ 6 删三条老规则与 `postSaved`,写 `CareGate` + 单测(9 条)
- ✅ 7 AI 决策层:`decideCare(window:recentlySaid:)` → `CareDecision`;退场判断也交给了 AI(见 §2.1)
- ✅ **8 卡片生命周期**(09-23 完):卡片分 `.speaking` / `.lingering` 两种形态,模拟器实测过。
  **产品边界层(Layer 3)决定不做** —— 见下方「砍掉的东西」。细节见「卡片两种形态」一节
- ✅ 9 可观测(09-23 完):`CareDebugViewController`(整个文件在 `#if DEBUG` 里)。
  **入口:Debug 构建下长按首页日期** —— 不加任何可见 UI。
  `SceneDelegate` 那段临时 print 已收掉(它只看得到最近一次,而要回答的问题都是跨多次的)。
  顶上那几个统计**不是装饰**,是去给「把换内容和重新开口拆开」那个候选方案取前提数据的 ——
  尤其「替换里引用全是旧日子 N/M」那一栏,占比决定那个方案值不值得做
- ✅ 10 eval:41 条 golden set + 文案抽查(禁词硬判、范围词/超长只报)。
  **当前基线(09-25,41 条 × 5 次,prompt 77 行,载荷 `.sortedKeys`):
  决策 precision 0.87 / recall 1.00(TP 20 / FP 3 / FN 0 / TN 18);
  文案 硬禁词 1 例 ❌(#25「今晚」)、范围词 2 例(#6「那几天 / 那阵子的自我怀疑」,引用 2 天,描述的是状态)**
  · 判错只剩「保持」那族三条:#30 4/5、#31 5/5、#37 5/5 —— 跟 09-23 一样,结构性的,不是噪声
  · 不稳定 7 条:#10(2/5)#12(1/5)#21(3/5)#25(4/5)#30 #32(1/5)#35(2/5)
  · **跟 09-23 比的变化别当成 `.sortedKeys` 的功劳**:翻过来的 #10(3/5→2/5)、#25(2/5→4/5)、#41(→5/5)
    全是早就标过的边界用例,各自的 n=10 A/B 本来就在五成上下。`.sortedKeys` 去掉的是一个噪声源,
    不是改了模型的判断;要证明它影响了某条,按老规矩对那条单独做 n=10 A/B
  · 固定之后模型看到的顺序是「最近对ta说过的话」在前、「近14天」在后(按 Unicode 排,**不是设计出来的**)。
    prompt 正文先讲时间线再讲说过的话,两者顺序相反 —— 想试「时间线在前」得改成手动控制顺序,是另一个实验
  · 09-25 这一跑结束时**测试进程崩了**(报告已经完整打印):`CareEvalTests` 当时没标 `@MainActor`,
    拆 AI 层之后 `CareDecider` 有存储属性、析构走 isolated deinit,撞上 §5 那个运行时 bug。已补 `@MainActor`
  **上一版基线(09-23,载荷键顺序随机):precision 0.82 / recall 0.90;硬禁词 0、范围词 1**
  ⚠️ **recall 0.90 不可信** —— 掉下去的 #25 #41 专项 n=10 跑都是判对的(6/10、7/10)。
  详见下方「文案规则:两条都做了 A/B」
  · 判错的**三跑全是同四条**:#10 #30 #31 #37 —— 稳定,不是噪声
  · #25 三跑分别 4/5、2/5、2/5,单独 A/B 又是 5/10、6/10 → **真边界,约五成**
  #25~#29 专测 `isNew`:两个漏洞(当天重孵 / 昨晚关怀今早补蛋)、防「见新就换」、防迟补旧蛋误标、
  以及 prompt 里「包括针对里那几天」和 isNew 打架时模型信谁(信 isNew,5/5)。
  判据本身另有 `PastCareTests` 7 条单测兜底 —— **eval 测模型会不会用,单测测判据算得对不对**。
  #37~#40 是**退场专项**(`stillShowing: false`)—— v2 里唯一没覆盖过的 `recentlySaid` 状态。
  按 `CareGate` 的推导,每次自然退场 + 冷却之后都会走一次,不是小众场景。
  **#10 #12 #25 #35 是真边界**,5 次采样下基本抛硬币(#25 单独跑 10 次是 5/10、6/10),
  改 prompt 时要盯着,但**别拿它们的翻转当证据**

#### eval 09-23 全量基线的诊断(改 prompt 前的存档点)

**四条失败全是 FP(不该说却说了),FN 是 0。** 而「该说」那 19 条全对、17 条 5/5。

> **模型的「该开口」判断满分且稳;所有问题都在「该闭嘴」那一侧。**
> 8 条不稳定里有 6 条也在这一侧(#10 #12 #30 #31 #35 #39)。

这正是已知坑第 2 条(「模型总想说点什么」)的量化版 —— **那份不说清单在 97 行的 prompt 里压不住了。**

失败分两族:

| 失败 | 病根 |
|---|---|
| #30 情绪标签变了、还是同一件事<br>#31 写得更具体、没有新角度<br>#37 退场后同一件事还在继续 | **「同一件事在继续 → 保持/不说」整族没落地**,三条全挂 |
| #10 才两天,看不出走向 | 证据门槛(独立问题) |

- **#30 #31 #37 三条并排跑过**:#30 #31 是「还挂着」、#37 是「已退场」,**全都 5/5 判反**。
  所以这不是退场状态特有的混淆,是这条规则整体被稀释了。**别再拿「退场状态弱」解释它。**
- **#1~#29 相对 09-17 漂了一点**:#10 从「0~2/5 来回」变成 3/5(多数决翻转),#25 #29 从稳定变成 4/5。
  中间隔着 prompt v4、v5 两次提交。
- **手工实测(4 次采样)另有一个 eval 照不到的问题**:关怀已退场时,模型有 **2/4** 概率
  以为它还挂着(`pattern` 里写「当前悬挂的关心」「保持原关心即可」「值得替换」)。
  原因是 prompt 里讲「关怀挂着时怎么判」的那三十行是**无条件文本**,
  对抗它的只有 payload 里 `最近对ta说过的话[].状态` 一个字段。
  **eval 只看 `shouldShow`,看不到它以为自己在哪个状态** —— #38 #40 答对了,但可能是用错误的框架答对的。

改 prompt 时的靶子因此很具体:**「该说」那一族一个字别动(它满分),要救的是「保持/不说」那一族。**
拆条件 prompt 能帮 #30 #31(它们在替换分支);救不了 #37(它在首次开口分支,靠的是不说清单里
「语义重复 → false」那一行,得写得更狠)。

#### prompt 精简实测:救得了「证据门槛」,救不了「保持」那族(09-23)

把 carePrompt 从 **98 行压到 71 行** —— **只合并重复表述、去空行,一条规则都不增删**
(核对方式:把老版按标点切成片段,逐个在新版里找;这么查出来一处真丢了 ——
「从积极转为明显低落」被我压进「明显加重」里盖不住,补了回去)。

| # | 标注 | 98 行 | 71 行 |
|---|---|---|---|
| #10 才两天,看不出走向 | 不说 | 8/10 | **4/10** |
| #30 标签变了、还是同一件事 | 不说 | 10/10 | 9/10 |
| #31 更具体、没新角度 | 不说 | 8/9 | 8/10 |
| #37 退场后同一件事继续 | 不说 | 9/10 | 10/10 |

**两条结论,一正一反:**

1. **正:精简确实能让被稀释的规则复活。** #10 从 ~0.8 降到 ~0.4 —— 「一两天的变化只是较弱
   证据」那条重新生效了。这是「89 行失效 / 68 行生效」那条经验的又一次复现。
   ⚠️ 但别说成「修好了」:全量 n=5 下 #10 仍判错(3/5)。真实概率约 0.4,**从稳定判错变成了边界**。
2. **反:「保持」那族不是稀释问题。** #30 #31 #37 在 **三种措辞、两种长度**的 prompt 下
   都是 9~10/10 判说。模型有个压不住的先验:**「这个人还在难受,说一句总比沉默好」**。
   **别再试图用 prompt 压它了** —— 再精简、再拆条件分支、再加规则,大概率都没用。

全量验证:41 条 × 5,precision / recall / 判错集合**和精简前完全一致**,
「该说」那 19 条一条没掉(#21 #29 反而从 3/5 变成 5/5)。所以精简是安全的,留下了。

##### 候选方案:把「换内容」和「重新开口」拆开(09-23 产品结论,**前提未验证**)

**先问对问题。** 「母鸡该多久说一次话」问错了 —— 它假设频率是个要调的参数。
真正的问题是:**「她开口」这个动作还有没有信息量?**

| 频率 | 用户读到的意思 |
|---|---|
| 每次打开都说 | 「她总会说点什么」→ 这是个函数,不是观察 |
| 偶尔说 | 「她今天说话了」→ **这是个事件** |
| 几乎不说 | 忘了有这回事 |

> **频率不是要控制的参数,是要保护的信号。**

所以今天测出的那个 AI 倾向(「人还在难受,说一句总比沉默好」)危险在于:
人大部分时候都**有点**不顺,顺着它走,「她开口」会贬值到零。

**❌ 否掉:纯频率限制(N 天最多换一次)。**
AI 总想换 + 本地总卡 N 天 = 实际表现是精确的「每 N 天一换」,**一个完美的定时器**,
比没有兜底更容易被识破。**用算术压语义,压出来的是规律,而规律本身暴露机制** ——
这是 v1 那类错误的变体。

**✅ 候选:拆开两件被压成一个动作的事。**
现在「替换」= 旧的退场 + 新的诞生 + 重新滑出。但它压着两种性质不同的情况:
1. 她有新的话要说(情况真变了)→ 该是事件,该滑出
2. 旧话还对,只是能说得更贴切 → 不该惊动人

**用户感知的频率只跟第 1 种有关。** 内容更新几次不重要,**演出**几次才重要。
两种形态(09-23 做的)正好铺好了路:

- 有新东西 → `.speaking` 滑出 = 她又开口了
- 只是措辞更贴切 → **静默更新内容、保持 `.lingering`** = 那句话还在,只是读起来更准了(保鲜,不是通知)

**判据已经有了,不用新发明:** 新关怀的 `referencedDates` 里有没有「旧话之后才出现的日子」
—— 就是 `PastCare.isNewEvidence`(有 7 条单测)。全是旧日子 = 它在复述 → 静默更新。

这套的好处是**不跟模型的先验硬扛,而是让它的先验不造成伤害**:
AI 保留全部语义判断权(它压不住就别压了),本地只决定「这次要不要演出」。

**⚠️ 前提没验证,别急着做。** 上面全建立在「AI 确实经常想换」上,而那 9~10/10 是在
**专门构造的边界用例**上测的;真实使用里平淡的一天可能压根不触发替换。
**为一个没观测过的现象改设计,是在猜。** 先做第 9 步 debug 页,跑几天真实数据看两个数:
· 替换实际多久发生一次
· 其中多少次「引用的全是旧日子」(= 本来就该静默的那些)
第二个数字很小 → 这套不值得做;占了一半以上 → 它是当下最划算的改动。

#### 文案抽查的阈值是调出来的,两头都撞过(09-23)

范围词那条检查(「这几天」「那几天」…)卡在**引用 ≤2 天**,这个数不是拍的:

| 版本 | 结果 |
|---|---|
| 只报 `days == 1` | 全量 **0 例**,假阴性 —— 模型引用 2 天(外婆+加班)却把单日的外婆说成「那几天」 |
| 全报,不预筛 | 110 句里 **19 例**,其中 11 例是 `引用4~5天`,那些场景真连着好几天,**噪声淹掉信号** |
| **≤2 天**(现在) | 「几天」口语上至少三天;引用一两天却说「几天」才可疑 |

> **`referencedDates` 数的是「这条关怀基于哪几天」,不是「它说的那件事跨几天」。**
> 后者是语义的,任何预筛都会漏 —— 所以这条只报不判,别再想着把误报「优化」掉。

#### 文案规则:两条都做了 A/B(09-23,**今天效应最大的两个改动**)

都是在 prompt 精简到 71 行之后加的 —— **97 行时同方向的改动改了没反应**(见下一节)。
**先腾空间,再加规则;反过来做是白费。**

| 规则 | 量的是什么 | 前 → 后 | Fisher p |
|---|---|---|---|
| **不给事件安时间跨度** | #41 里「X 那几天」这类说法的比例 | 50%(4/8) → 11.5%(3/26) | 0.037 |
| **不要停在那一天** | #41 里「既说旧事、也提之后那几天」的比例 | 19%(5/26) → **61%(11/18)** | 0.0096 |

第二条改的**不是「说不说外婆」**(那条测过:模型 17/20 认为该说,理由站得住 ——
住院不会因为日记里没再提就结束),改的是**说的时候要承认时间往前走了**:

> ❌「外婆的事还揪着心吧,咕咕。」(停在四天前那一天)
> ✅「外婆的事还压着,你还得照常上班加班,真是辛苦了」(落在现在)

##### 坑:指标没动时,先看原始样本,别直接信指标

第二条规则第一次统计跑出来是 **p = 1.0**,看着完全没用,差点就撤了。
去翻被判「没跟上」的原始句子才发现 ——

> 「外婆的事还悬着,**班**也一直没停」
> 「外婆住院那阵子心里揪着,**你还照常过日子**」

**这些明明跟上了,是我的关键词表里只有「上班/加班」,漏了「班」「照常」「过日子」。**
修好检测器、两边用同一把尺重算 → 19% → 61%。

**测量工具本身也会错,而它错的时候伪装成「改动无效」。**

##### 全量验证:指标掉了,但掉的是噪声

77 行全量跑:precision 0.87→0.82、recall 1.00→0.90,「该说」那族出现两条判错(#25 #41)——
按原定的停止条件该回退了。**但专项 n=10 跑出来两条都是判对的(6/10、7/10)**,
#41 合计后规则版本 25/30 = 83%。全量那次的 1/5、2/5 是运气差。

> **要不是先做了 n=10 专项,就会去回退两条有效的规则。**
> n=5 的全量跑对边界用例基本是抛硬币 —— 这条已经栽过两次了。

##### eval 现在可能因为禁词而**红**

文案抽查里硬禁词是 `XCTAssert`,出现即失败(规格第 10 节写的就是「禁词 0 例」)。
09-23 有一跑抓到 `#29「今晚」` —— **114 句里的 1 句,肉眼根本翻不出来**,下一跑又是 0 例。
所以跑全量偶尔会红,**先看是不是这一条,别以为是崩了**。

#### 文案里的**范围词**是个没堵的口子(09-23 实测)

prompt 里禁了**会过期的时间词**(「今天」「今晚」「刚刚」),但没禁**范围词**。
实测 `-SeedDiaries` 那份数据(外婆住院只出现在一天,之后是洗衣服、被组长点名),
模型反复说「外婆住院**那几天**」—— 真机截图、三次手跑、eval #41 的样本里都出现。

**范围词比时间词严重:时间词只是过期,范围词是把事实说错。**
一旦点名具体事件,就得同时把它的范围说对,而模型稳定地说错。
说「最近好像一直揪着心」就没这个问题 —— **形状没有范围,事件有**。

还有一半的样本只说那件旧事、不提之后新写的两天,用户会觉得「她没在跟上我」。
若之后那几天是空白,说四天前完全合理;正因为之后写了,跳过才刺眼。

⚠️ **这两条 eval 都测不到**(只看 `shouldShow`),只能靠抽查 #41 的样本。

#### 基线的噪声:两次全量跑之间的差,多半不是你改出来的(09-23 实测)

同一天、同一套用例跑了两次(中间只改了 prompt 里讲文案措辞的一句话):

| | precision | recall | 判错 |
|---|---|---|---|
| 改前 | 0.83 | 1.00 | #10 #30 #31 #37 |
| 改后 | 0.82 | 0.95 | #10 #25 #30 #31 #37 |

看起来是「改坏了,多出一条 FN」。**但那是假的。**

#25 改前 `●●●●○`(4/5)、改后 `●●○○○`(2/5),多数决翻转。单独把 #25 拎出来各跑 10 次:
**改后 5/10,回退 6/10 —— 差别在噪声里。** 那条改动对 #25 没有任何可测影响。

结论,两条都要记住:

1. **n=5 的全量跑之间做对比,看不出小改动。** 边界用例(#10 #12 #25 #35)在 5 次采样下
   基本是抛硬币,它们一翻,precision / recall 就动一两个点 —— 而那和你改了什么无关。
   **别拿两次全量跑的分差去论证一个 prompt 改动的好坏。**
2. **要判断某条用例是不是被影响了,对它单独做 n=10 的 A/B**(`EVAL_ONLY=25` + `EVAL_RUNS=10`,
   改前改后各一次)。20 次调用、几分钟,比再跑两轮全量(400 次)便宜得多,而且结论才站得住。

> 差点因此回退一个其实无害的改动 —— **这就是「看到分数变了先别信」的实例。**

顺带:eval 只看 `shouldShow`,**它根本测不到文案措辞类的改动**。那类改动的收益要靠人工抽查样本,
分数不动是正常的,不是「改了没用」。

#### 卡片两种形态(09-23 定,别推翻)

**「说」是一次性事件,「在」是持续状态 —— 动画属于「说」,不属于「在」。**

原来的 bug:`presentCareIfNeeded()` 挂在 `viewDidAppear` 上,只要 active 就 `slideIn()` ——
**从广场 tab 切回首页,母鸡就把同一句话重新说一遍**。一天来回切五次就是五次隆重登场。

- **首次**(`firstSeenAt == nil`):`.speaking` —— 滑出、尾巴跟着母鸡、完整浮起。**不设任何定时器,
  从头清晰到尾。** 中途自己淡掉会让人以为看漏了什么。
- **之后**:`.lingering` —— 缩到「巢是空的」那行右边,13pt、`ink(0.5)`、无尾巴、影子撤掉。
  什么时候消失仍由引擎说了算。
- **没选**「收成小气泡点一下展开」:收纳是为了解决「东西多」,而同时最多只有一条关怀 ——
  给一条信息做收纳,是为不存在的问题付交互成本。而且那个未读小点等于一个待办,
  跟「纯只读、不给负担」的产品选择相反。
- **没选**「10 秒后原地变浅」:试过,一次露面之内换形态会让人以为看漏了。

##### 这块的坑

- **`firstSeenAt` 必须落库,而且不能在 `slideIn()` 那一刻写** —— 那记的是「播过动画」。
  用户一开 App 就点鸟巢,卡片刚冒头就被 `dismissCare()` 收掉,那次要是算数,
  这条关怀从此只剩浅色形态,**等于白说**。现在是滑出后活满 3 秒才记,被打断就取消。
- **下面两条判断 09-25 抽成了纯函数 `CareCardAction.decide`**(在 HomeViewModel.swift),`CareCardActionTests` 一条坑一个用例。
  VC 的 `presentCareIfNeeded()` 只剩「按结果演」
- **不在眼前就不演**(decide 的第一条 `isVisible`)。
  从后台回来时用户可能停在广场页,`dataDidChange` 照样打到首页,卡片在没人看的首页上滑出、
  3 秒后落库。**这条守卫看着像多余的判断,删掉就会静默地吃掉关怀。**
- **卡片不再自己消失,所以要按 id 比、取不到要收掉**。
  原来的 `guard showingCareId == nil else { return }` 会让新关怀永远进不来;
  `activeCare()` 返回 nil 时直接 return 会让作废的话一直挂着。
- **`subLabel` 要顶到 `.required` 抗压**。lingering 挤在它右边,不顶的话 Auto Layout 会选择
  压缩左边那行 ——「巢是空的」当场变成「···」。**这个只有跑起来才撞得到。**
- 模拟器上浅色卡片旁边有时会看到一个很淡的「轻点鸟巢」幽灵。**那不是 view**
  (给 `hintLabel` 加红底验过,全项目只有这一处写这个字符串,幽灵不是红的),
  是模拟器合成器的残留像素,真机没有。

#### 删日记和关怀的关系(09-18 定,别推翻)

- **删日记 = 作废那天的蛋**(`DayEggService.invalidate`)。蛋是当天日记的摘要缓存,
  不作废的话被删的内容会一直通过蛋的 text 流进关怀窗口。删光 → 不欠,孤儿蛋没了;
  还剩 → 过去的天当场 `rehatch`(不等下次打开,否则 14 天外的永远停在「还在孵」),
  今天回到待孵、留给按母鸡。
- **今天的预取要记住「基于哪几篇」**(`todayTask.basis` = 日记 id 数组)。按母鸡按到一半松手,
  再去写一篇或删一篇,手上那份就过时了;拿它落库,蛋会漏掉新那篇,而且蛋比那篇晚 →
  `EggDebt` 判不欠 → 永远补不回来。`prefetchToday` 每次都比对,对不上就作废重发;
  写和删走同一套,`invalidate` 不用单独管预取。
  **没选「松手就清预取」**:那样正确性要靠 UI 记得在每个出口通知 Service,Service 自己兜不住。
- **已经说出口的关怀不动**。本地不因为「引用日期里删了日记」撤关怀 —— 删的可能只是
  一篇重复的,这是拿算术猜语义。最多挂 3 天兜底;删的日子早于关怀那天时 `isNew = false`,
  AI 也基本会保持。
- **闸门①不加「蛋的日期也得是新的」**。想省删除重孵那一次 AI 调用,但会挡掉所有迟到的蛋
  (早上补蛋断网失败、中午补上 → 日期早于上次检查那天 → 永远不触发)。
  ①问的是「AI 看过没」,`createdAt > lastCheckedAt` 正好就是这个;
  `isNew` 看日期是因为它问的是「内容发生在关怀之后吗」—— 问题不同,判据不同。
  **闸门不知道蛋「为什么新」是它的优点。**

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
- **「摇摆」和「稳定地不同意」是两回事**。3/5、2/5 是模型在边界上晃,多半是标注或 prompt 不清楚;
  5/5 稳定地判得和标注相反,说明模型有一个清楚的读法 —— 先认真看它的理由和输出,再决定谁错。
  #7/#8/#24 就是这样:09-09 在 3 次采样的噪声里定了「主题变了不替换」,加了 `isNew` 之后模型
  5/5 稳定判替换、新话具体不空洞,09-17 改回「主题变了、旧话接不住,也该换」。
- **改标注的同时要改 prompt 里对应的规则**。只改标注,prompt 就和标注互相矛盾 ——
  模型这次忽略了那句,下次调别的措辞时可能又开始遵守。
- **prompt 里规则越多,每条越弱**。实测:同一条「至少三个日期」的改动,在 89 行的 prompt 里
  失效,精简到 68 行后就生效了。加规则前先想能不能删。
- **eval 用 3 次采样噪声太大**。实测同样的输入两轮跑,24 条里 8 条结果不同、3 条多数决翻转。
  **至少 5 次**(`TEST_RUNNER_EVAL_RUNS=5`)。
- **打开 App 的流程能交错跑两遍**(09-24 修,模拟器复现过)。以前每次激活都 `Task { await onAppActive() }`,
  没有任何拦截。`@MainActor` 只保证同一时刻一段代码在跑,**每个 `await` 都是让出点**(actor 重入)。
  闸门锚点 `lastCheckedAt` 要等 AI 回来才写 → 第二轮也放行 → 两次 AI、两条关怀,第一条刚落库就被顶掉
  (debug 页多一次**假替换**,正好污染「拆开换内容和重新开口」要取的前提数据)。
  修法:`SceneDelegate.activation` 存着那个 Task,非 nil 就跳过。**防重入挂在整段流程上,不挂在 CareEngine 里** ——
  要保护的是「先补蛋再关怀」这个顺序;只在引擎里挡,第二轮的补蛋会因为那几天正在孵而秒返回、抢先跑关怀。
- **入口是 `sceneWillEnterForeground`,不是 `sceneDidBecomeActive`**(09-24 实测)。
  前台/后台 = 用户在不在这个 App 里;活跃/非活跃 = 此刻摸不摸得到。拉通知中心只走后者,
  以前每拉一次就跑一遍闸门、写一条 `CareCheck` 噪声。冷启动两个都会走,不用另外补。
  **换位置是少触发,防重入是不重叠,两个都要。**
- **「今天」不能在长寿对象里存成常量**。`SquareViewModel` 是组合根建的唯一实例,
  App 在后台挂一夜不被杀很常见。以前 `let today` 隔夜回来还停在昨天:真正的今天 `isFuture`、点不了。
  现在是 `syncToday()` 显式往前挪(不做成计算属性:一次 `rebuildWeeks()` 读它几十遍,跨零点时会前后不一)。
  触发点:进前台立刻广播一次(不等补蛋那轮跑完)+ 系统的 `significantTimeChangeNotification`(开着 App 跨零点)。
  零点那一下**只刷界面、不跑补蛋和关怀** —— 规格里那条流程只认「回到 App」。
  `DayEggService` / `CareGate` 每次现取 `Date()`,没有这个问题。

### 母鸡聊天的检索(RAG)

目标:聊天时按用户这句话检索相关的历史日记,让母鸡能像朋友一样「拿起来说」。
**跟主动关照是两套东西** —— 关怀看蛋的趋势,检索看日记的语义。

管线:提炼检索词 → 三路召回 → RRF 融合 → LLM 重排 → 生成(可以选择不说)。
全链路已接通；召回负责尽量别漏，重排和生成负责宁缺毋滥。

- ✅ `RecallRule` 纯函数:关键词/向量各取 Top 10 后做 RRF；情绪只给已召回候选加权，不能单独创造候选
- ✅ 端侧向量:`bge-small-zh-v1.5` → Core ML(45MB,fp32 输出)+ 手写 `BertTokenizer`。
  **懒加载 + 启动后后台预热,别挪回启动路径**(装完第一次加载要 2 秒,见「冷启动白屏」一节)
- ✅ eval:29 篇虚构语料 + 4 条标注,含生产配置在内的六种配置对比
- ✅ AI 提炼检索词:`extractRecallIntent` → 同义词扩展 + `shouldRecall` 否决权
- ✅ LLM 重排:RRF 候选 10 条 → 临时 ID 白名单精排 → 返回 0...3 条；网络/JSON 失败时返回空，不降级成硬塞 Top 3
- ✅ 接进 `ChatViewModel`:检索历史不重复当前消息；生成阶段仍有最后否决权

**重排 eval 基线(09-25,26 条 × 5 次,载荷 `.sortedKeys`,第一次记录)**:
计分 25 条(正例 13 / 空选 12)。must 命中 **100%**、exclude 违反 5/125、空选守住 55/60、
平均选中 0.94 条、**逐条全对 24/25**、摇摆 0 条。两条纯算术基线:全空 12/25、前三条 0/25。
唯一判错 **#5 泛化累**:标注空选,模型 5/5 选 110(「什么都不想干」,字面几乎一样的另一天)。
理由是「同样状态,属同一具体情境的延续」—— **5/5 稳定地不同意,先读理由再决定谁错**,别急着改 prompt。

实测(2026-09-11):baseline(关键词+情绪) r@10 **0.95**,仅向量 **0.90**,三路融合 **1.00**。
Apple `NLEmbedding` 中文句向量 r@5 只有 0.11,**比随机的 0.17 还差**,有 hub 现象
(一条日记跟所有 query 都近)。已放弃,别再试。

同义词扩展的价值:三路全开时看不出来(向量已经把 r@10 拉满),**关掉向量**才露出来 ——
手工词 0.95 → AI 扩展词 1.00,差别全在「组长/领导/上司」那条上(0.80 → 1.00)。

#### 检索这条线踩过的坑(别再踩)

- **重排看到哪段，回复就得看到哪段**(09-27 修)。以前重排截前 160 字、回复 `memoryContext` 只截前 60 字 ——
  依据落在第 61~160 字时，母鸡拿到一篇「被选中了但看不出为什么」的日记。现在两边都走 `RecallExcerpt.of`
  (压成一行再截 160;隐私政策不写这个数，改它不用动同意版本，但它决定一次聊天带出多少旧日记原文)。
  · **测试一直没抓到，因为检索语料最长 22 字**。`RecallExcerptTests` 专门用 `-SeedLife` 那篇 291 字的长日记
    (「小林」第 109 字、「火锅」第 140 字),换回旧写法 5 个断言全挂
  · 真 AI 对照(「今天又跟小林吃火锅吐槽工作了」,各 3 次,重排两边都选中了它):
    旧版 3/3 只接用户这句的「又」「火锅」,旧事没用上 = 检索白做;新版 3/3 用上了。
    但 1/3 把细节说走样(「笑完谁也没说出个解法」→「笑完谁都没说话」)—— 片段长了，复述走样的机会也多了,**盯着**
  · **重排的 `reason` 故意不传给回复模型**:是整句分析、带 `m3` 这类临时 id;给了最容易说出「我记得你上次…」
    (暴露判断依据),也让回复的最后否决权不再独立
  · 没解决的：超过 160 字的部分两边都看不到，但召回按全文算 → 可能因为后半段召回、重排看不到依据而不选。
    只漏不错；要做就按命中位置截，而不是永远截开头
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

- **SceneDelegate 还剩「导航」没拆**(09-25):写日记 / 聊天的工厂闭包、写完日记后刷新各页,还在组合根里。
  页面再多再抽导航对象。流程、DEBUG 配置、首页注入 09-25 已经处理
- **广播靠手动**:`broadcastDataChange` 的调用点都在 SceneDelegate / AppOpenFlow 里,每多一个写入方就得记得广播。
  两个页面够用;出现第三个页面或写入方时,改成仓库发变更通知、页面自己订阅
- `-CareStep2` / `-CareStep3` 两个旧别名(现在叫 `-CareTurn` / `-CareFlat`),可以收掉
- **`ChatSession` / `ChatMessage` 实体**:代码不用了(聊天不存库),下次加模型版本时连同实体类文件一起删(见「聊天不存库」)
- `SceneDelegate` 里包着 `RootTabBarController` 的那层 `UINavigationController` 是摆设 ——
  全项目没有一处 `pushViewController`,compose / chat 都是 present。可以去掉

### 调试关怀系统的固定套路

1. Scheme 勾 `-UseTestStore`(Edit Scheme → Run → Arguments),否则 `DebugSeeder` 拒绝播种。
   **所有启动参数的解析和说明都在 `Slime/Debug/LaunchOptions.swift`**(09-25 收拢),单测在 `LaunchOptionsTests`
2. 跑 App(控制台那段 `🔍 关怀检查` 的 print 已经收掉了,看第 3 步的 debug 页)
3. **长按首页日期** → 关怀 debug 页:统计 + 关怀历史 + 检查日志,不用退出 App。
   要看原始行(或者页面本身有问题)时再退出 App → `bash check.sh` 查库
   (**代码以为干了什么,和库里真发生了什么,是两回事**)
4. 多幕场景:不加参数是第一幕(清库+播种);`-CareStep2` 保留关怀只补一颗转折的蛋;
   `-CareStep3` 补一颗平淡的蛋
5. 跑 eval:`TEST_RUNNER_RUN_EVAL=1 TEST_RUNNER_EVAL_RUNS=5 xcodebuild test-without-building
   ... -only-testing:SlimeTests/CareEvalTests -resultBundlePath X.xcresult`,
   然后 `xcrun xcresulttool export attachments --path X.xcresult --output-path DIR` 取报告
   (命令行跑测试时 `print` 会丢,所以报告走 `XCTAttachment`)。
   eval 走线上中转 + 开发者通行证(仓库根目录 `Secrets.plist` 的 `RelayDevToken`,见 `SlimeTests/EvalClient.swift`)
6. 报告末尾有一节**文案抽查** —— 和 precision / recall 是两回事:那两个量「说不说」,
   这一节量「说了什么」(规格第 10 节的「文案铁律:禁词 0 例」就是它)。分两档:
   · **硬禁词**(prompt 里逐字点名的:「连续」「检测」「记录显示」「今天」「刚刚」…)
     出现即 `XCTAssert` 失败 —— 算术,没有判断余地
   · **可疑项**(范围词、超 32 汉字)只列出来给人看 —— 需要上下文才能定
   ⚠️ **范围词不要用「只引用了一天」去预筛**,实测是假阴性:`referencedDates` 数的是
   「这条关怀基于哪几天」,不是「它说的那件事跨几天」。模型会引用 2 天却仍然把
   单日的外婆说成「那几天」。**这个区别是语义的,预筛注定漏** —— 所以一律报出来、
   带上引用天数、`⚠️` 标记只引用了一天的那些,判断交给人
7. **只跑几条**:加 `TEST_RUNNER_EVAL_ONLY=37,38,39,40`。全量 41 条 × 5 次 = 205 次调用、十来分钟,
   调 prompt 时先拿一小撮快速对比。
   ⚠️ **子集分数不能和全量基线比**,只能和同一子集的上一次比

### 关键待确认项

- **上架地区:只上海外(不含中国大陆)**(09-26 定)。所以中转用 Cloudflare Workers;
  要上大陆得换国内云 + ICP 备案域名,还有 App 备案、生成式 AI 备案/登记
- **隐私同意 + 隐私政策**:日记经 Cloudflare 发给 DeepSeek。审核指南要求把个人数据交给第三方 AI 前
  明确告知并取得同意(以最新版指南为准)。**同意页(切片 18)、隐私政策页 + 设置页链接(切片 19)已做**;
  隐私政策页、支持页 09-28 已部署;还差:App Store Connect 里填两个网址 + 隐私标签(跟 `PrivacyInfo.xcprivacy` 一致)
- **开发者账号 09-29 开通**(个人,团队名 Shiying Chen,Team ID 还是 `54ZWCBP5FX` —— 原来的 Personal Team 原地升级)。
  **Bundle ID 定为 `com.shiying.muji`**(原 `com.shiying.Slime`),第一次上传后不能再改。
  模拟器上等于一个新 App:旧 ID 下的测试库、同意状态都还在旧的那个里,桌面会有两个「母鸡日记」,旧的可以删
- 限流做实(Durable Objects 强一致计数 或 App Attest)—— 等上线后真看到异常流量再做,见「后端中转」
- **余额用完 / key 失效时没有提醒**:中转只在 `wrangler tail` 里记 `upstream_401` / `upstream_402`,没人通知 ——
  所有用户的 AI 一起停,要等用户来说才知道。10-03 做过一版(cron 每小时查余额 + Bark 推送)又撤了,**先不做**

---

## 7. 范围红线(本期不做,别主动加)

- 登录 / 账号体系
- 他人回复 / 社区功能
- 帖子久无回应时的 AI 回应(依赖"他人回复",与其同期)
- 挑战 / 奖励 / 游戏化
- 多用户、数据同步、内容审核

如果我要求加这些,提醒我一句它在本期范围外,再按我意愿处理。
