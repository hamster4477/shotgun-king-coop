# 合作模组：纯局域网源码目录

[English](README.md) | [玩家说明](onlinecoop/README_zh.md)

版本 Unified 72 LAN 1。保留本地合作、局域网／虚拟组网、TCP 端口映射与 Steam 启动配置；排除实验 P2P 的接入代码、程序、SDK 动态库和源码。

执行 `python tools/package.py` 在已忽略的 `dist/` 目录生成玩家 ZIP。使用明确文件清单，不打包测试、会话数据或日志，也不覆盖已有压缩包。Python 3 用于打包；游戏助手需要 Windows。

测试：先 `python -m pip install lupa`，再运行 `python onlinecoop/tests/test_game_lobby.py` 与 `python onlinecoop/tests/test_game_broker.py`。后者会启动临时本机回环网络助手并在结束时关闭。不包含原版游戏文件，实际游戏需另行安装。

共享战斗／卡牌规则位于 `onlinecoop/shared`，战役位于 `campaigns`，模式适配位于 `adapters`，无需分别修改本地和在线平衡。

许可：本次整理没有擅自给代码或素材添加统一开源许可。上传前仍应由作者选择可授权代码的许可证并说明素材权利范围；不要直接宣称全部文件均为 MIT。音效再分发来源由模组作者确认。本目录整理不等同于完整来源审计。
