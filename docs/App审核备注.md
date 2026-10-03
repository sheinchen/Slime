# App 审核备注

App Store Connect → 版本页 →「App 审核信息」→「备注」。**贴英文那段**(审核员不一定看得懂中文;上限 4000 字符)。
中文对照只给自己看,确认每一句都跟 App 实际行为一致。

> ⚠️ 改了下面任何一处交互(按钮名字、入口位置、关怀出现的条件、新手示范能不能跳过),回来改这份。
> 按钮的中文原文要跟 App 里**一字不差** —— 审核员是照着字形在屏幕上找的。

「需要登录」**不勾**。附件里放一段关怀卡片的录屏(怎么录见文末)。

---

## English(贴这段)

```
Thank you for reviewing Hen Diary (母鸡日记).

ABOUT THE APP
Hen Diary is a journaling app. Users write short diary entries during the day, and each day is summarized into one "egg" whose look reflects that day's mood. An AI hen character replies to entries, chats with the user, and occasionally checks in on them. The interface is in Simplified Chinese only, so button names below are given in Chinese with a translation.

NO LOGIN
There are no accounts and no demo account is needed. All diary data is stored locally on the device.

FIRST LAUNCH
1. AI consent page "让母鸡读你的日记" (Let the hen read your diary). It explains what is sent to the AI and to whom. Tap the orange button "同意并开始" (Agree and start). The AI features are the core of the app, so it cannot be used without agreeing. No diary content or other user data is sent to the AI before the user agrees; this is enforced in the app's network layer. Consent can be withdrawn at any time in Settings.
2. A short guided tutorial follows. It uses sample data kept in memory only (nothing is saved) and can be skipped with "跳过示范" (Skip tutorial).

MAIN FEATURES
- Write an entry: on the home screen, tap the nest on the island, type, then tap "收 好" (Save). The hen replies with one short line.
- Hatch today's egg: tap the calendar icon in the bottom bar, then press and hold the hen at the nest.
- Browse past days: on the calendar page, swipe the week strip left or right; pull it down to open the month calendar.
- Delete an entry: on the calendar page, long-press a diary card, then tap the × on its corner.
- Chat with the hen: tap the round speech-bubble button at the bottom right.
- Settings: the gear icon at the top right of the home screen. "撤回 AI 授权" (Withdraw AI consent) returns the app to the consent page. "隐私政策" (Privacy Policy) opens the policy in the app.

CHECK-INS
The hen occasionally checks in with a short message on the home screen. It only appears after several days of use, so it won't show up during review. The attached screen recording shows it with sample data.

AI SERVICE
AI requests go from the app to the developer's own relay server (a Cloudflare Worker), which forwards them to the DeepSeek API. The relay does not store any content, and the app contains no API keys. The relay will stay online throughout the review. Without a network connection, entries are still saved; the hen simply replies with a short built-in line instead.

USER SAFETY
The hen is not a therapist, and the app makes no medical claims. If an entry or a chat message expresses hopelessness or thoughts of self-harm, the hen drops its playful tone, responds sincerely, and encourages the user to reach out to someone they trust or to professional help. It is instructed never to make up phone numbers. The support page lists crisis resources (findahelpline.com).

PRIVACY
Privacy policy: https://slime-relay.hen-diary-2026.workers.dev/privacy
Support: https://slime-relay.hen-diary-2026.workers.dev/support
No ads, no tracking, no third-party analytics.
```

---

## 中文对照(不贴,自己核对用)

**关于这个 App**:日记 App。用户一天里随手写几篇短日记,每天收成一颗「蛋」,蛋的样子跟这一天的心情有关。一只 AI 母鸡会回复日记、陪用户聊天、偶尔主动关心。界面只有简体中文,所以下面的按钮都写了中文原文和英文意思。

**不用登录**:没有账号,不需要演示账号。日记都存在设备本地。

**第一次打开**
1. AI 同意页「让母鸡读你的日记」,讲清楚发什么、发给谁。点橙色按钮「同意并开始」。AI 是这个 App 的核心,不同意用不了。同意之前不会有任何日记或用户数据发给 AI(网络层强制的)。设置里随时可以撤回。
2. 接着是一段新手示范,用的是只在内存里的示例数据(不会存下来),可以点「跳过示范」跳过。

**主要功能**
- 写日记:首页点岛上的鸟巢,写完点「收 好」,母鸡回一句。
- 孵今天的蛋:点底部的日历图标,在鸟巢那儿按住母鸡。
- 看过去的日子:日历页左右滑周条,往下拉展开月历。
- 删日记:日历页长按日记卡片,点角上的 ×。
- 和母鸡聊天:点右下角的圆形气泡。
- 设置:首页右上角齿轮。「撤回 AI 授权」回到同意页;「隐私政策」在 App 内打开。

**主动关心**:母鸡偶尔会在首页说一句关心的话。用了几天之后才会出现,审核时看不到。附件录屏用示例数据演示。

**AI 服务**:App → 开发者自己的中转(Cloudflare Worker)→ DeepSeek API。中转不存内容,App 里没有密钥。审核期间中转一直在线。没网时日记照样存,母鸡回一句内置的话。

**安全**:母鸡不是心理咨询师,App 不做任何医疗宣称。日记或聊天里出现绝望、自伤念头时,母鸡收起玩闹的语气,认真回应,鼓励用户联系信任的人或专业帮助;规定不许编电话号码。支持页列了求助资源(findahelpline.com)。

**隐私**:隐私政策、支持页两个网址;没有广告、不追踪、没有第三方统计。

---

## 每一句的出处(改代码时对照)

| 备注里的说法 | 依据 |
|---|---|
| 同意页标题、「同意并开始」 | `AIConsentViewController` |
| 同意前什么都不发 | `AIClient.makeRequest` 第一行的闸 + `AIClientConsentGateTests` |
| 示范用内存数据、可跳过、按钮叫「跳过示范」 | `TutorialAssembly`、`TutorialOverlay` |
| 孵蛋在日历页按住母鸡 | `NestStageView.henPressed`、示范锚点 `.squareHen` |
| 长按卡片 → 点 × 删除 | `DiaryCardView.deleteBadge` |
| 「撤回 AI 授权」「隐私政策」 | `SettingsViewController` |
| 聊天只能从右下角的圆进;首页点母鸡只缩一下 | `RootTabBarController.onAccessoryTap`、`IslandView.islandTapped`(10-02 去掉了点母鸡进聊天) |
| 「同意前不发**用户数据**」而不是「什么都不发」 | 同意页上 `NetworkAccessPrompt` 会发一个 `HEAD /privacy`(触发国行的「使用数据」弹窗),不带任何用户内容 |
| 关怀用了几天之后才出现(实际是 14 天内至少 3 天有蛋,备注里不写数) | `CareGateRule.windowDays` / `minDaysWithEgg` |
| 中转不存内容、App 里没有密钥 | `relay/src/index.ts`、§6「后端中转」 |
| 没网照样存 | 切片 15「先存后分析」 |
| 安全回应、不编号码 | `HenPersona` / `ChatPrompt` / `CareDecider` 的安全底线 |

## 关怀录屏怎么录

审核员看不到关怀,所以要附一段录屏。用 Debug 版 + 测试库 + 示例数据录,备注里已经写了「用示例数据演示」,不算误导。
**10-02 录过一版**:`~/Desktop/母鸡日记-关怀录屏.mp4`(12 秒、884×1920、约 21 MB)。改了首页或关怀卡片的样子要重录。

按这个顺序(10-02 实际就是这么录的):

1. 新建一台临时的 iPhone 17 Pro Max 模拟器,状态栏固定成 9:41 满电:
   `xcrun simctl status_bar <udid> override --time "9:41" --batteryState charged --batteryLevel 100 --wifiBars 3`
2. **第一遍不录**:带 `-UseTestStore` 启动 → 点「同意并开始」→ 点「跳过示范」→ 关掉 App。
   这样第二遍直接进首页,录屏里没有同意页和示范
3. **第二遍开录**:`xcrun simctl io <udid> recordVideo --codec=h264 --force care.mp4`(后台跑),
   再带 `-UseTestStore -SeedLife` 启动。`-SeedLife` 会清测试库、播「最近一周加班、外婆住院」那份示例数据(过去每天都带蛋),
   一开 App 就调一次真 AI 决定关怀,**几秒内卡片滑出来**。AI 有否决权,万一这次没说话,再启动一次(会重新播种、重新评估)
4. 卡片出来后再等几秒,`pkill -INT -f recordVideo` 停止
5. 原始文件很大(42 秒 128 MB),用系统自带的 `avconvert` 剪掉开头的桌面、压一下:
   `avconvert --source care.mp4 --output care_small.mp4 --preset Preset1920x1080 --start <App 启动那一秒> --duration 12`
   (开头那几秒是桌面,会露出还没做的空白图标,一定要剪掉)
