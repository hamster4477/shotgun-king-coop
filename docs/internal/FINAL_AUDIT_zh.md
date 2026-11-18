# 发布前收尾审查

日期：2026-11-18（替代 2026-11-14 那版的范围说明）。供作者与后续维护者使用；玩家说明见 README_zh.md。

本次核对代码、副本与打包清单，并**完成了两台电脑的真实联机测试**（房主本机 + 客机通过 Steam 工坊订阅）。测试中发现的问题均已修复并单独提交。没有完整重玩所有模式、隐藏 Boss 与全部结局组合，因此仍不能据此宣称无 Bug；残留的未知项列在文末。

## 两台电脑实测发现并修复的问题

按发现顺序：

| 现象 | 根因 | 修复 |
| --- | --- | --- |
| 客机掉线后游戏直接退出 | `net_view.lua:625` 索引了早已被删除的 `zh`/`en` 文案表 | 恢复两张分阶段文案表，断线只显示横幅不再崩溃 |
| 客机看不到炮灰掉落士兵灵魂 | 快照把"空槽"和"士兵灵魂（id 0）"编码成同一个值 | 灵魂记录增加"是否已填充"字段，协议升至 `unified72lan2` |
| 房主选亚历山大，客机顶栏显示马克达 | 客机武器图标行号少了 `+1`，取到上一把武器 | 改为与原生一致的 `(weapons_index+1)*16` |
| 回合卡住、双方都无法操作，F5 无效 | `coop_king_move_input_locked` 无释放路径 | 3 秒静默后自动释放；F5 也兼作手动解锁 |
| 比武礼节额外行动后卡死 | 国王落在刚被击杀的骑士格，白军回合握手永不推进 | 45 帧后重发 `new_turn`；6 秒兜底清标志 |
| 装额外模组后联机文件写进别人的目录 | SUGAR 相对路径按**最后加载**的模组解析 | 本模组改为最后加载（`priority_hint=-4`） |
| 装了 Glacies Module Terminal 后联机初始化在别的模式里跑 | 该前置会扫描所有模组的 `start` / `on_empty` 并重放 | 两个函数加 `mode.id=="coop"` 守卫与同帧去重 |

诊断手段是本次新增的：`[COOP STUCK Ns]` 自动快照所有挂起标志，`[COOP UNSTICK]` 记录自动恢复，`[CLIP WAIT]` 记录片段等待进度。定位卡死时先看这几行，比读代码快。

## 源码与发布状态

1. **三份源码不一致的问题已解决。** 之前仓库 `main`、作者本机运行版、发布副本内容不同（本机是拆分 `coop_install_*_hooks` 并清理了逐调用日志的重构版，仓库仍是旧版）。现已合并为一版：5,850 行、10 处 `if _log`，仓库与本机哈希一致。
2. **版本号统一为 v0.73.0**，发布资产 `coop-unified-r73.zip`（81 文件）。之前 README 写 `r72c`、`package.py` 产出 `r72c`、release 资产是 `r72d`、模组内 README 写 "Unified 72 LAN 1"，玩家无法判断当前版本；旧编号现在只保留在 `VERSION_HISTORY_zh.md` 作为历史。
3. **补上 MIT 许可证**（`LICENSE`），并在其中声明游戏本体与原始素材版权归 PUNKCAKE Delicieux。
4. **公开包已移除 Steam P2P 实验运行库**，`steam-p2p/` 目录与开发清单删除，`check_release.py` 现在对任何 `steam-p2p/` 路径直接报错。公开包稳定为 81 项。
5. **内部文档移入 `docs/internal/`**，根目录只保留玩家需要看的说明。
6. **新增 Issue 模板与自动检查**：`.github/ISSUE_TEMPLATE/bug_report.yml` 要求填写版本、角色、战役、楼层与日志片段；`.github/workflows/tests.yml` 在每次 push 与 PR 上运行发布清单与 Lua 级测试。

## 验证记录

| 检查 | 本次结果与范围 |
| --- | --- |
| 两台电脑实测 | 房主本机 + 客机（Steam 工坊订阅）。覆盖：建立房间与加入、开局选武器段位、逐层推进、骑士死亡与复活、选卡换层、掉线、卡死恢复。发现的问题见上表。 |
| `test_game_lobby.py` | 通过；隐藏 `string`/`math` 环境下的多行解析、分页、上限、清空复位、长按退格。 |
| `test_game_broker.py` | 通过（仅本地）；真实本机回环辅助进程、发现与过期、网卡记忆、端口冲突、TCP 转发、握手、取消与重新创房。CI 中跳过，因为需要 Windows 回环。 |
| `test_playback.py`、`test_playback_network.py`、`test_playback_choice_watchdog.py` | 通过；长动画、网络抖动、短时断流、尾帧确认，以及选择框优先级看门狗与 F5 兜底。 |
| `test_transport_limit.py` | 三个副本均通过；覆盖上限前的最后一条、越限断连、错误锁定与新会话归零。 |
| `test_knight_health_view.py`、`test_story_captions.py` | 通过；血量显示与字幕专项回归。测试桩已补齐 `append`/`prepend`，模块级钩子不再导致该测试失败。 |
| Lua 语法 | 46 个文件全部可编译。 |
| 发布清单 | 仓库与工坊暂存副本 81 项内容一致；ZIP 81 条目、CRC 校验通过。 |

复测命令：

```text
python -m pip install -r onlinecoop/tests/requirements.txt
python onlinecoop/tests/test_game_lobby.py
python onlinecoop/tests/test_playback.py
python tools/check_release.py
python tools/check_release.py --compare "实际游戏目录/mods/onlinecoop"
python tools/package.py
```

## 仍未验证或未解决

- **蓄力第二圈戳击的联机表现**：本地与单机已测，联机下的镜像与确认流程未实测；如果客机看不到第二圈格子，先检查两边的 `ONLINE_BUILD` 是否一致（当前 `unified72lan3`）。协议不一致时握手会直接拒绝，不会静默出错。
- **原生游戏异常退出没有明确提示**：`Start-OnlineGame.ps1` 在 `$game.WaitForExit()` 后未检查或传递退出码，VBS 只判断 PowerShell 返回值。原生进程非零退出时可能只表现为 Steam 恢复"启动"状态。
- **SDLX 手柄驱动崩溃（0xC0000005）根因未证实**：目前靠 `SDL_JOYSTICK_DIRECTINPUT=0` 与单核启动器规避，属于缓解措施，不是修复。不应因一次通过就删除。
- **已失效的原版挂钩**：`net_events.lua` 的 `kill_piece` 前置、`shared/core.lua` 的 `kill_piece` 后置与 `resume` 前置仍保留；原版脚本已无这些全局函数。未观察到故障，属历史清理项，删除时三处要一起改并重新验证死亡、复活和隐藏结局。
- **长局与性能**：`shared/cards.lua` 顶部的全局 `jit.off()` 是历史崩溃缓解措施，保留现状；缩窄禁用范围需要在隔离环境对比长局稳定性后再决定。
- **断线续局**：未实现。需要保存权威状态、重连握手与去重，不能靠超时解锁代替。

## 发布前仍建议人工过一遍

双方启动与加入、额外行动、破坏效果选择、骑士死亡与复活、选卡换层、完整动画切换、结算重开、中途掉线；如改隐藏结局，追加对应 Boss 实战。两台电脑必须使用同一版本的包（协议版本不一致会直接拒绝连接）。
