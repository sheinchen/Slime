# CLAUDE.md — 史莱姆树洞 项目常驻背景

> Claude Code 每次启动会自动读这个文件。它是本项目的"常驻记忆":锁死的决策、带我的方式、当前进度都在这里。请全程遵守。详细背景见 `docs/` 下的《项目执行文档》和《PRD》。
>
> **我的工作分两条线**:这里是**执行线**(推进项目、写代码);我另有一个**教学对话**专门弄懂 iOS 概念。执行线负责往前做,遇到我不懂的概念,给够上手的解释即可,深挖我会拿到教学对话去问。

---

## 1. 项目一句话

一个有主动关怀能力的 AI 情绪陪伴 App:用户记录碎碎念,每篇诞生一只由情绪驱动样貌的史莱姆,一只 AI 史莱姆在合适时机主动关心用户。iOS 是呈现层。

---

## 2. 技术决策(已锁死,不要改变或建议替换方案)

- **UI**:全 UIKit(不用 SwiftUI)
- **列表/集合**:现代 UICollectionView —— Compositional Layout + Diffable Data Source(不要用老的 UITableView + cellForRowAt 写法)
- **布局**:SnapKit(不要手写大量 NSLayoutConstraint)
- **存储**:Core Data(第一版可先用 UserDefaults + Repository 过渡,但对外接口按 Repository 设计,便于无痛切换)
- **架构**:MVVM + Repository。View 只负责显示,业务逻辑在 ViewModel,数据读写全部走 Repository,逻辑层与 UI 分离、可测试
- **形态**:本地为主(当前纯单机,无登录、无账号、无网络账号概念),未来轻后端
- **UI 启动**:纯代码搭 UI(可去掉 Storyboard),不依赖 Interface Builder

---

## 3. 怎么带我(重要 —— 请严格按这个来)

**我的真实画像:**
- **Swift 语言本身我熟**:变量、函数、类、闭包、可选值这些语法不用解释。
- **但 iOS 框架层和工程工具我不熟**:UIViewController 生命周期、Core Data、Auto Layout、Git、Xcode 工程结构这些概念我**不懂**,需要你讲清楚。**不要假设我懂任何 iOS 框架或工程概念。**

**带我的方式:**
- **整块给代码,但配足够解释**。一次给一个完整文件,不要一行行带我敲、不要把简单的东西拆成小碎步(那样太慢)。但每给一段代码,要用中文说清:这个文件/这段在干嘛、涉及的 iOS 概念是什么、为什么这么写。
- **写代码时每一步讲清"在干嘛"**,尤其出现新的 iOS 框架概念(生命周期、Core Data、代理、闭包回调等)时,简短点明它是什么、起什么作用。
- **深入原理放到另一条线**:我另开了一个"教学对话"专门弄懂概念。所以在这条执行线里,你点到概念、给够上手需要的解释即可,**不用长篇展开原理**;我想深挖时会拿到教学对话去问。执行线保持往前推。
- **卡住时**:如果我说"这个概念我不懂",你简短解释一下够我继续就行,或提示我"这个建议到教学对话深聊",别在执行线停太久。

## 3.1 谁来写代码(重要)

- **核心代码 —— 只给我看 + 讲解,不要写入文件,我自己敲**:
  - Core Data(栈、数据模型、增删改查的核心逻辑)
  - 分层结构(Repository、ViewModel 的设计与职责划分)
  - 并发(async/await、@MainActor、actor)
  - 规则引擎(Event→Rule→Agent→Action)
  - 这几块是我要吃透、面试要讲的,必须亲手敲。你给代码 + 讲清原理,我自己写进文件。
- **其余代码 —— 可以直接生成写入文件**:
  - 常规 UI(ViewController 布局、cell、自定义 view)、样板(CRUD 模板、重复配置)、工程杂项
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
- 依赖:SnapKit 用 SPM 引入。
- 目录分层参考:`Models/`(Core Data 实体+领域模型)、`Repositories/`、`ViewModels/`、`ViewControllers/`、`Views/`(自定义 view / cell)、`Resources/`。

---

## 6. 当前进度(每条切片做完更新这里)

> 这一节是我的跨对话存档点。开新对话 / 重启 Claude Code 时,看这里就知道做到哪了。

- **已完成**:
  - **切片 1(最小闭环)✅**:输入一句话 → ComposeVM → PostRepository → Core Data → SquareVM → 广场(UICollectionView 现代写法)展示为纯色圆角方块。端到端跑通,重启数据还在,一行 AI 未接。
    - 数据层:`Post` 实体(id/content/createdAt,均非可选,Codegen=Manual 手写子类)、`CoreDataStack`(单例,栈从 AppDelegate 抽出)、`PostRepository`(协议 + `CoreDataPostRepository` 实现,init 注入 context)。
    - UI 层:代码驱动启动(SceneDelegate 建 window + UINavigationController,已去 Storyboard)、`ComposeViewController`(SnapKit)、`SquareViewController`(Compositional Layout + Diffable Data Source + CellRegistration)、`SlimeCell`。
    - 逻辑层:`ComposeViewModel` / `SquareViewModel`(不 import UIKit,依赖注入 Repository);`SlimeItem`(值类型 Hashable 展示模型,Post→SlimeItem 转换解耦)。
    - 依赖:SnapKit 6.0(SPM)。
  - **切片 2(点击详情)✅**:广场点方块 → `didSelectItemAt` → `dataSource.itemIdentifier(for:)` 取 SlimeItem → 注入 `PostDetailViewModel` → push `PostDetailViewController`(只读展示正文+日期)。源码已按五层目录(Models/Repositories/ViewModels/ViewControllers/Views)归位。
  - **切片 3(删除)✅**:补全 CRUD 的 D。`PostRepository.delete(id:)`(NSPredicate 按 id 查 + context.delete)。两个入口:广场长按 `UIContextMenuConfiguration` 菜单删除(diffable 动画移除)、详情页垃圾桶 + `UIAlertController` 确认后删并 pop。详情删完靠广场 `viewWillAppear` 重读自动同步,无回调。
- **正在做**:
  - (切片 3 已完,切片 4 待定)
- **下一步(待做)**:
  - 切片 4 候选:把占位方块换成真正的史莱姆 view / 空广场占位提示 / 接入 AI 情绪分析(需先定 AI 服务选型)。
- **关键待确认项**(来自 PRD,做到相关切片再定):
  - AI 服务选型、后端选型、真机/开发者账号、通知实现方式、隐私处理、情绪枚举锁定

---

## 7. 范围红线(本期不做,别主动加)

- 登录 / 账号体系(与"他人回复"同期,未来才做)
- 他人回复 / 社区功能
- 挑战 / 奖励 / 游戏化
- 多用户、数据同步、内容审核

如果我要求加这些,提醒我一句它在本期范围外,再按我意愿处理。
