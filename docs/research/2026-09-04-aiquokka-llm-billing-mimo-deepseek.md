# aiquokka LLM 计费与用量适配调研

调研日期：2026-09-04（Asia/Shanghai）

仓库：`aiquokka-menubar`

范围：只读检查；本文是研究笔记，不包含 Swift、测试、`Package.swift` 或配置修改。

## 短结论

- 当前 upstream `main`（现场 commit `def6ca814d8da68aa36394a189c1bd2d918d3357`）已有 **Claude、Codex、Kimi、Grok、Copilot、DeepSeek、Kiro、Antigravity、Z.ai** 九个 provider；**没有 MiMo**。本机安装的旧 binary（`v0.0.0-20260820211128-01b313d8a0db`）已支持 DeepSeek，但尚未包含 Z.ai。
- DeepSeek 不需要再向当前 upstream “新增 provider”：已有官方 `GET https://api.deepseek.com/user/balance` 适配，能读到余额货币、总余额、赠金余额和充值余额。它是**账户现金余额**，不是官方返回的 token 使用率、额度上限或 reset 时间。
- MiMo 的官方资料足够实现 API 调用和**逐请求** token usage/价格估算，但截至本次检索，公开文档把账户级用量/账单放在 Console 的 Usage 页面（可按日期查看/导出），没有找到公开的账户余额、剩余额度或 reset API。该“没有公开文档化 endpoint”结论标为“未确认”，不能用私有 Console 请求反推稳定接口。
- 当前 macOS wrapper 是 provider-agnostic 的 YAML reader：只要新 provider 输出 `provider/plan/windows[].label/used_percent/resets_at/extra[]`，通常不需新增 provider 分支、UI 或错误处理；但 DeepSeek upstream 的关键字段是 `windows[].remaining` 和 `currency`，当前 Swift parser/UI 会忽略余额并只显示“无可用使用率窗口”。若要正确显示 DeepSeek/MiMo 的余额或绝对额度，需要扩展模型、解码和展示语义。

## 证据等级与访问说明

- **源码事实**：来自本地文件，或固定 commit 的 upstream 源码/README。
- **官方文档事实**：来自 Xiaomi MiMo 或 DeepSeek 一方的 API、价格、FAQ、Console 页面。
- **推断**：根据上述接口字段与当前 wrapper 行为推导，已明确标注。
- **未确认**：官方公开资料没有给出，尚未用真实新 API key 做调用或抓取私有 Console 网络请求；本文不编造 endpoint、价格或 SDK 行为。

所有外部来源均于 **2026-09-04** 访问；价格、模型和页面内容可能继续变化。

## 1. aiquokka 当前支持什么

### 1.1 upstream 与本机版本

| 检查对象 | 结果 | 证据 |
|---|---|---|
| upstream 当前分支 | `main` 指向 `def6ca814d8da68aa36394a189c1bd2d918d3357`；README 和 `cmd/root.go` 均列 DeepSeek、Z.ai，没有 MiMo。 | [upstream README（固定 commit）](https://raw.githubusercontent.com/McKean/aiquokka/def6ca814d8da68aa36394a189c1bd2d918d3357/README.md)、[cmd/root.go](https://raw.githubusercontent.com/McKean/aiquokka/def6ca814d8da68aa36394a189c1bd2d918d3357/cmd/root.go)；访问：2026-09-04 |
| 本机 binary | `/Users/sheneyan/go/bin/aiquokka`；Go build metadata：`github.com/McKean/aiquokka v0.0.0-20260820211128-01b313d8a0db`。 | 本地 `go version -m /Users/sheneyan/go/bin/aiquokka`；访问：2026-09-04 |
| 本机命令列表 | `claude codex kimi grok copilot deepseek kiro antigravity`；没有 `zai`。 | 本地 `/Users/sheneyan/go/bin/aiquokka --help`；访问：2026-09-04 |
| 本机 DeepSeek | `aiquokka deepseek --yml` 返回 `no DeepSeek API key found — set DEEPSEEK_API_KEY (sk-…)`；说明命令已存在，本机未配置该 key。 | 本地命令现场输出；访问：2026-09-04 |

### 1.2 upstream 的共同数据模型与 YAML

固定 commit 的 [`internal/usage/usage.go`](https://raw.githubusercontent.com/McKean/aiquokka/def6ca814d8da68aa36394a189c1bd2d918d3357/internal/usage/usage.go) 定义了 provider 适配的共同模型：

| 层级 | upstream 字段 | 能表达什么 | 不能自动证明什么 |
|---|---|---|---|
| Report | `provider`, `plan` | 显示名称、订阅/计划标签（若 provider 能提供） | `plan` 不等于官方账单状态 |
| Window | `label`, `used_percent`, `resets_at` | 时间窗使用率和 reset 时间 | 没有 `used_percent` 就不能声称有“使用率”；`resets_at` 不是余额到期日，除非 provider 明确这样定义 |
| Window | `used`, `limit` | provider 返回绝对计数时的已用/上限 | 当前终端 renderer 是否展示这些字段，取决于 upstream renderer；不是所有 provider 都有 |
| Window | `remaining`, `currency` | 余额型或预付型 remaining 数值及币种，例如 DeepSeek | remaining 是余额，不是“已用百分比”或固定 quota |
| Fact | `extra[].label/value` | provider-specific 的任意文字事实 | 值是上游适配器整理后的文本，不代表有统一账单语义 |

结构化输出由 [`cmd/run.go`](https://raw.githubusercontent.com/McKean/aiquokka/def6ca814d8da68aa36394a189c1bd2d918d3357/cmd/run.go) 负责：`--json`/`--yaml`（`--yml` alias）输出 `Report`；聚合输出以小写 provider 名称作为顶层 key；未配置 provider 被跳过；已配置但失败的 provider 输出 `{error: ...}`。因此，“aiquokka 支持某 provider”首先表示能通过其认证/数据源得到 `Report`，不等同于 provider 提供了官方公开 billing API。

### 1.3 provider 适配表

下表按当前 upstream `main` 的 `allProviders` 与 README 记录。endpoint 多数是官方 CLI 或内部服务使用的接口；README 明确提醒这些 endpoint 可能是 undocumented，不能把它们统一称为官方公开计费 API。

| provider 名称 | 认证 / 数据来源 | 读取/展示的主要数据 | 是否是官方 API 账单/配额 | YAML 能否被当前 wrapper 读取 |
|---|---|---|---|---|
| Claude | 本机 Claude Code OAuth：credentials 文件或 macOS Keychain | 5h、Weekly、Weekly Fable 的百分比和 reset；plan | 订阅 usage endpoint；源码标为 Claude Code undocumented endpoint，不是公开消费账单 | 能；标准 `windows/extra` 形状 |
| Codex | `~/.codex/auth.json` 的 ChatGPT OAuth | 5h/Weekly 百分比和 reset；plan；`Resets`、`Credits` extra | ChatGPT/Codex 后台 usage；是官方客户端数据源，但不是公开 API 账单接口 | 能；标准窗口和 extra |
| Kimi | `~/.kimi-code`/`~/.kimi` OAuth，或 `KIMI_API_KEY` | coding subscription 的 rolling windows 与 Weekly 的 used/limit/remaining/reset | Kimi Code usage；不是通用 Kimi API 账单；README 说明 endpoint undocumented | 能；结构化字段可读 |
| Grok | `~/.grok/auth.json` 的 xAI OIDC | 周期使用百分比和 reset；subscription tier；Grok Code access | Grok CLI `/usage` 背后的 billing/credits endpoint；源码/README 将其作为 undocumented CLI endpoint | 能；标准窗口和 extra |
| Copilot | `~/.config/github-copilot/{apps,hosts}.json` | Chat、Completions、Premium Interactions 的 usage limits | GitHub `copilot_internal` usage endpoint；是官方客户端相关数据，但不是公开 billing API | 能；标准窗口/extra |
| **DeepSeek** | 环境变量 `DEEPSEEK_API_KEY`（静态 API key） | 账户 balance：`remaining`、`currency`；`Granted`、`Topped up` extra；状态 unavailable 时写 extra | **是官方文档化的余额 API**，但余额不是 token usage quota，也没有 reset 字段；见第 3 节 | provider/error/extra 能读；当前 wrapper 不读 `remaining/currency`，见第 4 节 |
| Kiro | 调用已安装 `kiro-cli /usage`，由 Kiro CLI 保管 credentials/refresh | 月度 credits、plan、reset、overage | 通过官方 CLI 的 usage 输出；wrapper 本身不直接调用 billing endpoint | 能；前提是 CLI 输出落在共同 YAML 模型 |
| Antigravity（alias `agy`） | `~/.gemini/antigravity-cli/antigravity-oauth-token` | daily quota windows | Google/Antigravity CLI 使用的受限 quota endpoint；README 标为 undocumented | 能；标准窗口 |
| Z.ai | `ZAI_API_KEY`，或 `~/.pi/agent/models.json` 中的 zai provider | token bundles 的 used/total、cash balance、适用模型等 | Z.ai 业务接口；README 标为 undocumented；upstream 有，本机旧 binary 尚无 | 能读共同字段；本机 binary 不会产出该 provider |

upstream 细节的入口：[`cmd/root.go`](https://github.com/McKean/aiquokka/blob/def6ca814d8da68aa36394a189c1bd2d918d3357/cmd/root.go)、[`internal/usage/usage.go`](https://github.com/McKean/aiquokka/blob/def6ca814d8da68aa36394a189c1bd2d918d3357/internal/usage/usage.go)、[`internal/deepseek/deepseek.go`](https://github.com/McKean/aiquokka/blob/def6ca814d8da68aa36394a189c1bd2d918d3357/internal/deepseek/deepseek.go)；访问：2026-09-04。

## 2. Xiaomi MiMo：API/计费可接入性

### 2.1 名称与产品边界

这里的 MiMo 指小米的 **Xiaomi MiMo API Open Platform**，当前文档入口从 `platform.xiaomimimo.com` 跳转到 `mimo.mi.com`。不要把 MiMo API、MiMo Studio、MiMo Claw、MiMo Code 或 Token Plan 当作同一个计费面。官方文档首页称 API 同时兼容 OpenAI 与 Anthropic 格式；[官方文档索引](https://mimo.mi.com/llms.txt) 与 [API 首页](https://mimo.mi.com/docs/en-US) 访问：2026-09-04。

### 2.2 当前模型、endpoint 和认证

| 使用方式 | 官方当前资料 | 认证与 endpoint | 计费/额度边界 |
|---|---|---|---|
| Pay-as-you-go API | 当前文本模型为 `mimo-v2.5-pro`、`mimo-v2.5`；另有 ASR/TTS 系列。旧 `mimo-v2-pro`、`mimo-v2-omni`、`mimo-v2-flash` 等在模型页标为 2026-06-30 deprecated。 | OpenAI 兼容 `https://api.xiaomimimo.com/v1`，请求路径 `/v1/chat/completions`；API key 可用 `api-key: ...` 或 `Authorization: Bearer ...`，格式示例 `sk-xxxxx`。 | 按实际 token 从普通账户 balance 扣款；与 Token Plan 不互通。 |
| Token Plan | 覆盖 `mimo-v2.5-pro`、`mimo-v2.5`、ASR/TTS 等六类模型；固定月/年套餐，以 Credits 换算消耗。 | 专用 Base URL 示例 `https://token-plan-cn.xiaomimimo.com/v1`，专用 key 格式 `tp-xxxxx`；购买后从 Token Plan 管理页获取。 | 固定订阅资源包；不同模型按不同换算比例共享套餐；文档明确与普通 API balance 分离。 |

证据：[首次 API 调用（官方 Markdown）](https://mimo.mi.com/static/docs/quick-start/summary/first-api-call.md)、[模型列表与 rate limit](https://mimo.mi.com/static/docs/quick-start/summary/model.md)、[OpenAI Chat Completions API](https://mimo.mi.com/static/docs/api/chat/openai-api.md)、[Token Plan](https://mimo.mi.com/static/docs/price/token-plan.md)；访问：2026-09-04。

### 2.3 官方当前价格与能读取的 usage

官方 Pay-as-you-go 页面当前列出的每 1M token 价格如下；这里保留币种和 cache hit/miss 维度，避免把不同区域混成一个价格：

| 模型 | 中国区：输入 cache hit / miss / 输出 | 海外区：输入 cache hit / miss / 输出 |
|---|---:|---:|
| `mimo-v2.5-pro` | ¥0.025 / ¥3.00 / ¥6.00 | $0.0036 / $0.435 / $0.87 |
| `mimo-v2.5` | ¥0.02 / ¥1.00 / ¥2.00 | $0.0028 / $0.14 / $0.28 |
| `mimo-v2.5-asr` | ¥0.5 / 小时 | $0.074 / 小时 |
| TTS 系列 | 限时免费 | 限时免费 |

官方价格页还说明 web search 另按调用次数计费，ASR 按输入音频时长计费；所以仅拿 `total_tokens` 不能覆盖所有 MiMo 费用。来源：[官方 Pay-as-you-go API Pricing](https://mimo.mi.com/static/docs/price/pay-as-you-go.md)，访问：2026-09-04。

OpenAI 兼容响应的 `usage` 文档字段包括：

```text
completion_tokens
prompt_tokens
total_tokens
completion_tokens_details.reasoning_tokens
prompt_tokens_details.cached_tokens
prompt_tokens_details.audio_tokens
prompt_tokens_details.image_tokens
prompt_tokens_details.video_tokens
web_search_usage.tool_usage/page_usage
```

这是**单次请求**的 token/tool usage，足够在调用方保存请求日志后按官方价格做估算；它本身不是账户余额、套餐剩余量或 reset 时间。来源：[官方 OpenAI 兼容响应 schema](https://mimo.mi.com/static/docs/api/chat/openai-api.md)，访问：2026-09-04。

### 2.4 账户级 usage/billing 的可见性

官方首次调用文档写明：在 [Console Usage Information](https://platform.xiaomimimo.com/#/console/usage) 页面可以按日期查看并导出账户模型 token usage 和 request count；官方多媒体文档也把该 Console 页面称为查看 bill/usage 的位置。普通 API 的余额入口是 [Account Balance](https://platform.xiaomimimo.com/#/console/balance)，Token Plan 的配额入口是 [Plan Manage](https://platform.xiaomimimo.com/#/console/plan-manage)。

截至本次对 [官方文档索引/全文](https://mimo.mi.com/llms-full.txt)、API reference 和 FAQ 的检索：

- **已确认**：官方公开文档给出了调用 endpoint、API key 认证、价格、逐请求 usage，以及 Console Usage/Balance/Plan Manage 页面。
- **未确认**：没有找到公开文档化的“账户余额 JSON API”“套餐已用/剩余 Credits API”或“reset/到期时间 API”。Console 可能有私有后端请求，但没有做抓包，也没有将私有请求当作稳定适配依据。
- 因此，MiMo 不能仅凭当前公开资料可靠地产生 aiquokka 所需的 `used_percent + resets_at` 账户窗口。若用逐请求 usage 和价格自行累计，必须明确标成“本地估算”，且不能声称等于 Xiaomi 官方账单；若导入 Console 导出的历史 CSV，也只能在导出后显示该快照，不是实时 API。

## 3. DeepSeek：当前官方能力与 upstream 适配

### 3.1 官方模型、endpoint、认证和价格

DeepSeek 当前官方 Quick Start 列出：

- 模型：`deepseek-v4-flash`、`deepseek-v4-pro`、`deepseek-v4-flash-vision-exp`。
- OpenAI base URL：`https://api.deepseek.com`；Anthropic base URL：`https://api.deepseek.com/anthropic`。
- 调用认证：`Authorization: Bearer ${DEEPSEEK_API_KEY}`；官方示例请求为 `POST /chat/completions`。
- 价格按每 1M token、cache hit/miss、peak/off-peak 区分；官方当前页面列出 `v4-flash` 为 cache hit `$0.007/$0.014`、cache miss `$0.22/$0.44`、output `$0.66/$1.32`，`v4-pro` 为 `$0.022/$0.044`、`$0.66/$1.32`、`$1.98/$3.96`（前者 off-peak/后者 peak）。峰时段为 UTC 01:00–04:00、06:00–10:00，周一至周五；价格页提示价格可能调整。

来源：[DeepSeek First API Call](https://api-docs.deepseek.com/)、[Models & Pricing](https://api-docs.deepseek.com/quick_start/pricing/)、[官方平台 Balance 页面](https://platform.deepseek.com/balance)；访问：2026-09-04。

### 3.2 单次请求 usage

DeepSeek Chat Completions response 官方 schema 明确给出：`completion_tokens`、`prompt_tokens`、`prompt_cache_hit_tokens`、`prompt_cache_miss_tokens`、`total_tokens`，以及 `completion_tokens_details.reasoning_tokens`。流式响应的最后一个 chunk 也会携带该请求的 usage。官方 Token & Token Usage 页面说明实际 token 应以 API 返回为准。

来源：[Chat Completions API response schema](https://api-docs.deepseek.com/api/create-chat-completion/)、[Token & Token Usage](https://api-docs.deepseek.com/quick_start/token_usage/)，访问：2026-09-04。

### 3.3 官方余额 API 与“已用/剩余/reset”边界

DeepSeek 有公开文档化的：

```text
GET https://api.deepseek.com/user/balance
Authorization: Bearer <DeepSeek API Key>
```

响应字段为：

```json
{
  "is_available": true,
  "balance_infos": [
    {
      "currency": "CNY",
      "total_balance": "110.00",
      "granted_balance": "10.00",
      "topped_up_balance": "100.00"
    }
  ]
}
```

官方定义 `is_available` 为余额是否足够 API 调用，`total_balance` 是包括赠金和充值的可用余额，且赠金优先扣除。该 endpoint **没有** token 已用数量、总 quota、余额 reset 时间或赠金过期时间字段。

官方 FAQ 另说明，账户级使用明细在网页的 Usage 页面选择月份并 Export，下载包内 `amount` CSV 按 key 给出 usage；这是 Console 导出，不是本文找到的公开 API endpoint。来源：[Get User Balance](https://api-docs.deepseek.com/api/get-user-balance/)、[DeepSeek FAQ（Billing/Usage by API Key）](https://api-docs.deepseek.com/faq)、[Token & Token Usage](https://api-docs.deepseek.com/quick_start/token_usage/)，访问：2026-09-04。

**判断**：DeepSeek 可以可靠展示“当前剩余货币余额、币种、赠金/充值拆分、是否可用”；可以对保存下来的逐请求 usage 做价格估算；不能仅靠官方 `/user/balance` 声称“本周期已用百分比、剩余 token quota、余额重置时间”。公开 API 是否存在未列入当前文档的其他账户接口：**未确认**。

### 3.4 upstream 已有实现

固定 commit 的 [`internal/deepseek/deepseek.go`](https://raw.githubusercontent.com/McKean/aiquokka/def6ca814d8da68aa36394a189c1bd2d918d3357/internal/deepseek/deepseek.go) 已实现：

1. 读取 `DEEPSEEK_API_KEY`；支持 `DEEPSEEK_BASE_URL` 覆盖默认 base URL。
2. 带 Bearer key 请求 `/user/balance`。
3. 将每个 currency 的 `total_balance` 映射成 `usage.Window{Remaining, Currency}`。
4. 将 `granted_balance` 和 `topped_up_balance` 映射成 `extra` facts。
5. `is_available=false` 时保留 `Status: unavailable`，没有余额数值时显示 unknown。

这说明 DeepSeek upstream 的语义是“remaining-balance window”，不是普通 `used_percent` window；README 也明确说余额栏在有余额时为满、余额归零时为空，真正有意义的是金额。来源：[upstream README DeepSeek 说明](https://raw.githubusercontent.com/McKean/aiquokka/def6ca814d8da68aa36394a189c1bd2d918d3357/README.md)、[DeepSeek adapter](https://github.com/McKean/aiquokka/blob/def6ca814d8da68aa36394a189c1bd2d918d3357/internal/deepseek/deepseek.go)，访问：2026-09-04。

## 4. 当前 macOS wrapper 的影响

现场检查的 Swift 事实：

- [`UsageCommandRunner.swift`](../../Sources/AiQokkaMenubar/UsageCommandRunner.swift) 只直接执行本地 `aiquokka --yml`，不读取 provider credentials，也不维护 provider 列表。
- [`UsageYAMLDecoder.swift`](../../Sources/AiQokkaMenubar/UsageYAMLDecoder.swift) 按顶层 key 泛化解码 provider；读取 `provider`、`plan`、`error`、`windows[].label`、`windows[].used_percent`、`windows[].resets_at` 和 `extra[].label/value`；未知字段会被忽略。
- [`UsageModels.swift`](../../Sources/AiQokkaMenubar/UsageModels.swift) 当前没有 `remaining`、`currency`、`used`、`limit` 等属性。
- [`UsagePopoverView.swift`](../../Sources/AiQokkaMenubar/UsagePopoverView.swift) UI 主要显示百分比进度条、reset 文本和 extra；没有单独的金额/币种/绝对余额组件。provider error 会单独显示，不会伪装成空 usage。
- 这些事实与本地测试 fixture 的 `provider/plan/windows/used_percent/resets_at/extra/error` 形状一致；没有添加任何研究专用 fixture。

### 4.1 “只解码新 provider YAML”是否足够

| 场景 | upstream/CLI 侧 | 当前 wrapper 侧 | 可可靠展示的内容 |
|---|---|---|---|
| 新 provider 输出标准 usage window：`label + used_percent + resets_at` | 需要 provider adapter、命令注册、测试和 README；wrapper 不需要 provider-specific 分支 | 泛化 YAML decoder、通用 UI、通用错误处理均可复用 | provider 名、plan、百分比、reset、extra |
| MiMo 仅输出逐请求 usage 后自行转成标准百分比 | upstream 还需要定义数据来源/累计规则；官方 API 本身不会给账户百分比 | 若最终 YAML 符合标准 window，wrapper 可读取 | 只能叫本地累计/估算；不能叫 Xiaomi 官方实时 billing |
| DeepSeek 当前 upstream 输出 `remaining + currency` | upstream 已完成 | **仅解码不够**：当前 parser 忽略两字段，UI 看不到余额数值；需要 Swift model/decoder/UI 扩展，或 upstream 另输出兼容的文字 extra | 不改 Swift 时最多显示 provider、可能的 extra；不能正确显示账户余额 |
| provider 返回顶层 `error` | upstream 负责产生错误对象 | 当前 wrapper 已保留 provider error，并保留上一次成功快照 | 可显示失败原因；不应把失败渲染成 0% |

因此，对当前 wrapper 的准确回答是：**没有 provider 注册表，所以标准 YAML 新 provider 通常只需 CLI 输出变化；但 DeepSeek/MiMo 的余额型数据不是当前 UI 的数据语义，若要求“看得到并看对金额/币种”，仍要改 Swift 的模型、解码和 UI。错误处理不需要为 MiMo/DeepSeek 单独分支，除非上游引入新的错误形状。**

## 5. 明确判断：直接加入 provider 需要什么

### 5.1 MiMo 加入 aiquokka upstream

至少需要以下 upstream 代码/文档工作（本文没有实施）：

1. 新增 `internal/mimo` package：认证、区域/模式选择、官方 endpoint 请求、响应校验、context timeout 和错误分类。
2. 把结果映射到共同 `usage.Report`。若没有官方账户级 balance/quota endpoint，必须先确定产品语义：逐请求计费估算、Console CSV 快照，或未实现账户账单；不能把猜测的私有接口写成稳定 provider。
3. 新增 `cmd/mimo.go`，在 `cmd/root.go` 的 `allProviders` 和 Cobra command tree 注册 `mimo`。
4. 为 pay-as-you-go 与 Token Plan 的不同 key/base URL、币种/区域、cache hit/miss、web search/ASR 计费维度增加测试。
5. 更新 README 的 provider/credentials/endpoint 表，并说明哪些 endpoint 是官方文档化、哪些不是。

若最终输出只有标准 `used_percent/resets_at/extra`，macOS wrapper 可不改；若要展示 MiMo 余额、Credits、币种、逐请求估算或 CSV 时间范围，则需要先扩展 Swift 数据模型和 UI 语义。

### 5.2 DeepSeek

- 当前 upstream 已有 provider、Cobra command、余额 API 适配和测试方向；不需要新增 provider 代码。
- 本机 binary 也已包含 `deepseek`，但本机 key 未配置；是否升级本机 binary 属于后续操作，本文没有修改安装文件。
- 要让当前 macOS App 正确显示 current upstream 的 DeepSeek 余额，最小 Swift 变更不是“新增 provider 分支”，而是支持 `remaining/currency` 并将进度条标为“剩余余额”而不是“已用百分比”。
- 若只想显示 DeepSeek 的 `Granted`/`Topped up` 文本，现有 `extra` 已可承载，但仍不能把它们误标成 quota/reset。

## 6. 建议的最小实现顺序与阻塞点

1. **先完成 DeepSeek wrapper 语义补齐**：以真实但不提交的 `deepseek --yml` 样例验证 `remaining/currency/extra`，为余额型窗口增加显示和测试；保持 provider error 与旧快照行为。
2. **再确认 MiMo 官方数据面**：让 Xiaomi 明确是否提供面向 API key 的余额/usage/billing endpoint，响应是否含 remaining、limit、reset/expiry、currency；在确认前不抓取或依赖私有 Console API。
3. **若 Xiaomi 只有 Console 导出**：把“导入账单快照”与“aiquokka provider 实时查询”分开设计；不要伪造 `used_percent`。若只做逐请求估算，要保存请求 usage、模型、区域、peak/off-peak、cache 和附加工具计费，并明确是本地估算。
4. **官方 endpoint 确认后再写 upstream MiMo adapter**：先单 provider 命令，再聚合注册，再 README/测试；最后用脱敏 YAML 检查 macOS wrapper。
5. **验收门槛**：源码单测/结构化 YAML 只证明适配和解码；还需分别验证官方 API 实际响应、真实账户余额/Console 对账、macOS UI 的余额语义。没有真实 key、官方 endpoint 或 Console 对账证据时，billing 结论应保持“未确认”。

## 7. 来源清单（均访问于 2026-09-04）

### aiquokka upstream

- [README（固定 commit）](https://raw.githubusercontent.com/McKean/aiquokka/def6ca814d8da68aa36394a189c1bd2d918d3357/README.md)
- [`cmd/root.go`](https://raw.githubusercontent.com/McKean/aiquokka/def6ca814d8da68aa36394a189c1bd2d918d3357/cmd/root.go)
- [`cmd/run.go`](https://raw.githubusercontent.com/McKean/aiquokka/def6ca814d8da68aa36394a189c1bd2d918d3357/cmd/run.go)
- [`internal/usage/usage.go`](https://raw.githubusercontent.com/McKean/aiquokka/def6ca814d8da68aa36394a189c1bd2d918d3357/internal/usage/usage.go)
- [`internal/deepseek/deepseek.go`](https://raw.githubusercontent.com/McKean/aiquokka/def6ca814d8da68aa36394a189c1bd2d918d3357/internal/deepseek/deepseek.go)

### Xiaomi MiMo 官方

- [官方文档索引 `llms.txt`](https://mimo.mi.com/llms.txt)
- [首次 API 调用](https://mimo.mi.com/static/docs/quick-start/summary/first-api-call.md)
- [Models](https://mimo.mi.com/static/docs/quick-start/summary/model.md)
- [OpenAI Chat Completions API](https://mimo.mi.com/static/docs/api/chat/openai-api.md)
- [Pay-as-you-go API Pricing](https://mimo.mi.com/static/docs/price/pay-as-you-go.md)
- [Token Plan](https://mimo.mi.com/static/docs/price/token-plan.md)
- [Rate Limit](https://mimo.mi.com/static/docs/api/guidance/rate-limit.md)
- [官方文档全文索引 `llms-full.txt`](https://mimo.mi.com/llms-full.txt)
- [Console Usage](https://platform.xiaomimimo.com/#/console/usage)、[Account Balance](https://platform.xiaomimimo.com/#/console/balance)、[Token Plan Manage](https://platform.xiaomimimo.com/#/console/plan-manage)

### DeepSeek 官方

- [Your First API Call](https://api-docs.deepseek.com/)
- [Models & Pricing](https://api-docs.deepseek.com/quick_start/pricing/)
- [Token & Token Usage](https://api-docs.deepseek.com/quick_start/token_usage/)
- [Chat Completions API](https://api-docs.deepseek.com/api/create-chat-completion/)
- [Get User Balance](https://api-docs.deepseek.com/api/get-user-balance/)
- [Rate Limit & Isolation](https://api-docs.deepseek.com/quick_start/rate_limit/)
- [DeepSeek FAQ](https://api-docs.deepseek.com/faq)
- [Official Platform Balance](https://platform.deepseek.com/balance)

## 8. 未确认项

- Xiaomi MiMo 是否存在未公开在当前 API reference 的账户 balance/usage/quota/reset JSON endpoint；未做私有 Console 抓包，也未用真实 MiMo key 试调用。
- Xiaomi Console 导出的具体 CSV schema、是否包含可直接换算的 remaining/limit/reset/expiry 字段；官方文档只确认可以查看/导出 usage 与 request count。
- Xiaomi MiMo 是否会为第三方 CLI/aiquokka 提供稳定、允许自动轮询的账户级 API；当前公开资料不足以确认。
- DeepSeek 是否存在当前公开文档之外的账户级“已用 token/额度 reset” API；已确认的 `/user/balance` 不含这些字段。
- 使用官方价格对逐请求 usage 做本地累计时，历史价格、peak/off-peak、赠金优先扣款、跨 key/模型/币种对账的精确规则是否与 Console 导出完全一致；没有实际账单对账前只能称估算。
