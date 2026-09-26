//
//  母鸡日记的 AI 中转(Cloudflare Worker)
//
//      App ──(安装 ID)──▶ 这里 ──(DeepSeek key)──▶ DeepSeek
//          ◀────────── 原样流回 ◀──────────────
//
//  为什么要有它:key 放在 App 里 = 放在每个用户手上。IPA 解压就能读到 Secrets.plist。
//  现在 key 只存在 Cloudflare 的加密 secret 里,App 里一个密钥都没有。
//
//  它只做四件事,按顺序:
//    ① 认门:路径、方法、安装 ID 格式不对就拒
//    ② 限流:按安装 ID、按 IP 各一道(带开发者通行证的跳过)
//    ③ 重建请求:只挑 App 真会发的那几个字段,模型和输出上限由这里定
//    ④ 转发 + 原样流回:**不攒,边收边转**
//
//  它**不懂业务**:不看 prompt、不解析模型的回答、不记日志内容(日记是用户最私密的东西)。
//

export interface Env {
  /** DeepSeek 的 key。`wrangler secret put DEEPSEEK_API_KEY` 设,代码和配置文件里都没有它 */
  DEEPSEEK_API_KEY: string;
  /** 开发者通行证,可以不设。只给 eval 测试用 —— 带上它不限流(见 checkRateLimit) */
  DEV_TOKEN?: string;
  /** 上游地址。平时是 DeepSeek;本地测试时在 .dev.vars 里指向假服务器 */
  UPSTREAM_URL: string;
  /** 用哪个模型。放在服务端决定 = 换模型不用发 App 新版 */
  MODEL: string;
  /** 两个限流器,在 wrangler.jsonc 的 ratelimits 里声明 */
  PER_INSTALL: RateLimiter;
  PER_IP: RateLimiter;
}

/** Cloudflare 限流绑定的形状。只用到这一个方法,手写比引整个类型包清楚 */
interface RateLimiter {
  limit(options: { key: string }): Promise<{ success: boolean }>;
}

/**
 * 请求的上限。**每个数都要比 App 正常用到的大得多** —— 这些不是为了省钱卡用户,
 * 是为了让「拿中转当免费 DeepSeek 用」的人每次只能占很小一点便宜。
 */
const LIMITS = {
  /** 整个请求体。正常最大的是聊天(人设 + 检索到的旧日记 + 10 轮历史),几万字节 */
  maxBodyBytes: 300_000,
  /** 消息条数。聊天最多 1 条 system + 20 条历史 + 1 条当前 */
  maxMessages: 60,
  /** 所有消息的总字数。一天写的日记全部要进孵蛋那一次,给足 */
  maxTotalChars: 50_000,
  /** 模型最多写多少 token。母鸡说的每句话都很短,2048 ≈ 三千汉字,远远够 */
  maxTokens: 2048,
};

const INSTALL_ID = /^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$/i;

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    // ① 认门 ——————————————————————————————————————————————
    // 只开一个口子。路径跟 DeepSeek 的一样,App 那边只用换 baseURL
    const url = new URL(request.url);
    if (url.pathname !== "/chat/completions") return fail(404, "not_found");
    if (request.method !== "POST") return fail(405, "method_not_allowed");

    const installID = request.headers.get("X-Install-ID") ?? "";
    if (!INSTALL_ID.test(installID)) return fail(400, "bad_install_id");

    // ② 限流 ——————————————————————————————————————————————
    if (!(await checkRateLimit(request, env, installID))) return fail(429, "rate_limited");

    // ③ 重建请求 ———————————————————————————————————————————
    // 先看声明的长度,太大的连读都不读
    const declared = Number(request.headers.get("Content-Length") ?? 0);
    if (declared > LIMITS.maxBodyBytes) return fail(413, "too_large");
    // 分块传输时没有 Content-Length,读完再核一次。
    // 要按字节读再解码,不能用 request.text() 的 .length —— 那数的是字符,一个汉字 3 字节
    const bytes = await request.arrayBuffer();
    if (bytes.byteLength > LIMITS.maxBodyBytes) return fail(413, "too_large");

    let parsed: unknown;
    try {
      parsed = JSON.parse(new TextDecoder().decode(bytes));
    } catch {
      return fail(400, "bad_json");
    }
    const body = rebuild(parsed, env.MODEL);
    if (typeof body === "string") return fail(400, body);

    // ④ 转发 + 原样流回 ——————————————————————————————————————
    let upstream: Response;
    try {
      upstream = await fetch(env.UPSTREAM_URL, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${env.DEEPSEEK_API_KEY}`,
          ...(body.stream ? { Accept: "text/event-stream" } : {}),
        },
        body: JSON.stringify(body),
      });
    } catch {
      return fail(502, "upstream_unreachable");
    }

    // 上游出错(key 失效 401、余额不足 402、拥堵 429/503…)统一成 502 给 App。
    // App 只关心「成没成」,而且这样 App 收到的 4xx 一定是中转自己拒的,两类错误不会混。
    // 只记状态码(`wrangler tail` 能看到),不记内容。
    if (!upstream.ok) {
      console.error(`upstream ${upstream.status}`);
      await upstream.body?.cancel();
      return fail(502, `upstream_${upstream.status}`);
    }

    // 关键:把上游的 body(一个字节流)直接交出去,**不 await 它读完**。
    // DeepSeek 拥堵时会先回 200、再一直发空行保持连接(最长 10 分钟)。App 那边
    // 靠「有字节在到」来重置 60 秒的空闲超时 —— 这里要是攒完再回,App 会以为断线了。
    return new Response(upstream.body, {
      status: upstream.status,
      headers: {
        "Content-Type": upstream.headers.get("Content-Type") ?? "application/json",
        // no-transform:别让 Cloudflare 边缘压缩这个响应。
        // 压缩器会把零碎的小块攒起来再发,那几个保活用的空行就到不了 App 了。
        "Cache-Control": "no-cache, no-transform",
      },
    });
  },
} satisfies ExportedHandler<Env>;

// MARK: - 限流

/**
 * 两道限流,**任何一道不过就拒**:
 * - 按安装 ID:一台设备一分钟最多多少次。但安装 ID 是 App 自己报的,谁都能每次编一个新的 ——
 * - 所以再按 IP:编再多 ID,从同一个 IP 出来也只有这么多。
 *
 * ⚠️ 这是**减速带,不是墙**。Cloudflare 的限流是每个机房各算各的、最终一致,
 * 而且换 IP 就能绕开。真正封顶损失的是 DeepSeek 账户余额(预付费,花完就停)。
 * 它的作用是:让一个脚本没法在几分钟内刷光余额,给你发现和换 key 的时间。
 */
async function checkRateLimit(request: Request, env: Env, installID: string): Promise<boolean> {
  // eval 测试(重排并发 4 路,一分钟上百次)带通行证过来,不限。
  // 通行证泄露了也只是能绕过限流,拿不到 key、改不了模型。
  if (await hasDevToken(request, env)) return true;

  const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
  // 两道同时问,省一次往返
  const [byInstall, byIP] = await Promise.all([
    env.PER_INSTALL.limit({ key: installID }),
    env.PER_IP.limit({ key: ip }),
  ]);
  return byInstall.success && byIP.success;
}

/**
 * 比对通行证用「恒定时间比较」,不用 `===`。
 * `===` 遇到第一个不同的字符就返回,理论上可以靠测响应快慢一位一位猜出来。
 * 隔着网络几乎猜不出,但比较密钥就该这么写,成本是零。
 */
async function hasDevToken(request: Request, env: Env): Promise<boolean> {
  const given = request.headers.get("X-Dev-Token");
  if (!env.DEV_TOKEN || !given) return false;
  const a = new TextEncoder().encode(given);
  const b = new TextEncoder().encode(env.DEV_TOKEN);
  if (a.byteLength !== b.byteLength) return false;
  return crypto.subtle.timingSafeEqual(a, b);
}

// MARK: - 重建请求

type Role = "system" | "user" | "assistant";

interface UpstreamBody {
  model: string;
  messages: { role: Role; content: string }[];
  response_format: { type: "text" | "json_object" };
  temperature: number;
  stream: boolean;
  max_tokens: number;
}

/**
 * **不转发 App 发来的原样 JSON,而是按白名单挑字段、重新拼一个。**
 *
 * 原样转发的话,别人可以在里面塞 `tools`、`max_tokens: 8000`、换成更贵的模型……
 * 中转就成了一个谁都能用的免费 DeepSeek。重建之后,不管发来什么,
 * 发给 DeepSeek 的永远只有 App 用得到的那五个字段 + 这里定的模型和上限。
 *
 * 返回字符串 = 哪里不对(当错误码回给调用方)。
 */
function rebuild(raw: unknown, model: string): UpstreamBody | string {
  if (typeof raw !== "object" || raw === null) return "bad_body";
  const input = raw as Record<string, unknown>;

  // messages:必须是数组,每条只能是 system / user / assistant + 一段文字
  if (!Array.isArray(input.messages)) return "bad_messages";
  if (input.messages.length === 0 || input.messages.length > LIMITS.maxMessages) return "bad_messages";
  const messages: UpstreamBody["messages"] = [];
  let totalChars = 0;
  for (const m of input.messages) {
    if (typeof m !== "object" || m === null) return "bad_messages";
    const { role, content } = m as Record<string, unknown>;
    if (role !== "system" && role !== "user" && role !== "assistant") return "bad_role";
    if (typeof content !== "string") return "bad_content";
    totalChars += content.length;
    messages.push({ role, content });
  }
  if (totalChars > LIMITS.maxTotalChars) return "too_long";

  // response_format:App 只用这两种
  const format = (input.response_format as { type?: unknown } | undefined)?.type ?? "text";
  if (format !== "text" && format !== "json_object") return "bad_format";

  // temperature:App 用的是 0.1 ~ 1.0;DeepSeek 允许 0 ~ 2
  const temperature = input.temperature ?? 1;
  if (typeof temperature !== "number" || !(temperature >= 0 && temperature <= 2)) return "bad_temperature";

  const stream = input.stream ?? false;
  if (typeof stream !== "boolean") return "bad_stream";

  return {
    model,
    messages,
    response_format: { type: format },
    temperature,
    stream,
    max_tokens: LIMITS.maxTokens,
  };
}

// MARK: - 工具

/** 中转自己拒绝时的回复。只给一个错误码,不带细节 */
function fail(status: number, code: string): Response {
  return Response.json({ error: code }, { status });
}
