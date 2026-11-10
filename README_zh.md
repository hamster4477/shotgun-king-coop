# 霰弹国王合作模式

**[English](README.md) | 简体中文**

一个人拿起霰弹枪，另一个人挥起骑士的刀锋。

这是《**Shotgun King: The Final Checkmate／霰弹国王**》的双人合作模组。与朋友分别操控黑王和黑骑士，相互掩护、配合击杀，一起挑战王座、无尽与剿灭模式。支持本地合作与局域网联机，并加入围绕双人配合设计的新卡牌和战斗机制。

**[在 Steam 创意工坊订阅](https://steamcommunity.com/sharedfiles/filedetails/?id=3833493529)** · **[下载模组](https://github.com/hamster4477/shotgun-king-coop/releases)** · [详细安装与联机说明](onlinecoop/README_zh.md) · [反馈问题](https://github.com/hamster4477/shotgun-king-coop/issues)

## 下载前

- 需要已安装的《霰弹国王》。这是模组，不包含游戏本体。
- 联机启动工具适用于 Windows；双方分别运行游戏，并安装相同版本的模组。
- 支持局域网、虚拟组网和 TCP 内网穿透。异地游玩需要自行配置组网或穿透工具。
- 支持简体中文和英文。

## 安装

订阅安装请使用上方工坊链接，再按[工坊安装步骤](onlinecoop/README_zh.md#steam-创意工坊安装)配置。手动安装 ZIP 的步骤如下：

1. 从下载页的 **Assets** 中下载模组发行 ZIP，选择模组附件，而不是 GitHub 自动生成的 **Source code** 源码压缩包。
2. 完全退出游戏，将压缩包内的 `onlinecoop` 文件夹放入游戏安装目录的 `mods` 文件夹。
3. 启用 `onlinecoop`。如果安装过旧版 `coop`，请将其停用，避免两份合作模组同时运行。

安装后的路径应为：

```text
Shotgun King The Final Checkmate/
└─ mods/
   └─ onlinecoop/
      ├─ info.lua
      ├─ script.lua
      └─ …
```

更新前请备份存档。联机双方应完整更新到同一版本，不要混用不同版本的文件。

## 与朋友联机

通常使用模组文件夹里的 **`Start Online Co-op Multi Core.vbs`** 启动。房主负责黑王，加入者负责黑骑士；房主将连接码发给朋友，双方使用相同战役开始游戏。

希望从 Steam 直接启动，可运行一次 **`Configure Steam Launch.vbs`** 完成配置。本地合作无需启动联机助手。

具体连接步骤、Steam 启动配置和 FRP 设置，请查看[详细说明](onlinecoop/README_zh.md)。

## 常见问题

**连接不上怎么办？** 先确认双方版本相同、房主地址可达，以及组网或穿透工具已连接。同一个热点也可能禁止设备互相访问。

**联机画面等待较久怎么办？** 按 **F6** 降低传输帧率上限，或按 **F7** 切换到追帧模式。默认的完整动画模式会优先保留动画，网络较慢时可能需要等待缓冲。

**断线后能继续吗？** 暂不支持自动重连，需要双方重新建立连接。

**启动或游玩时崩溃怎么办？** 可以尝试单核兼容启动文件 **`Start Online Co-op.vbs`**；它是兼容性绕过办法，不保证解决所有崩溃。

模组仍在持续测试，部分画面效果和音效在 2P 端可能与房主不同。遇到问题欢迎[提交反馈](https://github.com/hamster4477/shotgun-king-coop/issues)，说明版本、模式、玩家角色、楼层与发生前的操作，并附截图或相关日志。公开日志前请删除连接码、房间密钥和个人信息。

如果希望私下反馈，也可以发邮件到 [hamster4477@qq.com](mailto:hamster4477@qq.com)。

---

模组作者：**liber H :Aeon**。原作由 **PUNKCAKE Délicieux** 开发。本项目为非官方社区模组。

[开发与源码说明](DEVELOPMENT_zh.md)
