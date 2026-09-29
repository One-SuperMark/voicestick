# AGENTS.md

## 项目范围

- 本仓库是 Voice Stick：M5Stack StickS3 蓝牙按键语音输入固件与 macOS 客户端。
- 未提交的工作区改动不代表已经发布、安装到 macOS、烧录到设备或完成真实硬件验收。
- Git 提交信息使用中文；只暂存当前任务负责的文件或具体差异，默认不推送。
- 正式桌面版本统一使用 Apple 兼容的三段数值版本号 `主版本.次版本.修订号`。根目录 `VERSION`、macOS `Info.plist` 的 `CFBundleShortVersionString` 与 `CFBundleVersion`、正式标签 `v<VERSION>` 必须一致；从旧版 `0.3.4.8` 迁移后的下一版为 `0.3.5`。每次提交并推送包含面向用户的功能更新的代码前，将第三段加一。正式提交前做静态检查；推送 `main` 后由 `macOS ARM64 Package` GitHub Actions 构建测试包，检查云端任务与产物。测试包未经过 Developer ID 签名、公证，也未自动安装到本机，不能表述为正式分发或本机运行版本。正式发布另由 fork 的 macOS 发布工作流在匹配的版本标签上完成签名、公证和 GitHub Release，不触发固件发布。
- 本机开发验证使用 `scripts/build-macos.sh --development`，显示版本为四段数值，例如 `0.3.6.1`；每次成功本地构建递增第四段，正式三段基线改变时从 `.1` 开始。开发号只写入产物的 `VoiceStickDevelopmentVersion` 元数据和产物名称，不修改源 `VERSION` 或 Apple 两个版本字段，不进入正式 appcast。检查更新窗口与设置窗口标题显示四段号及“开发版”标识；正式 `--release` 包仍显示三段，正式更新排序不使用本机第四段。不得恢复已删除的“当前版本”菜单，也不得把开发包表述为正式发布。
- 按用户最新要求，桌面客户端修改后必须更新本机 App，不能仅停在源码或云端产物。未获提交、推送或正式发布授权时，完成静态检查后构建固定 Developer ID 签名的 ARM64 开发包并安装，Apple 版本字段保留当前三段基线、用户可见版本显示四段开发号，在记录中区分本机包与公开正式包；不得因此自动提交、推送、打标签或发布。已获正式发布授权时，优先安装该次已验证的正式产物。安装验收须核对开发显示号、构建与已安装二进制哈希、实际运行路径及菜单变化，本地签名不等于 Apple 公证或 Sparkle 跨版本升级通过。
- 重构或更新安装流程必须先按 `/Applications/VoiceStick.app/Contents/MacOS/VoiceStickApp` 可执行进程确认旧版已退出，验证新包签名与可启动性后再启动新版本，并在交付时报告实际运行的版本与架构。`/Applications` 只保留当前 `VoiceStick.app`，不得保存本地备份；如需可恢复备份，放入仓库 `build/local-app-backups/`。
- 本机已配置 `Developer ID Application: Zhejiang Zhongwei Safety Technology Co., LTD (322V86ZQ9K)`；后续本地安装和发布优先使用此固定身份签名，不得在可用时回退到 ad-hoc 签名。

## 代码与项目知识同步

- 代码能力、用户交互、蓝牙协议、macOS 输入注入、配置、测试或构建边界发生变化时，同一任务同步更新项目知识。
- 项目知识库位于 `/Volumes/work/wiki/wiki`，项目目录为 `/Volumes/work/wiki/wiki/10 项目/Voice Stick`，入口为 `/Volumes/work/wiki/wiki/10 项目/Voice Stick/Voice Stick.md`。
- 功能文档写入 `10 功能模块`，技术实现、配置、测试与构建证据写入 `20 技术实现`；不要在两处复制同一正文。
- 仅将已提交且验证的源码标记为最终 `source_ref`；未提交代码写为“工作区开发中”。
- 源码仓库与知识库分别检查、验证、暂存和提交；不混入、覆盖或回滚既有无关改动。
- 不写入 API Key、Token、私钥、Cookie 或其他未脱敏敏感数据。
