# AGENTS.md

## 项目范围

- 本仓库是 Voice Stick：M5Stack StickS3 蓝牙按键语音输入固件与 macOS 客户端。
- 未提交的工作区改动不代表已经发布、安装到 macOS、烧录到设备或完成真实硬件验收。
- Git 提交信息使用中文；只暂存当前任务负责的文件或具体差异，默认不推送。
- 正式桌面版本统一使用 Apple 兼容的三段数值版本号 `主版本.次版本.修订号`。根目录 `VERSION`、macOS `Info.plist` 的 `CFBundleShortVersionString` 与 `CFBundleVersion`、菜单显示和正式标签 `v<VERSION>` 必须一致；从旧版 `0.3.4.8` 迁移后的下一版为 `0.3.5`。每次提交并推送包含面向用户的功能更新的代码前，将第三段加一。调试构建若需区分轮次，只在产物名称或记录中添加调试字母，不写入 Apple 版本字段，也不将调试构建表述为正式发布。提交前只做静态检查，不在本地重新打包、替换或启动应用；推送 `main` 后由 `macOS ARM64 Package` GitHub Actions 构建测试包，检查云端任务与产物。测试包未经过 Developer ID 签名、公证，也未自动安装到本机，不能表述为正式分发或本机运行版本。正式发布另由 fork 的 macOS 发布工作流在匹配的版本标签上完成签名、公证和 GitHub Release，不触发固件发布。
- 重构或更新安装流程必须先按 `/Applications/VoiceStick.app/Contents/MacOS/VoiceStickApp` 可执行进程确认旧版已退出，验证新包签名与可启动性后再启动新版本，并在交付时报告实际运行的版本与架构。`/Applications` 只保留当前 `VoiceStick.app`，不得保存本地备份；如需可恢复备份，放入仓库 `build/local-app-backups/`。
- 本机已配置 `Developer ID Application: Zhejiang Zhongwei Safety Technology Co., LTD (322V86ZQ9K)`；后续本地安装和发布优先使用此固定身份签名，不得在可用时回退到 ad-hoc 签名。

## 代码与项目知识同步

- 代码能力、用户交互、蓝牙协议、macOS 输入注入、配置、测试或构建边界发生变化时，同一任务同步更新项目知识。
- 项目知识库位于 `/Volumes/work/wiki/wiki`，项目目录为 `/Volumes/work/wiki/wiki/10 项目/Voice Stick`，入口为 `/Volumes/work/wiki/wiki/10 项目/Voice Stick/Voice Stick.md`。
- 功能文档写入 `10 功能模块`，技术实现、配置、测试与构建证据写入 `20 技术实现`；不要在两处复制同一正文。
- 仅将已提交且验证的源码标记为最终 `source_ref`；未提交代码写为“工作区开发中”。
- 源码仓库与知识库分别检查、验证、暂存和提交；不混入、覆盖或回滚既有无关改动。
- 不写入 API Key、Token、私钥、Cookie 或其他未脱敏敏感数据。
