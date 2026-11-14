# 开发说明

[返回玩家首页](README_zh.md) | [English](DEVELOPMENT.md)

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

打包前先运行 `python tools/check_release.py`。如要核对本机运行版，可运行
`python tools/check_release.py --compare "游戏目录/mods/onlinecoop"`；替换为实际路径。
该检查会报告缺失文件、非法清单条目及两个副本的内容差异。不要用旧源码覆盖已修复的运行版。
维护交接见 [MAINTENANCE_zh.md](MAINTENANCE_zh.md)，收尾审查见 [FINAL_AUDIT_zh.md](FINAL_AUDIT_zh.md)。

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
