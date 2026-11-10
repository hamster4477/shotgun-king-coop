# Co-op — local and LAN

**[简体中文](README_zh.md) | English**

Current version: **Unified 72 LAN 1**. The host (1P) controls the Black King; the joining player (2P) controls the Black Knight. Both run their own game. The host resolves combat and rules; 2P receives visuals and state and submits actions.

Fixed Folly Shield warnings after an independent Knight action changes a bishop/rook attack line, including Inquisition bishops seeing through cloak. Local and online modes share this fix.

Draw weights: Warrant and Bounty Cavalry are restored to their base weight of 4. Revolution and Guillotine also use their original base weight of 4. In-Law (shotgun wedding) and Knight Spirit (chivalry) use base weight 5; other added co-op cards use base weight 4.

One enabled mod provides local and LAN versions of **Throne, Endless and Charnier**. All six entries load the same combat, cards and campaign source. Local play needs no network helper. For LAN play, use the setup below and select the same campaign on both PCs: **LAN Co-op**, **LAN Endless** or **LAN Charnier**. A campaign mismatch is reported before gameplay.

In LAN Charnier, the host manages the campaign save, cinders, brands and starting the next raid. 2P sees a preparation summary (rank, cinders and owned brands) and can ring the bell; purchases remain host-only. After results, the host returns to preparation and may start another raid without reconnecting. In Endless, the host confirms later-floor reinforcement reveals; these input waits do not hold the complete-animation lock.

Keep the old `coop` mod disabled. It may be kept as a backup, but is no longer a development source. The folder remains `onlinecoop` so existing Steam launch paths continue to work. This release keeps the existing `onlinecoop` save bank; old `coop` progress is not automatically combined or erased.

Added in-game prompts follow each player's game language: Simplified Chinese displays Chinese; English and other languages use the English fallback. Fixed mod-list metadata includes both languages. Players may use different display languages.

## 1. Install and launch

Both players must fully exit the game and install the same `coop-unified-r72c-lan-only.zip`. Put its `onlinecoop` folder inside the game's `mods` folder. Replace the complete mod when updating; keep your saves. Leave Steam running on both PCs. This release updates the network helper protocol too: do not mix an old helper with the new Lua files.

Choose an entry point inside `mods/onlinecoop`:

| Launcher | Purpose |
| --- | --- |
| `Start Online Co-op Multi Core.vbs` | Normal launch without imposing a CPU affinity restriction; use this on most PCs. |
| `Start Online Co-op.vbs` | Single-core compatibility launch for PCs that need this workaround for native crashes. |

The two VBS launchers can connect to each other; players do not need the same CPU mode. Single-core affinity is a compatibility workaround, not a guaranteed fix for every crash.

The game opens its normal main menu. Select **Play → LAN Co-op / LAN Endless / LAN Charnier** to open the lobby; you can also choose a normal mode such as Throne. The network helper runs hidden and exits with the game. Players do not need to install Python, LuaSocket or extra DLLs.

The VBS launchers temporarily enable only onlinecoop and restore the previous mod list on exit. If you change that list during play, your changes are retained. They do not modify files in `mods/coop`. Do not enable coop and onlinecoop in the same process: they contain overlapping card names and rules.

### Steam Workshop installation

[Subscribe on Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3833493529). When the download finishes, open this folder in the Steam library where Shotgun King is installed:

```text
steamapps\workshop\content\1972440\3833493529\
```

Double-click **Configure Steam Launch.vbs** there, select your account and **Apply and restart Steam**. Multi-core is the default; select single-core compatibility if needed. Then launch from Steam, or use either Online Co-op VBS directly inside the Workshop item folder. Subscribing does not execute the setup script automatically: configure it once manually.

The launcher uses the numeric Workshop directory as the enabled item ID, locates the game through Steam installation manifests, and runs the helper against that same mod's `lan` directory. No copy to the game's `mods` folder is required. Only the selected item is enabled during launch; the original mod list is restored on exit unless you deliberately changed it in-game. Local `coop` / `onlinecoop` files are not overwritten. Missing, invalid or ambiguous game installations produce an error.

Ordinary updates retaining the same item path do not require reconfiguration. Moving libraries, switching Workshop items or unsubscribing requires updating/removing Steam Launch Options. Exit the game and helper before updating; both players need the same release.

Developer checks cover simulated Workshop paths, separate Steam libraries, numeric activation IDs, native-game numeric-folder loading/mailboxes, duplicate-local-mod exclusion and list restoration. The real subscription → launch → Workshop update flow still needs verification after publishing.

For publishing, select a clean content folder containing `info.lua` and `script.lua` directly. Do not upload its outer folder, the ZIP itself, or the development directory's old archives, logs and test runs.

## 2. Create or join a room

On the same LAN, click **Nearby** at the top right of the lobby, wait for your friend to create a room, then click their computer name and address to join. Both players must select the same game mode. The list refreshes automatically; closed rooms expire after about six seconds. Discovery uses UDP port 27842. If a hotspot, firewall, or virtual LAN blocks discovery broadcasts, use an invitation code.

The lobby shows the selected network adapter's name. After a successful connection, the host's adapter is remembered and preferred on the next launch if still available. Connection failures show a more specific reason and a **Retry** button. Ask for a new invitation if the host recreates the room. Hold Backspace or Delete to erase continuously, or hold Left/Right to move the caret.



1. Both players select the same **Play → LAN Co-op / LAN Endless / LAN Charnier** entry.
2. The host clicks **Create room → Copy invite** and sends the complete invite to their friend.
3. The friend copies it and clicks **Paste** beside the invite field, then **Join** above. There is no need to enter the IP, port and key separately.
4. After connection and version checks, the host chooses a weapon and rank and starts. 2P finishes their own opening cutscene and waits for the host. No game restart is needed.

Addresses are detected automatically. With multiple adapters or a virtual LAN tool, the host clicks the address before creating a room to select one their friend can reach. For example, use the host's virtual IP with JiaoYueLink, not the client's own IP. The default port is `27841`; occupied ports are skipped. The actual port is included in the invite.

Clicking the invite/port field highlights its border and shows a blinking caret. Arrow keys, Home/End, Backspace and Delete work. **Back** or Esc cancels this room/connection attempt and returns to the menu. Failed connections can be cancelled and retried.

For the default LAN / virtual LAN option, the PCs must be able to reach each other over that network. A SKCOOP1 invite does not provide a public relay. If Windows asks for firewall permission, allow the trusted network you are using. Some hotspots isolate devices, so sharing a hotspot does not guarantee connectivity.

### Optional: TCP tunnels and port forwarding

Click **Tunnel settings (optional)** beside **Back** at the bottom of the lobby, then enable **Use public endpoint** on its settings page. This changes the advertised address only. Configure and keep your third-party tunnel running separately. Your friend still uses **Paste** beside the invite field, then **Join** above and does not need to enable this option.

For Sakura FRP running on the host's gaming PC:

1. Enable forwarding. The default local binding becomes `127.0.0.1:27841`; local ports may be 1024–65535.
2. Create a **TCP** tunnel whose local IP and port match the game's **Local** address and port.
3. Start the tunnel and copy its **public hostname:remote-port**. Use **Paste** beside the public endpoint field. The `tcp://hostname:port` format is also accepted.
4. Create the room, wait for the waiting status, then **Copy invite** and send it to your friend. External and local ports can differ: do not put the remote port in the local port field.

The public endpoint is remembered locally, but forwarding starts disabled on each game launch. Enable it when needed. You can edit the public address while waiting and copy a new invite. Mapped rooms never silently switch an occupied local port: choose another local port and update the tunnel target to match.

| Connection method | In-game configuration |
| --- | --- |
| Sakura FRP, upstream frp, NATAPP and similar raw TCP tunnels | Enable forwarding and enter the public hostname/IP and remote port. A tunnel running on the gaming PC normally targets `127.0.0.1:local-port`. |
| Router TCP port forwarding with public IPv4 / DDNS | Enable forwarding, switch Local to the host's LAN IPv4, and forward the router port to that address and local port. Advertise the public IP/DDNS and external port. Requires an inbound-reachable public address. |
| ZeroTier, Tailscale, Jiaoyuelian and other virtual LANs | Usually leave forwarding off. Connect the virtual network before starting the game, select the reachable virtual-adapter IPv4, then create and share the invite. Both peers need network access permission. |
| Tunnel agent on a different LAN device | Bind the game to the host's LAN IPv4 and configure the agent to forward to that address and local port. |

Supports numeric IPv4, names resolving to IPv4 (including DDNS), and external ports 1–65535. IPv6-only endpoints, HTTP/HTTPS web tunnels, UDP-only tunnels, and forwarding that requires the game to understand PROXY protocol are not supported. This is generic TCP endpoint support: it does not log into providers, create tunnels or modify routers. Configure provider authentication, virtual-network authorization and firewalls in the relevant tools.

Verified with a local TCP relay: hostname connection, different internal/external ports, bidirectional data and port conflicts. Individual providers' public routes have not been live-tested. Official references: [Sakura FRP](https://doc.natfrp.com/game/other-games.html), [frp](https://gofrp.org/en/docs/features/tcp-udp/), [NATAPP](https://natapp.cn/article/tcp), [ZeroTier](https://docs.zerotier.com/start/), [Tailscale](https://tailscale.com/docs/use-cases/personal-or-at-home-use/share-private-game-server).

## 3. Optional: launch from Steam (single-core entry verified)

Double-click **`Configure Steam Launch.vbs`**. It detects Windows, game and Steam paths. Select your Steam account. Multi-core is the default; check **Single-core compatibility** if you need to restrict the game to one logical CPU. The account list shows Steam nicknames and IDs, marks the current account, and selects it when detected. Last login is labeled separately; if the current account cannot be confirmed, select by nickname.

- **Copy** copies the complete launch options for pasting into the game's Steam Properties.
- **Apply and restart Steam** requests a normal Steam shutdown, waits for it to exit, backs up and writes the selected account's launch options, then reopens Steam. No manual shutdown or path entry is needed. Finish your games first and respond to any Steam prompts.

Only this game's launch options are replaced; the previous value is displayed. Backups are stored in the account's `config` directory as `localconfig.vdf.onlinecoop-timestamp-id.bak`. If Steam does not exit within 45 seconds, nothing is written and it is not forcibly terminated. Select the correct account when several exist. Browse to `steam.exe` if detection fails, or use Copy. Manual configuration follows below.


On 2026-10-29, a player confirmed that the single-core entry below successfully launched the game from Steam. Right-click the game in Steam → **Properties → General → Launch Options**, then entering this complete line:

```text
"C:\Windows\System32\wscript.exe" "<actual game installation folder>\mods\onlinecoop\Start Online Co-op.vbs" %command%
```

Replace the entire `<actual game installation folder>` placeholder with the full path to your game folder, without angle brackets. Example:

```text
"C:\Windows\System32\wscript.exe" "D:\Program Files (x86)\Steam\steamapps\common\Shotgun King The Final Checkmate\mods\onlinecoop\Start Online Co-op.vbs" %command%
```

Your Steam library may be outside `Program Files (x86)`; changing only the drive letter may be insufficient. Keep the quotation marks and trailing `%command%`. For multi-core launching, change only the filename to `Start Online Co-op Multi Core.vbs`. The multi-core entry has not yet been separately tested through Steam.

Use a full path for the first executable too: `"C:\Windows\System32\wscript.exe"`. In the reported test, the bare name `wscript.exe` made Steam report a missing executable (OS Error 2), although both the game and VBS existed. If Windows is installed elsewhere, use its actual `System32\wscript.exe` path.

Then click Steam's **Play** button and select **LAN Co-op** in-game. This confirmation covers game startup, not a complete two-PC multiplayer test. If it fails, remove this added launch option and double-click the VBS directly. Save any existing launch options before editing. Without this configuration, ordinary Steam launching does not automatically start the network helper.

## 4. Playing

The King acts first on the first turn of every floor. Subsequent turns normally proceed Knight → King → white-piece resolution. Wait for animations to finish and legal-target markers to appear before acting.

| Player/control | Action |
| --- | --- |
| 1P | Normal King movement, shooting, reloading, card selection, wands and other King actions. |
| 2P left-click a legal square/target | Move or attack with the Knight; rules are still resolved by the host. |
| 2P Tab | Skip the Knight's action. |
| 2P right-click | Cancel the selected soul. |
| 2P C / V | Cycle card pages / soul pages when there are more than five soul slots. |
| Either player: E, then click a square | Place one ping and leave ping mode. E again or right-click cancels. The lower-left exclamation button also enters ping mode. |
| 2P click the upper/lower card pair | Suggest a pair to 1P; only 1P confirms the final selection. |
| 2P left-click the bell | Notify 1P; both hear the same bell variant, with a local button animation; 0.3-second cooldown. |

A ping flashes on arrival, lasts about 3 seconds and disappears. Each player keeps one ping; a new one replaces their previous ping. Pings clear on a floor change. Changing a card suggestion plays a sound for 1P; repeating the same suggestion does not. Bell presses have a 5% chance of sound 3; otherwise sound 1 or 2 is chosen randomly.

With **In-Law**, 2P can choose a Bishop/Rook soul and move using its pattern. With **Knightly Spirit**, choose a Knight soul, then left-click a square on the same rank/file to anchor a charge. Cancelling with right-click does not consume the soul. After the Knight dies, click a Knight soul while the King can act to revive it. The Knight cannot act again during its revival turn.

With **Phantom Muster**, 2P clicks the lower-left six-dot icon during the Knight's action, once per floor. The Knight sacrifices itself; six Phantom Knights appear next turn. 1P controls them through the native black-piece pickup/drop controls.

2P can see owned cards (including duplicates), souls, weapon/ammo, blade and piece status. Hover other pieces for status and cards for names. Wait while host confirmation is pending. If an action is rejected after the state changes, use the refreshed legal targets.

## 5. Animation, networking and frame rate

New games default to **complete-animation mode**. Either player presses **F7** to switch modes for both players. The current action and received animations finish before the switch takes effect. The setting persists across floors in the current run and resets on mode re-entry. Switching is unavailable during cutscenes.

| Mode | Tradeoff |
| --- | --- |
| Catch-up frames | Uses a short adaptive jitter buffer while actions animate, limits frames in flight and reduces the send rate under congestion. Old images may be skipped to stay close to the host. Ready/input phases show the latest received image immediately. |
| Complete animation | Starts playing while receiving when enough animation is buffered and the link can keep up. Preserves captured frames and timing; slow or repeatedly interrupted links buffer longer. Board actions unlock only after playback finishes. |

**F6** cycles the capture cap through `10 / 15 / 20 / 30 / 45 / 60`, default `30`. This affects synchronization sampling, not turn rules or game speed. Catch-up mode automatically adjusts below that cap during congestion and recovers gradually; complete mode retains the chosen capture cap. The rate display appears for about 3 seconds after pressing the key and stays hidden otherwise. Lower the cap on a slow link; try F7 if preserving complete actions matters more than waiting.

Board frames use lossless inter-frame compression: repeated pixels are referenced rather than retransmitted, with no resolution or palette reduction. Unchanged live frames and redundant Boss visual updates are suppressed. Receive-window flow control pauses sending while a peer is loading or temporarily not consuming messages, rather than overflowing its queue. These changes reduce traffic and uneven delivery; they cannot remove physical latency, long connection stalls or insufficient bandwidth.

Complete-animation records use bounded batches to reduce local file and socket overhead. Interactive commands flush any preceding batch immediately; the helper does not wait to fill a batch. Playback keeps the captured frame order and timing. Slow links may need to buffer before playback rather than repeatedly stall mid-action.

Complete mode carries buffering adjustments from earlier actions across turns and floors, gradually reducing the buffer when the connection stabilizes. The client decodes a small number of upcoming frames in advance to reduce decoding work at presentation time. Playback may start later on an unstable link, but received animation frames are not skipped to catch up.

Hidden-Boss transformations, book pickup and ending departures remain in the complete-action channel even while normal turns are paused. These story segments capture the full canvas, including side-card effects, the top of the screen, dialogue and native palette flashes. Complete mode buffers a story clip fully before showing its first story frame, avoiding network underruns midway through a transformation. Ordinary combat retains the narrow board capture and progressive playback. Modal choices become usable after their preceding clip has played.

Complete mode cannot invent uncaptured frames or eliminate local rendering stalls. Each action has safety limits of 7,200 frames, 24 MB of encoded frame data and two minutes. If an exceptional action reaches a limit, it retains the final image and logs the truncation; completeness is not guaranteed beyond those limits. Story text is redrawn locally at high resolution using 2P's current font. Different language/font settings may have different glyph coverage or appearance. Some postprocessing shaders and sounds are not part of the pixel channel. Opening, final-floor transition and ending cutscenes run locally on each PC without requiring frame-by-frame synchronization.

## 6. Troubleshooting


| Symptom | Check/action |
| --- | --- |
| Steam reports a missing executable | Check the quoted full path to the system `wscript.exe` and the VBS path that follows it. |
| Helper missing | Use either Online Co-op VBS launcher. For Steam, see section 3. |
| Version mismatch | Both players exit, replace the complete mod with the same release, then reconnect. |
| Timeout/refused connection | Check the host address, running helper, virtual LAN and firewall. Hotspots may isolate devices. |
| Choppy visuals | Lower capture rate with F6. F7 complete mode can preserve more of each action but adds waiting. |
| Disconnect during a game | Reconnection is not supported yet; both players must fully exit and reconnect. |

For a report, keep the game's `log.txt`, latest `crash_log_*.txt`, current session's `mods/onlinecoop/lan/<session>/error.txt` if present, and `lan/lobby/<session>/broker*.log`. Include roles, floor, last action and F6/F7 settings. Remove invite codes and room keys before sharing.

Joining a game in progress, resuming after disconnection and swapping roles are unsupported. 2P reuses native board visuals with supplemental UI; not every native/third-party mod effect or detailed tooltip is guaranteed to match. Native crashes and network disconnections are distinct failures.
