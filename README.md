# Co-op — LAN-only source export

[中文](README_zh.md) | [Player guide](onlinecoop/README.md)

Source for Unified 72 LAN 1. Local co-op, LAN / virtual LAN, TCP forwarding and Steam launch configuration remain available. The experimental P2P transport and its binaries, SDK runtime and source are excluded.

Run `python tools/package.py` to create the player ZIP in the ignored `dist/` directory. The explicit manifest excludes tests and runtime data. Existing archives are never overwritten. Requires Python 3; Windows is required by the game helpers.

Checks: `python -m pip install lupa`, then `python onlinecoop/tests/test_game_lobby.py` and `python onlinecoop/tests/test_game_broker.py`. The latter starts temporary loopback helpers and stops them on completion. No original game files are included. Actual gameplay requires a separately installed copy of Shotgun King.

Shared rules are in `onlinecoop/shared`, campaign rules in `campaigns`, and mode adapters in `adapters`. Do not duplicate balance fixes between local and online modes.

Licensing: this export does not grant a new blanket license. The author still needs to choose a license for code they can license and document asset rights before claiming the entire repository is open source. Game names and third-party material retain their respective ownership. Audio redistribution rights were confirmed by the mod author. This export does not constitute a complete provenance audit.
