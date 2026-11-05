# 参与贡献

欢迎通过 Issue 报告问题、讨论设计，或提交 Pull Request。

## 本地开发

- Apple Silicon Mac、macOS 26、Apple Command Line Tools。
- 执行 `./scripts/build.sh` 后打开 `build/虚拟工位.app`。
- 使用「模拟」或 `--render` 示例数据验证画面，无需运行真实 Codex 任务。
- 核心检查：`./scripts/test.sh`、`./scripts/test-pending-notes.sh`、`./scripts/test-pending-inbox.sh`、`./scripts/test-world-settings.sh`。
- 只运行与修改有关的其他检查；真实系统屏保、锁屏和多显示器应单独记录验收范围。

## 提交说明

说明解决的问题、可见行为和验证方法。界面修改可附使用模拟数据的图片。

不要提交个人待办、真实会话日志、凭据、本机路径或工作截图。报告 Codex 兼容问题时，请提供应用版本、macOS 版本和脱敏后的最小复现。

贡献代码与美术素材时，应具有相应授权，并接受本项目的 MIT 许可；外部素材须补充来源与许可声明。
