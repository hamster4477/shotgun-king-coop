# 合作模组维护交接

更新时间：2026-11-14。面向后续维护者；本文不是玩家安装说明。

本日收尾审查已完成源码修复同步、传输上限错误处理与发布清单校验。验证范围和待办见同目录 [FINAL_AUDIT_zh.md](FINAL_AUDIT_zh.md)；游戏根目录阅读者请打开 `exports/coop-lan-source-r72c/FINAL_AUDIT_zh.md`。

## 先读结论
本地合作与 LAN 合作已共用规则。修改平衡、卡牌、攻击和回合逻辑优先改 shared，不能为两种模式各复制一份规则。主机负责游戏判定，2P 发送操作、显示主机状态和动画。
当前文件状态优先于历史聊天和旧压缩包；历史测试通过不代表最近所有改动都重新测过。

## 目录与发布对象
- 游戏目录下 mods/onlinecoop：实际运行的开发副本。
- exports/coop-lan-source-r72c：准备上传 GitHub 的源码副本；目录名不是当前发布版本的可靠标识。
- exports/workshop-release/onlinecoop：工坊暂存副本，上传前需与实际上传目录核对。
- exports/workshop-backups：上传前备份；不要作为开发源覆盖新代码。
- diagnostics：旧日志、原版脚本对比、隔离测试和脚本；不进玩家包。
- mods/coop：旧独立本地合作，通常应停用；不能与合并版同时启用。
- 工坊 ID：3833493529；游戏 App ID：1972440。
- 工坊订阅路径：Steam 库/steamapps/workshop/content/1972440/3833493529。订阅副本与本地副本只能启用一个。
- GitHub：https://github.com/hamster4477/shotgun-king-coop
- 作者反馈邮箱：hamster4477@qq.com

## 代码导航
- script.lua：模组入口、资源注册、工坊身份和上传状态按钮防护。
- shared/core.lua：合作回合、移动、攻击、死亡、复活、灵魂槽及换层控制。
- shared/cards.lua、shared/royal_cards.lua：卡牌与自定义棋子；改权重先按卡牌名称定位对应声明和后续加权规则。
- shared/actions.lua：共享动作；shared/turn_indicator.lua：玩家回合图标。
- modes：本地和 LAN 的王座、无尽、剿灭入口。
- campaigns：隐藏结局、反叛骑士、悬赏元帅、幻影分支、美术与剧情。
- adapters：网络与模式适配。
- game_lobby.lua：游戏内创房、加入、连接码编辑、附近房间和穿透设置。
- transport.lua、lan、Lan-GameBroker.ps1、Start-LanBridge.ps1：游戏与辅助进程通信、网络连接。
- net_playback.lua：完整动画缓冲、播放、完成确认；net_scenes.lua/net_view.lua/net_signals.lua：场景、显示和提示。
- Start-OnlineGame.ps1：启动游戏及辅助进程；InstallPaths.psm1：本地/工坊安装定位。
- Configure-SteamLaunch.ps1、SteamLaunchOptions.psm1：配置 Steam 启动参数。

## 高风险约束
1. 只有主机执行伤害和回合结算。不得因 2P 重复输入重复执行动作。
2. 完整动画模式必须在动画完成后确认，同时能从选卡、破坏效果选择、额外回合等状态恢复；不要靠玩家额外点击解锁。
3. 死亡棋子必须及时退出威胁、占用、近战目标计算。骑士精神的回合末攻击要在原版建立攻击队列之前处理。
4. 灵魂槽会复用，复活骑士后需要恢复后续灵魂的点击回调。
5. 同名卡允许重复，不能用卡名作为唯一实例标识。
6. 隐藏结局、跨层与重开要清理旧棋子/按钮引用；本局记录与单层记录必须分开。
7. SUGAR 模组沙箱并非完整 Lua 环境。不能假设 string/math/os/io 等表可用；使用已验证的平铺接口，测试也需模拟限制。
8. 不修改官方 exe 或 data.sgr 来实现普通模组功能。不将原版游戏文件、转储、会话密钥、运行日志或组网工具打包。
9. UI 和说明保持中英双语；README.md 英文，README_zh.md 中文。小游戏是彩蛋，不在玩家说明里公开。
10. Steam P2P 是实验分支，公开 LAN 包应继续排除其二进制和 SDK。不要覆盖作者保留的测试版。

## 最近故障及真实状态
- 历史 0xc0000005：限制一个逻辑 CPU 有效缓解，但根因未证实。不能宣称原版多线程缺陷或已根治。保留单核可选项。
- 1.624：2026-11-08 对比原版脚本未发现挂接函数删除或签名变化；隔离本地开局和双窗口击杀白王、选卡同步、客机建议、进入第二层通过。不是所有隐藏结局全覆盖。
- 1.624b：曾出现 SDL Haptic error CoCreateInstance，发生于模组加载前；另有 diagnostics/bug-report-2026-11-11-haptic-crash.md 记录。禁用 DirectInput 曾使一次隔离测试成功，但不能当作根治。当前 Start-OnlineGame.ps1 已不含当时临时设置；不要依照旧聊天盲目加回。
- crash_log_065：game_lobby.lua 使用 string.gmatch 导致 nil 错误。2026-11-14 检查现有代码已改成 each_match，并以 flr 计算分页。不能再列成“尚未修改”；仍需在真实辅助进程运行时复测网卡列表、附近房间及输入按键，不能只测本地棋盘。
- 工坊上传曾因 manifest 上传超时失败，重复点击失败状态图标又触发原版 menu.lua 错误。script.lua 有窄范围防护；网络上传失败本身不是该防护能解决的。

## 测试与发布
在源码根目录安装 onlinecoop/tests/requirements.txt 所需依赖，运行 onlinecoop/tests 中 test_game_lobby.py、test_playback.py、test_playback_network.py、test_transport_limit.py；网络辅助进程测试用 test_game_broker.py。阅读脚本后执行。纯 Lua 模拟测试不能代替原生游戏。
本机旧隔离工具：diagnostics/run_v1624_native.py；探针包括 v1624_start_probe.lua 和 unified_draft_sync_probe.lua。启动前检查工具路径、游戏版本及复制清单，使用独立存档；它们会启动进程并自动停止，不应用于正在游玩的进程。
最小人工回归：启动/退出大厅、创房加入、双方行动、额外行动、破坏选择、骑士死亡复活及灵魂、选卡到第二层、完整动画与追帧切换、结算后重开。重点改隐藏结局时追加相应 Boss 和结局测试。网络变更需两台电脑验证延迟、断连及版本不一致。
打包工具：源码根目录运行 python tools/package.py <新的ZIP绝对路径>。只打 tools/package-files.json 白名单；输出使用独占创建，不覆盖旧包。新增运行文件需更新白名单。
发布前运行 tools/check_release.py 核对清单，并使用 --compare 核对运行副本、源码副本和工坊副本差异，勿将本机兼容设置同步给所有玩家。确认测试权重已恢复，没有开局赠卡和探针。本次交接未自动上传 GitHub 或工坊，也未制作新的对外发布包；diagnostics 内仅有打包检查产物。
工坊更新保留 info.lua 的现有 ID；历史入口是游戏根目录“上传创意工坊.bat”，在 Mods 中用 upload 进入上传界面。上传前先核对实际加载目录，避免传了旧订阅副本。发布由作者确认执行。

## 接手第一天
先备份；核对本地游戏版本和最新日志；比较三个副本；运行大厅沙箱测试与带辅助进程的原生启动；再测试一轮联机换层。每次发布记录日期、代码来源、改动、测试范围和包名，别只沿用 r72c 名称。
