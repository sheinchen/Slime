# relay —— 母鸡日记的 AI 中转

```
App ──(安装 ID)──▶ Cloudflare Worker ──(DeepSeek key)──▶ DeepSeek
    ◀──────────── 原样边收边转 ◀────────────────────
```

App 里一个密钥都没有。DeepSeek 的 key 只存在 Cloudflare 的加密 secret 里。
代码只有一个文件:[`src/index.ts`](src/index.ts),每一步为什么这么写都在注释里。

## 它做的四件事

| 步骤 | 做什么 | 为什么 |
|---|---|---|
| ① 认门 | 只接 `POST /chat/completions`,要有合法的 `X-Install-ID` | 别的一律 404 / 405 / 400 |
| ② 限流 | 每个安装 ID 30 次/分,每个 IP 60 次/分;带 `X-Dev-Token` 的跳过 | 减速带,不是墙(见下) |
| ③ 重建请求 | 只挑 `messages` / `response_format` / `temperature` / `stream`,模型和 `max_tokens` 由这里定 | 防止被当成免费的通用 DeepSeek |
| ④ 原样流回 | 把上游的字节流直接交出去,不攒;加 `Cache-Control: no-transform` | DeepSeek 拥堵时靠空行保活,攒着 App 会误判超时 |

**防滥用的真实边界:** 限流按 Cloudflare 机房各算各的,换 IP 就能绕开。
**真正封顶损失的是 DeepSeek 账户余额**(预付费,花完就停)——所以账户里只充小额,
余额低了再充。真要防「只有正版 App 能调」,得上 Apple App Attest(要真机 + 开发者账号)。

## 第一次部署

在 `relay/` 目录下,**自己在终端里一条条跑**(要登录你的 Cloudflare 账号):

```bash
npm install
```

```bash
npx wrangler login
```

```bash
npx wrangler deploy
```

第一次 deploy 会让你给账号起一个 workers.dev 子域。结束时打印的
`https://slime-relay.<子域>.workers.dev` 就是中转地址,填进
`Slime/Services/AI/AIConfig.swift` 的 `baseURL`。

然后把两个秘密交给 Cloudflare(从仓库根目录的 `Secrets.plist` 读,不经过屏幕和 shell 历史):

```bash
printf %s "$(plutil -extract DeepSeekAPIKey raw ../Secrets.plist)" | npx wrangler secret put DEEPSEEK_API_KEY
```

```bash
printf %s "$(plutil -extract RelayDevToken raw ../Secrets.plist)" | npx wrangler secret put DEV_TOKEN
```

`printf %s "$(…)"` 是为了去掉末尾的换行 —— 带着换行存进去,key 会变成 `sk-xxx\n`,DeepSeek 不认。

## 日常

| 要做的事 | 命令 |
|---|---|
| 改了代码,重新上线 | `npx wrangler deploy` |
| 看实时日志(只有状态码,不记内容) | `npx wrangler tail` |
| 类型检查 | `npm run check` |
| **换 key**(泄露了、或者定期换) | DeepSeek 后台新建 key → 用上面那条 `secret put DEEPSEEK_API_KEY` 覆盖 → 删掉旧 key。**App 不用发新版** |
| 换模型 | 改 `wrangler.jsonc` 的 `MODEL` → deploy。**App 不用发新版,但先跑 eval** |
| 改隐私政策 | 改 [`public/privacy.html`](public/privacy.html) → deploy。**改了发给 AI 的东西或接收方,App 的同意页和 `AIConsent.currentVersion` 也要一起改** |
| 改支持页 | 改 [`public/support.html`](public/support.html) → deploy。**改了 App 的交互(怎么写、怎么孵、怎么删),「常见问题」要跟着改** |

## 隐私政策页 / 支持页

同一个 Worker 顺带托管了两个静态页面,App Store Connect 里两个必填的网址都指向这里:

| 页面 | 线上地址 | 谁在用 |
|---|---|---|
| [`public/privacy.html`](public/privacy.html) | `https://slime-relay.hen-diary-2026.workers.dev/privacy` | App 的设置页、同意页;ASC「隐私政策网址」 |
| [`public/support.html`](public/support.html) | `https://slime-relay.hen-diary-2026.workers.dev/support` | ASC「支持网址」 |

靠的是 `wrangler.jsonc` 里的 `assets`:请求先看 `public/` 里有没有对应的文件,**有就直接返回、不进 `src/index.ts`**,
没有才轮到中转的逻辑。所以加页面没动 `index.ts` 一行,`/chat/completions` 照旧。

本地看:`npm run dev` → 打开 `http://localhost:8787/privacy`、`/support`。
开发者名字、联系邮箱两页都有(中英各一处),改的话一起改。

## 错误码

中转自己拒的是 4xx,上游(DeepSeek)出的错统一成 502,两类不会混:

| 状态 | `error` | 意思 |
|---|---|---|
| 400 | `bad_install_id` / `bad_json` / `bad_messages` / `bad_role` / `bad_content` / `bad_format` / `bad_temperature` / `bad_stream` / `too_long` | 请求不合规矩 |
| 413 | `too_large` | 请求体超过 300KB |
| 429 | `rate_limited` | 被限流 |
| 502 | `upstream_401` / `upstream_402` / `upstream_429` / … | DeepSeek 返回了错误。**`upstream_401` = key 没设对;`upstream_402` = 余额不足** |
| 502 | `upstream_unreachable` | 连不上 DeepSeek |

App 那边不区分这些,非 2xx 一律 `AIError.badStatus`,走各自的失败路径(写日记照样存、孵蛋下次再补…)。
