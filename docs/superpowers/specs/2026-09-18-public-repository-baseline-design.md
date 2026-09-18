# aiquokka-menubar 公开仓库基线设计

## 目标

将当前本地 `aikuokka_mac` 工程整理为可公开发布的 GitHub 仓库 `sheneyan/aiquokka-menubar`。公开基线应让首次访问者能够理解项目用途、与上游 `aiquokka` 的关系、安装和验证方法、数据与凭据边界，以及当前功能和限制。

本次保留完整 Git 历史，不重写、不压缩已有提交。公开前必须确认当前树和历史中不包含密钥、令牌或真实 provider 输出等敏感信息；如果发现敏感信息，必须先单独评估并清理历史，不能直接推送。

## 方案选择

采用“保留开发历史，整理当前公开树”的方案：

- 保留现有提交历史，使项目演进、设计决策和实现过程可追溯。
- 从当前树移除只服务于实施过程的 `docs/superpowers/plans/`，避免把逐步执行清单当作长期文档。
- 将仍有长期价值的设计规格整理到 `docs/design/`，使用面向公开读者的稳定路径。
- 不将本地研究笔记 `docs/research/` 纳入公开仓库；它当前未被跟踪，整理过程继续保持未跟踪状态。

不采用以下方案：

- 不创建无历史的全新初始提交。这样虽然树更简洁，但会丢失现有设计和实现脉络。
- 不原样公开全部内部计划和研究笔记。它们包含实现时上下文、机器路径或尚未形成产品承诺的探索内容，会提高维护成本并模糊项目边界。

## 仓库身份与上游关系

公开仓库名称为 `aiquokka-menubar`，GitHub 地址为 `https://github.com/sheneyan/aiquokka-menubar`。项目定位是一个非官方、原生 macOS 菜单栏伴侣，通过用户本机安装的 `aiquokka --yml` 读取配额与余额数据。

README 必须明确：

- 本项目不是上游 `aiquokka` 官方仓库，也不隶属于上游维护者。
- 上游 `aiquokka` 是运行时依赖，用户需要自行安装并完成其支持的 provider 配置。
- 本项目不复制上游 Go provider 实现，不直接接管其登录流程或远端 API 请求。
- 上游项目使用链接和文字署名说明，不把上游作者的版权声明写成本仓库源码的版权归属。

App 的 bundle identifier 从本地占位值 `com.local.aiquokka-menubar` 改为公开且稳定的 `io.github.sheneyan.aiquokka-menubar`。构建脚本、Info.plist、文档和后续 Keychain service 等所有身份相关引用必须保持一致；公开基线完成后不应残留旧 bundle identifier，历史提交除外。

## 公开文档结构

### README.md

README 以当前已经实现并验证的功能为准，至少覆盖：

- 项目定位、非官方声明和上游链接。
- 菜单栏总览、详情视图、自动与手动刷新、provider 错误状态、显示模式、使用率提醒和可选 ntfy 通知等现有功能。
- 支持条件：macOS 13 或更高版本、本机 `aiquokka` CLI，以及源码构建所需的 Swift 6 工具链。
- App 查找 `aiquokka` 可执行文件的路径规则，并说明 GUI App 不会自动读取交互式 shell 的 `~/.zshrc`。
- 源码构建、测试、打包、安装与卸载步骤；命令必须和仓库现有脚本及 Swift Package 实际入口一致。
- 凭据与隐私边界：当前由本机 CLI 管理或读取 provider 凭据；App 解析 CLI 输出，不上传使用数据，只有用户启用 ntfy 时才向其配置的服务器发送里程碑通知。
- 已知限制和发布状态，包括 ad-hoc 签名及尚未提供正式 notarization 的事实。
- 一个稳定的截图引用位置；若公开时尚无合格截图，可先省略图片而不能提交失效占位链接。

DeepSeek Keychain 余额支持当前只有批准的设计规格，尚未实现，因此 README 不得把它列为已发布功能。将来实现并验证后再更新功能列表和凭据说明。

### LICENSE

仓库根目录使用标准 MIT License，版权行为：

```text
Copyright (c) 2026 Yiyan Shen
```

MIT 授权覆盖本仓库作者拥有权利的源码和文档，不自动改变上游项目、第三方依赖、provider 服务、用户数据或品牌的权利状态。

### THIRD_PARTY_NOTICES.md

增加第三方说明文件，记录随源码依赖或在构建中使用的组件、其许可证和官方来源。至少核实 Swift Package 依赖 Yams 的许可证；只引用权威仓库或许可证文件，不凭印象填写。

运行时外部依赖 `aiquokka` 在 README 中单独说明。除非本仓库实际分发其代码或二进制，不将其误写为本仓库打包的第三方组件。

### docs/design/

将现有、仍有长期解释价值的设计规格从 `docs/superpowers/specs/` 移入 `docs/design/`。迁移时：

- 保留设计内容和原始日期，修正失效的内部路径与已变更的公开身份。
- 明确区分“已经实现”“已批准但未实现”和“历史设计”。
- 删除当前树中的 `docs/superpowers/plans/`。
- 本公开基线规格本身也移入 `docs/design/`，使当前树不再依赖内部工作流目录命名。

因为保留完整 Git 历史，被删除的计划和旧机器路径仍能从历史提交中看到。这是已接受的可追溯性结果，但只适用于非敏感内容；任何真实秘密都必须在推送前单独清理历史。

## 仓库卫生与敏感信息审计

公开前对当前树和完整 Git 历史执行审计，覆盖：

- API key、OAuth token、authorization header、私钥和常见 provider 凭据格式。
- 真实 provider YAML/JSON 响应、账号标识、余额、配额、邮箱及通知 endpoint。
- `/Users/...` 等本机绝对路径和只对作者机器有效的命令。
- 构建产物、`.DS_Store`、临时文件、研究草稿和未计划发布的日志。

敏感信息扫描使用可获得的专用 secret scanner；若本机没有该工具，使用 Git 内容遍历配合有针对性的模式扫描，并在交付报告中说明覆盖范围和限制。检测结果按风险处理：

- 真正的秘密或个人数据：停止推送，轮换凭据，并制定历史清理方案。
- 本机路径或非敏感开发痕迹：修正当前公开文档；保留历史是已接受的选择，但在结果中明确披露。
- 测试 fixture 中的虚构 token：确认其明显为测试值且不会被误认为真实凭据。

`.gitignore` 增加 `.DS_Store` 等必要规则。现有未跟踪的 `docs/research/` 不删除、不纳入提交；整理时不得误伤用户的本地研究资料。

## 构建与发布验证

推送前按以下层级验证：

1. 文档命令、文件路径、链接和 bundle identifier 与当前树一致。
2. `swift test` 全量通过。
3. 使用仓库现有流程构建 `dist/aiquokka.app`，进行 ad-hoc 签名，并通过 `codesign --verify --deep --strict`。
4. 对构建产物检查 Info.plist，确认 bundle identifier 为 `io.github.sheneyan.aiquokka-menubar` 且菜单栏 App 配置仍有效。
5. 检查 `git status`，公开化提交只包含计划内文件；未跟踪研究资料保持不变。
6. 在添加远端后核对 GitHub 仓库为空、目标 URL 正确且为 public，再推送 `main`。
7. 推送后读取远端引用，报告本地与 GitHub 的 commit SHA 是否一致。

添加 `origin` 和首次推送是最后的发布步骤，不与文档整理混在一起。推送前的本地验证失败时，不得发布半完成状态。

## 错误与风险处理

- README 命令与现有脚本不一致：以可执行验证结果为准，修正文档后重新验证。
- 第三方许可证不明确：不猜测、不省略，查阅官方许可证文件；无法确认时阻止公开发布。
- 历史扫描发现秘密：立即停止推送；凭据轮换和历史重写必须作为单独、可审查的操作处理。
- GitHub 远端非空或默认分支状态变化：不强推，先比较远端内容并重新决定整合方案。
- bundle identifier 变化影响 Keychain：当前 DeepSeek 功能尚未实现，因此不迁移现有 Keychain item；后续实现直接使用新的公开身份和 service 名称。
- ad-hoc 签名导致新构建再次请求钥匙串授权：这是已接受的本地发布限制，README 应如实说明，不承诺跨构建保持授权。

## 验收标准

- 根目录包含准确的 `README.md`、MIT `LICENSE` 和经核实的 `THIRD_PARTY_NOTICES.md`。
- 当前树不再包含 `docs/superpowers/plans/`，长期设计文档位于 `docs/design/`。
- `.DS_Store` 被忽略，未跟踪的 `docs/research/` 没有被删除或提交。
- 当前树不含旧的 `com.local.aiquokka-menubar` 身份引用；已构建 App 使用新的 bundle identifier。
- README 只描述已实现功能，明确 DeepSeek Keychain 支持尚未发布。
- 当前树和完整历史完成敏感信息审计，没有未处置的真实秘密或个人数据。
- 全量测试、App 构建和签名验证通过。
- 首次推送后，本地 `main` 与 GitHub `main` 指向同一提交，且没有使用强制推送。

## 不在本次范围

- 实现 DeepSeek Keychain、余额解析或其他 provider 接入。
- 新增 MiMo、Kimi、Z.ai、MiniMax 等 provider。
- Developer ID 签名、notarization、自动更新、GitHub Releases 或 CI/CD。
- 重写或压缩已有 Git 历史，除非敏感信息审计证明这是发布所必需的。
- 删除或公开本地 `docs/research/` 内容。
- 修改上游 `aiquokka` 或向其提交 pull request。
