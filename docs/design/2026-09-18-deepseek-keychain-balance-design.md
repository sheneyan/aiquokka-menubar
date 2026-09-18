# DeepSeek Keychain 与余额展示设计

> Status: approved design; not implemented in the current release.

## 目标

让 macOS 菜单栏 App 在不读取 `~/.zshrc`、不把密钥写入 `UserDefaults` 或项目文件的前提下，稳定向本地 `aiquokka --yml` 提供 `DEEPSEEK_API_KEY`，并正确展示 DeepSeek 返回的余额型窗口。

本设计只扩展 DeepSeek 的本机凭据桥接和通用余额模型。App 仍不直接请求 DeepSeek API，也不复制上游 provider 实现；所有网络请求继续由本机 `aiquokka` CLI 发起。

## 用户行为

- 详情页增加“DeepSeek”折叠设置区，菜单栏与独立窗口继续共享同一设置状态。
- 未配置时显示“未配置”，并提供 `SecureField` 输入 API Key。
- 用户点击“保存”后，App 将去除首尾空白的非空 Key 写入 macOS Keychain；界面立即清空输入框并触发一次 usage 刷新。
- 已配置时显示“已配置”。App 不回填、不显示、不复制已保存的 Key。
- 已配置时提供“删除”操作。删除成功后立即刷新，DeepSeek provider 应从下一次聚合结果中消失；删除不影响 `~/.zshrc` 或其他程序保存的凭据。
- Keychain 保存、读取或删除失败时，在 DeepSeek 设置区显示可理解的错误，不把密钥或原始 Security Framework 数据写入错误文案。
- 同一个 App 构建正常启动和每 60 秒刷新时不要求重复确认。继续接受 ad-hoc 签名的限制：重新构建并替换 App 后，代码身份变化，macOS 可能重新要求钥匙串授权。

## 方案选择

采用 App 内 `SecureField` + macOS Keychain：

- 相比终端命令录入，用户能在现有详情界面完成配置、删除和状态确认。
- 相比读取 `~/.zshrc`，不会执行任意 shell 初始化代码，也不依赖 GUI 进程无法继承的交互 shell 环境。
- 相比把 Key 写入 `UserDefaults` 或普通配置文件，Keychain 提供系统级加密存储和按 App 代码身份控制的访问权限。

不要求 Touch ID、设备密码或 `.userPresence`。这类交互式保护会与 60 秒后台刷新冲突。Keychain item 使用仅限本机、设备解锁时可访问的等级；当前 ad-hoc 构建在同一二进制内可静默访问，重新构建后的再次授权是明确接受的行为。

## 架构与数据流

新增三个独立边界：

- `DeepSeekCredentialStore`：定义 `load`、`save`、`delete` 和配置状态所需的最小接口。生产实现封装 Security Framework，测试实现使用内存存储。
- `KeychainDeepSeekCredentialStore`：使用固定 service `io.github.sheneyan.aiquokka-menubar.deepseek` 和 account `DEEPSEEK_API_KEY` 保存 generic password item。重复保存执行更新，不创建多个 item；删除不存在的 item 按成功处理。
- `DeepSeekSettings`：`@MainActor`、`ObservableObject` 的界面状态模型，持有输入草稿、是否已配置、是否正在保存和可展示错误。它不长期缓存已保存的明文 Key。

刷新链路保持单向：

```text
DeepSeekSettings 保存 Key
        ↓
macOS Keychain
        ↓ 每次 usage 刷新时短暂读取
UsageCommandRunner extraEnvironment
        ↓
DEEPSEEK_API_KEY=<内存中的值> aiquokka --yml
        ↓
UsageYAMLDecoder → UsageSnapshot → SwiftUI
```

`UsageCommandRunner` 在每次执行前通过一个注入的 environment provider 获取额外环境变量。Keychain 中存在非空 Key 时，以该值覆盖 App 进程可能继承的同名变量；Keychain 未配置或读取失败时，不注入 `DEEPSEEK_API_KEY`。Keychain 读取失败必须反馈给 UI/刷新错误，而不是静默回退到不确定的旧值。

Key 只在一次刷新调用的局部作用域和 `Process.environment` 中存在。App 不记录 Key、不把它加入通知、ntfy 消息、YAML fixture、测试输出或诊断日志。

## 余额数据模型

现有 `UsageWindow` 只保存 `used_percent` 和 reset 信息，无法表示 DeepSeek 的：

```yaml
- label: Balance
  remaining: 110.0
  currency: CNY
```

扩展 `UsageWindow`：

- `usedPercent: Double?`
- `used: Double?`
- `limit: Double?`
- `remaining: Double?`
- `currency: String?`
- 既有 reset 字段保持不变。

解码器接受整数、浮点数和数值字符串。窗口的显示规则按数据语义排序：

1. 有 `used_percent`：显示百分比和进度条。
2. 有合法的 `used`、正数 `limit`：计算 `used / limit * 100`，显示百分比、绝对值和进度条。
3. 有 `remaining`：显示格式化余额，不显示虚假的百分比进度；常见货币使用 `¥`、`$`、`€`、`£`，未知货币显示 `数值 + ISO code`。
4. 均缺失：保留当前的 `—`/无可用使用率状态。

余额型窗口不参与最高使用率、菜单栏百分比、80%/95% 提醒或 ntfy 百分比里程碑。只有能从 `used_percent` 或 `used/limit` 得到有效 0–100 百分比的窗口才参与这些逻辑。

DeepSeek provider 摘要在没有百分比时显示主余额，例如 `¥110.00`，而不是“没有可用的使用率窗口”。菜单栏全局摘要仍显示其他 provider 的最高真实百分比；只有余额数据时不在菜单栏伪造百分比。

## 设置界面

DeepSeek 设置区放在 provider 列表与现有 ntfy 设置之间，使用与 ntfy 一致的 `DisclosureGroup` 视觉结构：

- 标题：`DeepSeek`
- 状态：`已配置` / `未配置`
- 输入：`SecureField("DeepSeek API Key", text: ...)`
- 主操作：`保存`
- 已配置时的次要操作：`删除`
- 辅助说明：Key 只保存在本机钥匙串，App 仅在运行本地 `aiquokka` 时注入。

空白输入不能保存。保存和删除期间禁用重复操作；操作成功后清除错误。界面不提供“显示 Key”或复制按钮，减少明文暴露面。

## 错误处理

- `errSecItemNotFound`：读取表示未配置；删除视为幂等成功。
- `errSecDuplicateItem`：保存流程转为更新现有 item。
- `errSecInteractionNotAllowed`、用户拒绝或其他 OSStatus：转换为不含敏感信息的本地化错误，在 DeepSeek 设置区展示。
- Keychain 读取失败：本次 refresh 失败并保留上一次成功快照，沿用现有红色仪表盘和错误详情行为。
- DeepSeek API 返回认证或网络错误：由 `aiquokka --yml` 作为 provider error 返回，App 不自行解释或重试凭据。
- 余额字段格式无效：忽略该字段，不使整份聚合 YAML 解码失败；其他 provider 继续展示。

## 测试策略

### Keychain 与设置模型

- 内存 credential store 覆盖未配置、保存、覆盖更新、删除和读取失败。
- 保存会去除首尾空白并拒绝空值。
- 成功保存后输入草稿被清空、状态变为已配置，并请求刷新。
- 删除成功后状态变为未配置并请求刷新。
- 错误状态不包含测试 Key 明文。
- 生产 Keychain 查询使用固定 service/account，并将不存在删除视为成功；不在单元测试中写入用户真实 login keychain。

### Runner 环境注入

- 有 Key 时，执行请求包含 `DEEPSEEK_API_KEY`。
- Keychain 值覆盖继承环境中的同名变量。
- 未配置时不额外注入。
- Keychain 读取错误阻止 CLI 启动并返回可诊断错误。
- 测试 executor 只断言变量存在或等于虚构测试值，不打印环境字典。

### YAML 与展示逻辑

- DeepSeek `remaining: 110.00`、`currency: CNY` 被完整解码并格式化为 `¥110.00`。
- `used/limit` 计算有效百分比，非法或零 limit 不计算。
- 数值字符串和整数可解码；未知字段继续忽略。
- 余额型窗口不参与 highest usage、提醒和 ntfy 里程碑。
- provider 摘要优先显示可用百分比；没有百分比时显示主余额。

### 工程与人工验证

- 运行完整 `swift test`。
- 构建并 ad-hoc 签名 `dist/aiquokka.app`，验证 `codesign --verify --deep --strict`。
- 在真实 macOS login keychain 中用测试 Key 手动验证：首次保存、同一构建重启后静默读取、连续自动刷新不重复提示、删除后 provider 消失。
- 用真实 DeepSeek Key 验证 provider 出现且余额正确，验证失败时不在日志或 UI 中泄露 Key。
- 替换一次新 ad-hoc 构建，记录系统是否重新询问；无论是否询问，都不把“跨构建无提示”作为验收要求。

## 安全边界

- App 只为 DeepSeek 提供一个明确、用户主动配置的 Keychain bridge；不扫描或导入其他 shell 环境变量。
- App 不 source `.zshrc`、`.zprofile` 或其他 shell 配置。
- App 不直接调用 DeepSeek API，不拥有 token refresh、计费语义或 provider endpoint。
- 不使用允许任意 App 访问的 Keychain ACL，不使用 `security ... -A`。
- 不把真实 Key、完整环境或真实 provider YAML 加入仓库、测试、通知或日志。
- 本次接受 ad-hoc 构建跨版本可能重新授权；不在本次引入 Developer ID、notarization 或发布流程。

## 不在本次范围

- MiMo、MiniMax、Z.ai 或其他 provider 的新增凭据管理。
- 从 `~/.zshrc` 自动导入或迁移现有 DeepSeek Key。
- 修改或向上游提交 `aiquokka` Go CLI。
- DeepSeek 余额阈值提醒、消费历史、趋势图或余额不足通知。
- Touch ID、设备密码或每次读取时的用户在场认证。
- 正式签名、notarization、Mac App Store 或多设备钥匙串同步。
