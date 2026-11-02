# Development

[Back to the player guide](README.md) | [简体中文](DEVELOPMENT_zh.md)

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
