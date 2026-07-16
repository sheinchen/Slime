# 史莱姆树洞 · 开发进度日志(Progress Log)

> 本文件记录项目从零到完成的开发进度。每完成一部分功能,在对应位置更新状态与说明。
> 关联文档:《史莱姆树洞 · 产品需求文档(PRD)》《史莱姆树洞 · 项目执行文档》
> 定位:一个有主动关怀能力的 AI 情绪陪伴系统,以史莱姆世界为载体(iOS 纯 UIKit + Core Data)。

**状态图例**:⬜ 未开始 · 🟨 进行中 · ✅ 已完成 · ⏸️ 暂缓 · ❌ 本期不做(裁剪)

---

## 一、项目快照

| 项 | 内容 |
|---|---|
| 当前阶段 | 阶段一 · 骨架 + 架构地基 |
| 整体进度 | 切片 1 最小闭环已跑通(输入→存→展示) |
| 最近更新 | 2026-07-06 |
| 技术栈 | UIKit(现代写法)+ Core Data + MVVM + Repository + SnapKit |
| 后端 | 待定(AI 中转 / 定时任务) |

**技术决策(已锁定)**
- 框架:全 UIKit,不用 SwiftUI
- 存储:Core Data,不用 SwiftData
- 架构:MVVM + Repository,逻辑层与 View 分离、可测试
- 列表:UICollectionView + Compositional Layout + Diffable Data Source
- 布局:SnapKit
- 形态:本地为主 + 轻后端

**待确认清单**(阻塞项,需尽早定)
- ⬜ AI 服务选型(情绪分析 / 摘要)
- ⬜ 后端选型(藏 key、定时任务、种子内容)
- ⬜ 真机 / 开发者账号($99/年,后台任务与通知需真机)
- ⬜ 通知实现方式(本地通知 vs 远程推送)
- ⬜ 隐私处理(本地是否加密、上传 AI 前是否脱敏)
- ⬜ 情绪粒度(四类枚举锁死:开心 / 平静 / 难过 / 生气)

---

## 二、里程碑总览

| 阶段 | 周期 | 目标 | 状态 |
|---|---|---|---|
| M1 骨架 | 约 3-4 周 | 架构干净、能记录能展示的本地 App | 🟨 进行中 |
| M2 AI 系统 | 约 4-5 周 | 会主动关心你的 AI 史莱姆树洞(可演示) | ⬜ 未开始 |
| M3 打磨 | 约 3-4 周 | 流畅、拟人、可扛系统底层追问的完成品 | ⬜ 未开始 |

---

## 三、阶段一:骨架 + 架构地基(M1)

> 目标:打通"写一句话 → 生成一只史莱姆 → 出现在广场"最小闭环。一行 AI 不碰,史莱姆先用纯色圆角矩形代替。

### 3.1 工程与基础设施
- ✅ 新建 Xcode 工程,配好 Git(已有初始 commit)
- ✅ 移除 Storyboard,改为代码驱动的 SceneDelegate 启动(window + UINavigationController)
- ✅ 引入 SnapKit(SPM,6.0)
- 🟨 工程分层目录:文件已按 View / ViewController / ViewModel / Repository / Model 职责拆分,物理分组待整理(Post 子类文件暂在根目录)

### 3.2 数据层(Core Data)
- 🟨 设计数据模型:Post(id/content/createdAt,均非可选)已建;Slime Entity 暂未建(切片 1 用占位方块)
- ⬜ 定义情绪枚举(开心 / 平静 / 难过 / 生气)——留待接 AI 的切片
- ✅ 搭建 Core Data 栈(CoreDataStack 单例,NSPersistentContainer / viewContext,从 AppDelegate 抽出)
- ✅ Repository 封装:协议 PostRepository + CoreDataPostRepository 实现(create / fetchAll / delete(id:),init 注入 context;delete 用 NSPredicate 按 id 查后 context.delete)
- ✅ 数据持久化验证(冒烟测试 + 重启后仍在)

### 3.3 记录碎碎念(P0)
- ✅ 生成页 ComposeViewController:文本输入界面(UITextView + 占位,无强制字数 / 标题)
- ✅ 提交后经 ComposeViewModel → Repository 写入 Core Data
- ✅ ViewModel 承接输入与保存逻辑(去空白、空不存;不 import UIKit)

### 3.4 史莱姆广场雏形(P0)
- ✅ UICollectionView + Compositional Layout + Diffable Data Source 展示(CellRegistration,SlimeItem 值类型驱动)
- ✅ 史莱姆用纯色圆角矩形占位(SlimeCell,按 id 稳定取情绪色板;暂不接 AI、暂不做动效)
- ✅ 点击史莱姆 → 查看原帖内容(详情页 PostDetailVC + PostDetailVM;didSelect → itemIdentifier 取值 → push)
- 🟨 广场与生成页的基本转场(已有 push 导航,"走进广场"动画留后)

**里程碑验收**:全新安装后无需登录,输入文字 → 保存 → 广场显示 → 点击回看,数据流通畅。

---

## 四、阶段二:AI 主动系统(M2)

> 核心亮点。情绪打标签、规则引擎、Agent 决策、聊天、孵化揭晓。

### 4.1 AI 情绪分析 + 摘要(P0)
- 🟨 结构化输出(JSON):切片 6 先做 **emotion + reply** 两字段;摘要 / 是否含心愿 / 心愿时间 / 话题分类留后
- ✅ async/await 后台调用,不阻塞 UI(ComposeVM @MainActor;网络在 URLSession 后台,回主线程写库)
- ✅ 错误处理:改为 **失败即抛错 + 用户重试**(不伪造情绪、不存帖子;VM `async throws`,VC `do/catch` 弹提示、保留原文重试)
- ✅ 情绪标签持久化到 Post(切片 5 已加 emotion;切片 6 加 reply)
- 服务选型:**DeepSeek(OpenAI 兼容)**;base URL / 模型名做配置项,key 存 gitignore 的 Secrets.plist

### 4.2 生成史莱姆 · 孵化揭晓(P0)
- ✅ 乐观 UI:先放灰色未定形占位史莱姆(切片 5:setUndefined(true) 灰身体+藏五官)
- ✅ 揭晓颜色 + 五官淡入 + wobble 动画(切片 6 起用 AI 真实情绪;失败保证最短孵化时长后再报错)
- 🟨 样貌多维度:颜色(情绪)已做;表情细分 / 大小(长度/重要度)待后
- ⬜ 揭晓动画短(<1s)、可跳过;高频记录降级为轻量弹出(留后)
- 🟨 新史莱姆"走进广场"转场:已用标准 push 转场;共享元素"走进"动画留后

### 4.3 史莱姆广场 · 动态化(P0)
- 🟨 情绪驱动动效(开心蹦跳 / 难过扁塌挪动等)——已有通用动效骨架(呼吸+Q弹),按情绪区分留待接 AI
- ✅ squash & stretch(切片 4:呼吸 CASpringAnimation + 点击 Q 弹 CAKeyframeAnimation transform scale)
- ⬜ 四维度区分 + 日期标签兜底(目前仅日期;颜色/表情/大小待情绪驱动)

### 4.4 主动式 Agent 系统(P1 · 架构核心)
- ⬜ 统一管道:Event → Rule → Trigger → Agent 决策 → Action
- ⬜ Rule:连续 N 篇消极 → 主动关心
- ⬜ 频率控制(如同周不重复)
- ⬜ Agent 决定语气与内容

### 4.5 AI 主动关心 + 聊天模式(P1)
- ⬜ 触发后 AI 史莱姆柔和询问"要不要聊聊"
- ⬜ 进入聊天模式对话
- ⬜ AI 始终以史莱姆身份出现(透明,不假装真人)

### 4.6 心愿 / 时间点提醒(P1)
- ⬜ 从结构化输出识别心愿 / 时间点
- ⬜ 到期由 AI 史莱姆主动提起

### 4.7 帖子久无回应的 AI 回应(P1)
- ⬜ 超时无回应 → AI 拟人回应(身份透明)

**里程碑验收**:满足触发条件可靠触达、频率受控、聊天连贯温暖,可录屏演示。

---

## 五、阶段三:系统底层 + 打磨(M3)

- ⬜ BGTaskScheduler 后台任务(App 未打开也能提醒)
- ⬜ actor 保证多规则并发线程安全
- ⬜ 广场性能:UIView 掉帧拐点评估,必要时迁移 SpriteKit
- ⬜ 列表 / 广场内存优化
- ⬜ 拟人动效细节打磨(真机调手感)
- ⬜ 单元测试(逻辑层)
- ⬜ 隐私与本地数据安全策略落地

**里程碑验收**:流畅、拟人,能扛住系统底层与架构的连续追问。

---

## 六、本期裁剪(Out of Scope)

- ❌ 登录 / 账号体系(与"他人回复"同期引入)
- ❌ 回复他人日记 / 社区功能
- ❌ 挑战与奖励 / 游戏化(史莱姆进化 / 喂养)
- ❌ 多设备数据同步

---

## 七、开发日志(时间倒序)

> 每完成一个切片,在此追加一条:日期 · 做了什么 · 遇到的坑 / AI 协作记录(面试素材)。

### 2026-07-16(切片 6)
- **切片 6:接入 AI 情绪分析(DeepSeek)+ 软萌回复**。随机情绪换成真实分析。
  - ① AIService 层:`protocol AIService { func analyze(content:) async throws -> AIAnalysis }` + `DeepSeekAIService`(OpenAI 兼容 /chat/completions,`response_format: json_object`,两层 JSON 解析:外层 OpenAI 壳 → message.content 内层 {emotion,reply})。prompt = 软萌史莱姆性格 + 6 情绪 few-shot 锁风格 + 安全底线 + 只回 JSON。`AIConfig`(baseURL/model 配置项)、key 从 gitignore 的 `Secrets.plist` 读。范围:只做 emotion+reply,摘要/心愿/话题留后。
  - ② Core Data:Post 加 `reply`(String?,可选 → 轻量迁移无需默认值);Repository.create 带上 reply。
  - ③ 接进揭晓:`ComposeVM.generate(content:) async throws -> SlimeItem`(@MainActor;调 AI → 存库 → 返回);SlimeView 的 hatch 拆成 `beginHatching()`(未定形+凝结+灰待机,盖住网络延迟)和 `reveal(to:completion:)`(拿到真实情绪再揭晓);VC 用 `Task` + `do/catch`。
  - 错误处理(用户要求最终形态):失败不伪造、不存帖子,`async throws` 往上抛,VC 弹"分析失败"+保留原文重试;失败路径加"最短孵化时长"(no-net 秒失败也先让灰史莱姆露脸再报错)。
- 新概念:async/await + async throws(try await 不 catch 即上抛)、@MainActor、URLSession.data(for:)、Codable 编解码两层 JSON、Task / Task.sleep、Core Data 轻量迁移(可选字段)、密钥 gitignore 隔离。
- 待确认项更新:AI 服务选型已定(DeepSeek)。

### 2026-07-09(切片 5)
- **切片 5:生成页 · 孵化揭晓 + 走进广场**。三步各自 commit:
  - ① 情绪贯通数据层:Post 加 `emotion`(String,默认 calm → 自动轻量迁移,老数据不丢);`SlimeEmotion` 改 String 原始值 + `random()`;`SlimeItem` / `Repository.create(content:emotion:)` / `SquareVM.map` 全带情绪;`SlimeView.bodyColor(for:)` 情绪→颜色;广场按存下来的情绪上色。
  - ② `SlimeView.hatch(completion:)`:未定形(灰+藏五官+缩小)→ 凝结(CASpringAnimation 放大)→ 揭晓(fillColor 变色 + 五官 opacity 淡入 + CAKeyframeAnimation 抖),用 CATransaction completionBlock 串接三段,最后回调上层。
  - ③ `ComposeVM.generate(content:)→SlimeItem?`(校验+随机情绪+存库+返回展示数据);`ComposeViewController` 输入/孵化两模式,点"生成"→ enterHatchingMode → slimeView.hatch → 揭晓完延迟 push 广场;viewWillAppear 回输入模式。
- 关键设计:情绪必须存库,"走进广场"的才是同一只(揭晓色=广场色);也为接 AI 铺好路(只需把随机换成分析)。
- 新概念:Core Data 轻量迁移(加属性+默认值)、fillColor/opacity 可动画、CATransaction completionBlock 串接动画、乐观 UI。
- 遗留小项:ComposeVM 里旧的 `save` 已无人调用(可择机删);情绪仍随机,待 AI 切片替换。

### 2026-07-08(切片 4)
- **切片 4:纯色方块 → 可复用 SlimeView 组件(纯代码绘制 + 原生动效)**。三步各自 commit:
  - ① `UIBezierPath` 画粗糙果冻 blob(身体=四段三次贝塞尔,+两点眼+弧线嘴);坐标写在 100×100 参考系,用 `CGAffineTransform` 缩放适配任意尺寸;画法抽成 `SlimeShapeProviding` 协议 + `BlobSlimeShape` 实现,与 SlimeView 结构解耦。
  - ② `CASpringAnimation` 弹簧呼吸待机(autoreverse + 无限循环;`didMoveToWindow` 上屏/离屏自动启停省性能;beginTime 错相位防同步)。
  - ③ 点击 `CAKeyframeAnimation` squash&stretch Q 弹(压扁→过冲→回抖),`CATransaction` completionBlock 结束后恢复呼吸;广场先弹 0.18s 再 push 详情。
- 预留接口(本切片不实现差异):`SlimeEmotion`(开心/平静/难过/生气)、`SlimeSpecialState`(彩虹)、`perform(_:SlimeAction)` 一次性动作。SlimeView 不感知外部数据,只按情绪/状态/指令表现。
- 新概念:贝塞尔曲线(锚点+控制点)、CAShapeLayer(可动画 path)、CASpringAnimation(mass/stiffness/damping,欠阻尼=回弹)、CAKeyframeAnimation(values+keyTimes)、CATransaction、didMoveToWindow、CATransform3DMakeScale。
- 技术路线锁定:纯代码路径绘制(为以后形状实时变形),不用图片/SVG/Lottie。

### 2026-07-07(切片 3)
- **切片 3:删除史莱姆(补全 CRUD 的 D)**。两个入口都通同一条 `VM → Repository.delete(id:) → context.delete + save`:
  - 广场:长按方块 → `UIContextMenuConfiguration` 菜单 → 删除 → `SquareViewModel.delete` 删库并同步 items → applySnapshot 播 diffable 移除动画。
  - 详情页:右上角垃圾桶 → `UIAlertController` 确认框 → `PostDetailViewModel.delete()` 删库 → pop 返回。
- 架构点:详情页删完不写回调,靠广场 `viewWillAppear` 重读自动同步;若广场非每次重读才需 delegate/闭包通知——这个取舍是面试料。
- 新概念:NSPredicate(按 id 过滤)、context.delete、UIContextMenuConfiguration、UIAlertController、闭包 [weak self] 防循环引用。

### 2026-07-07
- **切片 2:点击史莱姆 → 详情页**。广场 `didSelectItemAt` → `dataSource.itemIdentifier(for:)` 安全取出 SlimeItem → 注入 `PostDetailViewModel` → push `PostDetailViewController`(只读展示正文+格式化日期,不重新查库)。
- 详情 VM 承担展示逻辑(日期格式化),VC 只 bind 现成字符串。
- 复用性验证(面试点):选中→取数据→push 详情 这套逻辑,以后广场换 SpriteKit 场景时不用改,只换"点击检测"入口。
- 工程整理:源码按 Models / Repositories / ViewModels / ViewControllers / Views 五层分组归位,Post 子类文件从根目录移入 Models。

### 2026-07-06
- **切片 1 最小闭环打通**:输入一句话 → 存 Core Data → 广场展示为纯色圆角方块,端到端跑通,重启数据仍在,一行 AI 未接。
- 分层落地:Post 实体(Codegen=Manual 手写子类)/ CoreDataStack(单例,从 AppDelegate 抽栈)/ PostRepository(协议+实现,注入 context)/ ComposeVM / SquareVM(不碰 UIKit,注入 Repository)/ SlimeItem(值类型 Hashable)/ Compose + Square VC / SlimeCell。
- 现代 UIKit:代码驱动启动去 Storyboard;广场用 Compositional Layout + Diffable Data Source + CellRegistration。
- 引入 SnapKit 6.0(SPM)。
- AI 协作记录(面试素材):数据模型 Optional 未取消导致模型与 Swift 非可选不一致的坑、误加 fetchedProperty、`context,save()` 拼写、`CoreDaraPostRepository` 拼写——都在 review 时逐一发现纠正;核心层(Core Data 栈 / Repository / ViewModel)坚持手敲,UI 与样板由 AI 生成。

### 2026-07-04
- 建立本 progress 日志,固化项目背景、里程碑与任务清单。项目处于初始化状态,尚无功能代码。
