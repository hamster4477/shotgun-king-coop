# Shotgun King Co-op

**English | [简体中文](README_zh.md)**

A community-made local and LAN co-op mod for **Shotgun King: The Final Checkmate**. Team up as the Black King and Black Knight in **Throne, Endless, and Charnier**.

[Downloads](https://github.com/hamster4477/shotgun-king-coop/releases) · [Player guide](onlinecoop/README.md) · [Report a bug](https://github.com/hamster4477/shotgun-king-coop/issues)

## Features

- Local co-op and LAN co-op, with shared cards, combat rules, and campaign content.
- In online play, **1P controls the Black King** and **2P controls the Black Knight**. Each player runs their own copy of the game.
- An in-game lobby with room creation, invite copying, and joining.
- Support for reachable LANs, virtual LAN tools, and TCP port forwarding such as FRP.
- Shared board markers and card-choice suggestions from 2P; 1P confirms the final card choice.
- Synchronized board animations, with selectable frame-rate caps and playback modes.
- Simplified Chinese and English interface text.

This distribution uses LAN/TCP networking. It does not include the experimental Steam P2P transport. Steam launch configuration is still supported.

## Install and play

**Requirements:** Windows, an installed copy of Shotgun King, and the same mod version on both PCs for online play. The game itself is not included.

1. Download the player ZIP from [Releases](https://github.com/hamster4477/shotgun-king-coop/releases). If no release asset is available yet, build one using the instructions below.
2. Fully exit the game and place the ZIP's `onlinecoop` folder inside the game's `mods` folder.
3. Enable `onlinecoop` and disable the old `coop` mod. Back up saves before updating; do not run both mods together.
4. For LAN play, launch with **`Start Online Co-op Multi Core.vbs`** inside the mod folder. If your PC needs the single-core workaround, use **`Start Online Co-op.vbs`** instead. Players do not need Python.
5. Both players select the same LAN campaign from **Play**. The host creates a room and copies the invite; the other player pastes it and clicks **Join**.

Local co-op requires no network helper. To launch LAN play directly from Steam, use **`Configure Steam Launch.vbs`** once. See the [player guide](onlinecoop/README.md) for Steam configuration, Workshop paths, virtual LANs, and FRP settings.

## Useful controls

| Control | Action |
| --- | --- |
| **E**, then click a square | Place a board marker. |
| **F6** | Cycle the capture cap: 10 / 15 / 20 / 30 / 45 / 60 FPS; default 30. |
| **F7** | Switch between complete-animation and catch-up playback. |
| **2P: click a card pair** | Send a card-choice suggestion to 1P. |
| **2P: Tab** | Skip the Knight's action. |

Complete-animation playback is the default. It preserves captured frames and may wait for buffering on slower connections. Catch-up playback can skip older frames to reduce delay. Neither mode can remove network latency, and switching takes effect after the current animation finishes.

## Feedback and known limitations

This mod is under active testing. Disconnections currently require both players to restart the connection; automatic reconnection is not available. A shared hotspot may isolate its clients, and virtual LAN or forwarding tools must be configured separately. Some native post-processing and sounds are not reproduced on 2P.

For bug reports, include the mod and game versions, campaign, player role, floor, last action, playback mode, and reproduction steps. Attach relevant screenshots or log excerpts. Remove room keys, invite codes, and personal information before posting logs publicly.

## Development

| Path | Contents |
| --- | --- |
| `onlinecoop/shared/` | Shared card and combat rules for local and online play. |
| `onlinecoop/campaigns/` | Campaign-specific behavior. |
| `onlinecoop/adapters/` | Local and network mode integration. |
| `onlinecoop/net_*.lua` | Synchronization, playback, and client presentation. |
| `onlinecoop/lan/LanTransport.cs` | LAN transport source. |
| `onlinecoop/tests/` | Focused lobby and network-helper checks. |
| `tools/` | Packaging script and runtime file manifest. |

Build a player ZIP from the repository root with Python 3:

```sh
python tools/package.py
```

The archive is written to `dist/`. The script uses an explicit file manifest, excludes tests and runtime data, and refuses to overwrite an existing archive.

Run the included checks on Windows:

```sh
python -m pip install -r onlinecoop/tests/requirements.txt
python onlinecoop/tests/test_game_lobby.py
python onlinecoop/tests/test_game_broker.py
```

The broker test starts temporary loopback helpers and stops them on completion. These checks do not replace gameplay testing. Keep gameplay changes in the shared rules so local and online modes stay consistent.

## Credits and rights

Mod author: **liber H :Aeon**. Shotgun King: The Final Checkmate is a game by **PUNKCAKE Délicieux**. This is an unofficial community project and requires the original game.

No project-wide open-source license has been granted at this time. Contact the author about reuse or redistribution of this project's code and assets. Third-party material retains its respective ownership and applicable terms.
