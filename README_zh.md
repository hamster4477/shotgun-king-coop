# 霰弹国王合作模式

**[English](README.md) | 简体中文**

《**Shotgun King: The Final Checkmate／霰弹国王**》的社区合作模组。与伙伴分别操控**黑王和黑骑士**，一起挑战**王座、无尽与剿灭模式**，支持本地合作和局域网合作。

[下载模组](https://github.com/hamster4477/shotgun-king-coop/releases) · [详细游玩说明](onlinecoop/README_zh.md) · [反馈问题](https://github.com/hamster4477/shotgun-king-coop/issues)

## 主要功能

- 本地与局域网合作共用卡牌、战斗规则和战役内容。
- 联机时，**1P 操控黑王，2P 操控黑骑士**；双方分别运行游戏。
- 在游戏内创建房间、复制连接码和加入房间。
- 支持可互通的局域网、虚拟组网，以及 FRP 等 TCP 端口映射方式。
- 双方可标记棋盘格子；2P 可发送选卡建议，由 1P 最终确认。
- 同步棋盘动画，可切换采集帧率上限与动画播放模式。
- 提供简体中文与英文界面提示。

此发行版使用局域网／TCP 联机，不包含实验性的 Steam P2P 功能。仍可配置从 Steam 启动模组。

## 安装与开始游戏

**运行要求：**Windows、已安装的《霰弹国王》；联机双方使用相同版本的模组。本项目不包含游戏本体。

1. 从 [Releases](https://github.com/hamster4477/shotgun-king-coop/releases) 下载玩家 ZIP。如果尚未发布下载附件，可按下方说明自行打包。
2. 完全退出游戏，将 ZIP 内的 `onlinecoop` 文件夹放进游戏的 `mods` 文件夹。
3. 启用 `onlinecoop`，停用旧 `coop` 模组。更新前备份存档，不要同时启用两者。
4. 局域网游玩请双击模组内的 **`Start Online Co-op Multi Core.vbs`**。需要单核兼容的电脑改用 **`Start Online Co-op.vbs`**。玩家无需安装 Python。
5. 双方从“游玩”进入相同的局域网战役。房主创建房间并复制连接码，另一方粘贴后点击“加入”。

本地合作无需启动网络助手。希望直接从 Steam 启动局域网模式，可先运行一次 **`Configure Steam Launch.vbs`**。Steam 启动配置、工坊路径、虚拟组网与 FRP 设置见[详细游玩说明](onlinecoop/README_zh.md)。

## 常用操作

| 操作 | 功能 |
| --- | --- |
| **E**，随后点击格子 | 标记棋盘格子。 |
| **F6** | 切换采集上限：10／15／20／30／45／60 帧，默认 30。 |
| **F7** | 切换完整动画与追帧模式。 |
| **2P 点击一组选卡** | 向 1P 发送选卡建议。 |
| **2P 按 Tab** | 跳过黑骑士行动。 |

默认使用完整动画模式，保留采集到的动画帧；网络较慢时可能需要等待缓冲。追帧模式允许跳过旧画面以减少延迟。两种模式都不能消除网络延迟，切换会在当前动画播放完成后生效。

## 问题反馈与已知限制

模组仍在持续测试。断线后目前需要双方重新建立连接，暂不支持自动重连。同一热点可能隔离设备；虚拟组网或端口映射工具需要另外配置。部分原版后处理效果与音效尚未在 2P 端还原。

反馈问题时，请提供模组版本、游戏版本、战役、玩家角色、楼层、最后操作、动画播放模式和复现步骤，并附相关截图或日志片段。公开日志前请删除房间密钥、连接码和个人信息。

## 开发与打包

| 路径 | 内容 |
| --- | --- |
| `onlinecoop/shared/` | 本地与在线共用的卡牌、战斗规则。 |
| `onlinecoop/campaigns/` | 各战役的行为。 |
| `onlinecoop/adapters/` | 本地与网络模式接入。 |
| `onlinecoop/net_*.lua` | 同步、动画回放和客户端显示。 |
| `onlinecoop/lan/LanTransport.cs` | 局域网传输源码。 |
| `onlinecoop/tests/` | 大厅与通信助手的专项检查。 |
| `tools/` | 打包脚本及运行文件清单。 |

使用 Python 3，在仓库根目录执行：

```sh
python tools/package.py
```

玩家 ZIP 会生成在 `dist/` 目录。打包脚本使用明确的文件清单，排除测试与运行数据，并拒绝覆盖已有压缩包。

在 Windows 上运行附带检查：

```sh
python -m pip install -r onlinecoop/tests/requirements.txt
python onlinecoop/tests/test_game_lobby.py
python onlinecoop/tests/test_game_broker.py
```

通信助手测试会启动临时本机回环连接，并在结束时关闭。上述检查不能替代实际游玩测试。修改玩法时请优先调整共享规则，保持本地与在线模式一致。

## 作者与权利说明

模组作者：**liber H :Aeon**。《Shotgun King: The Final Checkmate》由 **PUNKCAKE Délicieux** 开发。本项目为非官方社区模组，需要原版游戏才能运行。

本项目目前未授予统一的开源许可。如需复用或再分发项目代码、素材，请联系作者。第三方内容的权利归属和适用条款保持不变。
