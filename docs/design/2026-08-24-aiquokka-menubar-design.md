# aiquokka macOS 菜单栏 App 设计

日期：2026-08-24

## 目标

提供一个原生 macOS 菜单栏 App，读取本机已经安装的 `aiquokka` 命令输出，在菜单栏提供简短状态，并在点击后展示完整的 provider 使用数据。

## 已确认范围

- 数据源仅为本机已安装的 `aiquokka` 可执行文件。
- App 通过执行 `aiquokka --yml` 获取数据，不复制、解析或接管各官方 CLI 的凭据。
- 默认每 60 秒刷新一次，并支持手动立即刷新。
- 菜单栏只显示简短总览；点击后打开完整详情 Popover。
- MVP 不包含凭据管理、账户登录、通知、历史记录、图表、云同步或自定义轮询间隔。

## 推荐架构

采用原生 SwiftUI macOS App：

```text
MenuBarExtra
  └─ UsagePopoverView
       ├─ RefreshHeader
       └─ ProviderListView

UsageStore
  └─ UsageCommandRunner
       └─ Process("aiquokka", "--yml")
```

`UsageStore` 负责刷新调度、加载状态、最近一次成功数据和错误状态。`UsageCommandRunner` 只负责定位并执行命令、捕获 stdout/stderr 和退出码，不包含 UI 逻辑。YAML 解析结果转换为稳定的 Swift 模型：`UsageSnapshot`、`ProviderUsage`、`UsageWindow` 和 `UsageExtra`。

命令定位顺序应明确且可诊断：先检查常见用户级路径（例如 `/opt/homebrew/bin/aiquokka`、`/usr/local/bin/aiquokka`、`$HOME/go/bin/aiquokka`），再使用登录 shell 的 PATH 查找；最终在错误状态中显示实际尝试过的路径。App 不应静默下载或安装命令。

## 数据流与刷新

1. App 启动后立即执行一次 `aiquokka --yml`。
2. 每 60 秒触发一次刷新；刷新期间保留上一次成功数据并显示加载状态。
3. 用户点击“立即刷新”时，如果已有刷新在进行，则忽略重复请求。
4. 成功时更新快照、更新时间和菜单栏摘要。
5. 失败时保留上一次成功快照；如果没有成功数据，则显示空状态和可读错误。
6. App 退出或 Popover 关闭不应取消后台刷新模型；生命周期由 App 持有的 store 管理。

`--yml` 输出按 provider 名称聚合，provider 下包含 `provider`、`plan`、`windows` 和 `extra`。解析器应允许缺少可选字段、空数组和未知 provider；未知字段不影响已知字段展示。日期解析失败时保留原始字符串，不能让整次快照失败。

## 界面设计

### 菜单栏

- 正常状态：显示轻量 `Q`/quokka 图标和总体状态摘要。
- 有数据但 provider 较多时，摘要显示最紧迫或最高使用率窗口的百分比。
- 加载中：图标显示轻量进度状态，不阻塞菜单栏。
- 错误：显示警示符号；若存在上一次成功数据，仍允许打开详情查看旧数据。

### 详情 Popover

- 顶部显示标题、最后更新时间和“立即刷新”按钮。
- 主体为可滚动 provider 列表，每个 provider 显示名称、plan、窗口标签、使用率进度条、百分比和 reset 时间。
- provider 卡片支持展开，查看所有窗口的完整值以及 `extra` 项。
- 时间同时显示相对时间和必要的绝对时间，避免用户误解时区。
- 无数据时显示原因及“重试”；找不到命令时补充打开终端排查的提示。
- 底部提供“退出”入口；MVP 不提供设置页。

## 错误处理

- 命令不存在：提示安装/配置 `aiquokka`，但不自动执行安装。
- 非零退出：展示退出码和 stderr 的安全截断内容。
- YAML 解析失败：展示解析失败，并保留原始输出到诊断日志，不直接塞入界面。
- 单个 provider 错误：若上游 YAML 已返回该 provider 的错误表示，作为该 provider 的错误卡片展示，不影响其他 provider。
- 超时：单次命令设置合理超时，超时后终止子进程并展示可重试状态。
- 凭据权限问题：只展示 `aiquokka` 返回的错误，不读取凭据文件，也不要求用户输入敏感信息。

## 测试与验收

- 单元测试：YAML 正常样例、空 provider、缺少可选字段、未知字段、坏日期和 provider 错误。
- Store 测试：启动刷新、60 秒调度、重复刷新抑制、失败保留旧快照、无旧快照错误状态。
- Command runner 测试：命令路径发现、stdout/stderr、非零退出和超时；使用可注入的执行器，不直接依赖真实用户凭据。
- UI 验收：菜单栏常驻、点击打开 Popover、完整数据滚动展示、手动刷新、错误状态可见、退出入口可用。
- 集成验证：在本机用真实 `aiquokka --yml` 输出验证解析；不得把真实凭据或输出中的敏感内容提交到仓库。

## 非目标与后续方向

本阶段不做后台安装、自动升级 `aiquokka`、凭据诊断、历史趋势、通知阈值、菜单栏自定义格式或远程数据源。后续若需要，可在稳定的 `UsageStore` 和模型之上增加历史持久化与通知，而不改变命令读取边界。
