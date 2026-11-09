# Agent 人物控制（0.10.0 原型）

人物控制有两种模式，任务同步、便签和天气继续独立工作：

- **自动演出**：沿用工作、休息和手动小动作。旧版状态文件默认使用此模式。
- **Agent 接管**：本地 Agent 提交关节、朝向、位置和表情目标，像素人物按这些数值运动。界面切回「自动演出」即可收回控制。

接管接口接受任意有效数值及关键帧，不要求选择「挥手」「喝水」等预设动作。当前实现采用本地控制；应用内部调用模型 API、无人值守的后台语言模型循环尚未接入。

## 在当前 Codex 对话中使用

先构建并打开包含本地控制功能的应用，在仓库根目录执行以下命令。能够在这台 Mac 上执行本地命令的 Codex Agent 也可以调用同一个 CLI；无需为这个控制接口配置模型密钥。

```sh
# 读取当前模式、姿态、数值范围和状态更新时间。
python3 scripts/workplace-agent.py status

# 或在应用界面点击「Agent 接管」。
python3 scripts/workplace-agent.py mode agent

# 数值可以是小数；未提供的字段沿用接收指令时的当前姿态。
python3 scripts/workplace-agent.py pose \
  '{"x":930,"y":250,"facing":"front","joints":{"leftShoulder":-37.25,"rightElbow":24.5},"face":{"eyes":0.4,"brows":-0.35,"mouth":0.8}}' \
  --duration 2

# 一条指令中规划数秒动作。time 从应用接收本条指令时起算，必须大于0并递增。
python3 scripts/workplace-agent.py sequence \
  '[{"time":1,"pose":{"joints":{"leftShoulder":-70,"rightShoulder":45}}},{"time":2,"pose":{"joints":{"leftElbow":85},"face":{"eyes":0.25,"mouthOpen":0.3}}},{"time":3,"pose":{"joints":{"leftShoulder":-30,"leftElbow":20},"face":{"eyes":1,"mouth":0.8,"mouthOpen":0}}}]'

# 观察反馈，再决定下一段目标；成功回执表示已接收，不表示动作已经结束。
python3 scripts/workplace-agent.py status

# 结束接管。此后 pose/sequence 会被拒绝，直到再次接管。
python3 scripts/workplace-agent.py mode automatic
```

CLI 默认使用 `~/Library/Application Support/VirtualWorkplace`。独立测试或自定义应用状态目录需要把 `--state-dir` 放在子命令前：

```sh
python3 scripts/workplace-agent.py --state-dir /absolute/test-directory status
```

Agent 可以遵循「读取当前姿态与能力 → 接管 → 规划未来2至5秒的数值目标 → 等待回执 → 采样反馈 → 再规划」的循环。CLI 的 `result.duration` 是实际过渡时长，`status.pose` 是采样姿态，`statusAgeSeconds` 可判断状态文件是否仍在刷新。残留的旧状态文件不代表应用在线。

当前对话中的 Agent 只有在获得执行机会并调用本地工具时才会驱动人物；接管不会额外启动一个持续推理的模型。开发机上的 Codex 会话能显示在工位里，也不代表它已获得这台 Mac 的文件或命令执行权限。当前 CLI 应在 Mac 本地执行，原型不自动建立远程控制通道。

## 可以控制什么

关节以度为单位。四肢垂下对应0度，正角度指向画面右侧、负角度指向左侧；肘、腕、膝角度相对父肢段。躯干与头部参数表示倾斜角度。

| JSON 关节名 | 可用范围 |
| --- | --- |
| `torsoLean` | −30° 至30° |
| `headTilt` | −35° 至35° |
| `leftShoulder`、`rightShoulder` | −165° 至165° |
| `leftElbow`、`rightElbow` | −155° 至155° |
| `leftWrist`、`rightWrist` | −90° 至90° |
| `leftHip`、`rightHip` | −70° 至70° |
| `leftKnee`、`rightKnee` | −130° 至130° |

| `face` 字段 | 可用范围与含义 |
| --- | --- |
| `eyes` | 0至1，闭眼至睁眼 |
| `brows` | −1至1，眉形偏移与倾斜 |
| `mouth` | −1至1，嘴角由下弯至上扬 |
| `mouthOpen` | 0至1，张嘴程度 |

`facing` 可取 `front`、`back`、`left`、`right`。正面和侧面可以看到表情；背面保留后脑，不在后脑绘制人脸。

`x`、`y` 使用1672×941房间画稿的坐标，原点在左下角；它们表示人物脚下的地面锚点。默认位置为 `(835, 270)`，允许范围为 `x:460…1260`、`y:190…310`。根位置在两点之间先沿X、再沿Y移动，移动期间朝向跟随行进方向，落点恢复指定朝向。修改Y表示在地面上前后移动，不表示跳跃高度。

## 轨迹与本地接口

- `pose` 创建一段平滑过渡，`--duration` 默认1.5秒，可请求大于0、不超过15秒的时长。过快的请求会延长至满足速度限制的最短时间；回执给出实际时长。
- `sequence` 接受1至31个目标关键帧。应用补入接收时的当前姿态，内部最多32帧、总长不超过15秒。各帧是部分姿态补丁，后面的帧沿用前面帧未修改的目标。
- 关节角速度上限为360°/秒，根位置沿折线路径的速度上限为160画稿单位/秒。序列中超过速度上限的帧会被拒绝，整段保持原样；序列不会自动重排时钟。
- 新指令替换当前轨迹，不追加无限队列。轨迹结束后保持最后姿态，直到下一条指令或用户切换模式。
- 桌面与屏保按同一条绝对时间轨迹取样。屏保只读应用写出的快照，不接收指令，也不调用模型。系统「减少动态效果」开启时，以最终目标的静态姿态表达指令。

CLI 使用本地单槽信箱：`agent-command.json` 写入指令，`agent-result.json` 返回对应UUID回执，`agent-status.json` 提供当前姿态与数值能力。应用复用已有每秒一次的心跳读取信箱，没有新增网络监听器或天气/动画计时器。每份控制文件上限64KiB，指令带短时效和去重标识；CLI 会锁住当前发送过程，并最多等待8秒回执。

接管范围只有人物。控制状态不暴露便签、聊天正文或真实任务内容；控制指令也不会启动 Codex 任务、发送消息、审批请求或执行任意脚本。既有 Codex 状态观察器仍按原来的只读方式工作。

## 当前边界与检查

这版是受角度、速度与地面范围约束的二维关节控制，不是物理模拟或手脚目标的逆运动学（IK）求解。模型负责规划腿部运动，移动根位置本身不会自动生成走路步态；也不保证身体各部分或家具之间完全避免穿插。需要自然行走时，Agent 应同时给出位置与抬腿、屈膝的关键帧，并检查反馈。

验证命令：

```sh
./scripts/test-agent-puppet.sh
./scripts/test-agent-control.sh
./scripts/test-agent-cli.sh
```

当前检查覆盖共享数值模型1005项、本地协议1099项，以及真实CLI→信箱→StateStore链路27项；使用隔离目录，不访问个人状态。数值检查不能代替人物画面、实际系统屏保和长时间运行的验收。
