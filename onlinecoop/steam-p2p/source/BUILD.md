# Headless Steam tunnel

This is the optional transport adapter, not a second implementation of game rules.
It retains SteamP2PTunnel's seven-byte stream ID and little-endian u32 message type
framing, with a single stream and bounded queues. The existing authenticated TCP
game bridge runs over this stream unchanged. It cannot connect to the upstream GUI
directly: both players need this adapter and its `SKCOOPS1` lobby metadata.

Build with Rust on 64-bit Windows:

```powershell
cargo build --release --locked --target x86_64-pc-windows-gnu
```

This build was tested with Rust 1.99.1's GNU toolchain. Cargo.lock pins the dependency
versions and checksums. Copy `onlinecoop-steam-tunnel.exe` from the target release
directory and the matching `steam_api64.dll` from the steamworks-sys build output
into the parent `steam-p2p` directory. Do not replace the game's own Steam DLL or
create a steam_appid.txt in the game directory. Keep the dependency notices.

`--self-test` checks packet framing without initializing Steam. Normal arguments:

```text
--role host|client --port <local-port> --lobby <id-or-0>
--status <absolute-status-file> --stop <absolute-stop-file>
```

The broker supplies these arguments; players use the in-game lobby. Status records
are `SP1|state|lobby-id|error-code|END`. A stop file requests shutdown. The client
binds a loopback TCP listener, while the host connects only to its loopback game
bridge. Only Steam lobby members may open a host P2P connection. The underlying
game bridge still authenticates the invitation key. App ID 480 is intentionally
confined to this helper process and remains experimental.

Developer checks in `../../tests`: `test_game_lobby.py`, `test_game_broker.py`,
`test_steam_p2p_broker.py`. The last one creates real Steam lobbies but does not
test two-account traffic. For that, use two logged-in Steam friends on different
PCs, create/copy/paste/join, complete a floor and card choice, cancel and reconnect.
