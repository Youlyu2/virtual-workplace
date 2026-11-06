# 版本管理与贡献

公开仓库从整理后的0.9.2源码快照开始，包含源码、素材、构建脚本、测试及说明。开发期间的个人操作记录、真实会话信息和原本地Git历史不属于公开快照。不要假定公开仓库存在开发阶段使用过的提交号或版本标签。

构建目录、运行状态、日志和本地环境文件由 `.gitignore` 排除。分享修改前仍应检查新增文件和截图中是否含个人内容。

## 查看与保存修改

```sh
git status
git diff
git log --oneline --decorate
```

完成一项修改后，运行相关检查，再选择需要提交的文件：

```sh
git add Sources Tests scripts Resources docs README.md
git diff --cached --stat
git commit -m "Describe the resulting behavior"
```

提交应说明解决的问题、修改后的行为、验证方式和仍存在的限制。请使用通用模拟数据编写测试或报告问题。

## 回退与独立构建

使用 `git revert <commit>` 为已提交修改创建撤回提交。发生冲突时可用 `git revert --abort` 取消。不要撤回公开仓库的初始快照提交，以免删除整个项目。

如需单独查看或构建某个已存在的标签，可以使用Git worktree：

```sh
git worktree add --detach ../virtual-workplace-review <tag-or-commit>
```

将占位参数替换为本仓库实际存在的标签或提交。Git只管理源码；已经安装的应用、屏保与个人待办不会随源码回退。要运行回退后的版本，需要退出应用，重新构建和安装。

## 许可

贡献前请阅读仓库根目录的 [LICENSE](../LICENSE) 和 [素材许可说明](../ASSET_LICENSE.md)。新增第三方资源时应同时提供来源和适用的许可条件。

`v0.9.4` 将天气改为独立随机轮换，保留手动固定和双屏同步，待办等待时长不再影响天气。
