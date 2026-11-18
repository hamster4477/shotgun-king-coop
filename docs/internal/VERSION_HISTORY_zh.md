# 版本沿革与数量口径

截至 2026-11-18。没有完整、连续的提交/发布台账，因此不能把聊天轮数或 r72 字样当作确切版本数量。

可辨认阶段：本地合作原型 → 回合/灵魂/死亡修复 → 新卡与隐藏结局 → LAN 原型 → 原版动画复用 → 完整动画/追帧与网络优化 → 本地与在线共享规则合并 → 工坊/GitHub/Discord 公测 → 1.624/1.624b 兼容排查。

现存文件名包含 r72c、r72d、r72e、r72f、r72g 五个合并版标记，以及 Discord r4、r5 两个标记；它们不是同一条连续编号。还存在 UI、血量、剧情、测试权重、P2P 和工坊热修复等变体。不能推断总共恰好 72 版。

当前 exports 顶层存在 19 个模组发行或测试 ZIP（排除 BGM 参考包和 GitHub 源码包）。这只是现存归档数量，可能重复内容，也不包含已删除的早期包，不等于实际开发迭代总数。

## 现存包名

- Shotgun-King-Co-op-Beta.zip
- Shotgun-King-Co-op-Discord-Beta-2026-11-05-r4.zip
- Shotgun-King-Co-op-Discord-Beta-2026-11-05-r5.zip
- Shotgun-King-Co-op-Public-Beta-2026-11-04.zip
- Shotgun-King-Co-op-Public-Beta.zip
- Shotgun-King-Co-op-Workshop-3833493529-hotfix.zip
- coop-unified-r72c-boss-health-only-lan-only.zip
- coop-unified-r72c-knight-health-lan-only.zip
- coop-unified-r72c-lan-only-20261111.zip
- coop-unified-r72c-lan-only.zip
- coop-unified-r72c-player-icons-aligned-lan-only.zip
- coop-unified-r72c-player-icons-aligned-steamp2p-test.zip
- coop-unified-r72c-player-icons-steamp2p-test.zip
- coop-unified-r72c-revolution-guillotine-weight100-lan-only.zip
- coop-unified-r72c-revolution-guillotine-weight100-steamp2p-test.zip
- coop-unified-r72d.zip
- coop-unified-r72e-story-captions-lan-only.zip
- coop-unified-r72f-OP.zip
- coop-unified-r72g-player-icons-lan-only.zip

## 从 v0.73.0 起统一编号

旧的 r72c ~ r72g、Discord r4/r5 只是历史文件名，不再代表版本顺序。自 v0.73.0 起改为单一编号：

| 项 | 值 |
| --- | --- |
| Git 标签 | v0.73.0 |
| 发布资产 | coop-unified-r73.zip（81 文件） |
| package.py 产出 | dist/coop-unified-r73.zip |
| 协议版本（ONLINE_BUILD） | unified72lan3 |

协议版本与发行版本是两件事：ONLINE_BUILD 只在联机协议变更时递增，不一致的双方会直接拒绝连接。

以后每次发布记录标签、对应提交、发布包 SHA256 与测试范围，不要再沿用 r72x 名称。
