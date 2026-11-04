# Shotgun King Co-op

**English | [简体中文](README_zh.md)**

One player brings the shotgun. The other brings the Knight's blade.

A two-player co-op mod for **Shotgun King: The Final Checkmate**. Play as the Black King and Black Knight, cover each other, and fight through **Throne, Endless, and Charnier** together. Supports local co-op and LAN play, with additional cards and combat mechanics built around cooperation.

**[Download the mod](https://github.com/hamster4477/shotgun-king-coop/releases)** · [Installation and connection guide](onlinecoop/README.md) · [Report a problem](https://github.com/hamster4477/shotgun-king-coop/issues)

## Before downloading

- Requires an installed copy of Shotgun King. This is a mod; the base game is not included.
- The online launch tools require Windows. Each player runs their own game with the same mod version.
- Supports LAN, virtual LAN tools, and TCP forwarding. Remote players need to configure their own virtual LAN or tunnel.
- Supports English and Simplified Chinese.

## Installation

1. Download the mod release ZIP from **Assets** on the download page. Choose the mod attachment, rather than GitHub's automatically generated **Source code** archives.
2. Fully exit the game and extract the `onlinecoop` folder into the game's `mods` folder.
3. Enable `onlinecoop`. If you have the older `coop` mod installed, disable it so that both versions do not run together.

The installed folder should look like this:

```text
Shotgun King The Final Checkmate/
└─ mods/
   └─ onlinecoop/
      ├─ info.lua
      ├─ script.lua
      └─ …
```

Back up saves before updating. Both online players should install the same complete version; do not mix files from different releases.

## Playing with a friend

For most PCs, launch using **`Start Online Co-op Multi Core.vbs`** in the mod folder. The host controls the King, and the joining player controls the Knight. The host shares an invite code with their friend, and both players use the same campaign.

To launch directly from Steam, run **`Configure Steam Launch.vbs`** once to configure it. Local co-op does not need the network helper.

See the [detailed guide](onlinecoop/README.md) for connection instructions, Steam launch configuration, and FRP setup.

## Common questions

**Cannot connect?** Check that both players have the same version, the host's address is reachable, and your virtual LAN or tunnel is connected. Some hotspots prevent devices from communicating with each other.

**Waiting too long for animations?** Press **F6** to lower the transmission frame-rate cap, or **F7** to switch to catch-up playback. The default complete-animation mode prioritizes preserving animations and may buffer on slower connections.

**Can a disconnected player reconnect automatically?** Not yet. Both players need to establish a new connection.

**Experiencing startup or gameplay crashes?** Try the single-core compatibility launcher, **`Start Online Co-op.vbs`**. This is a workaround and does not guarantee that every crash will be resolved.

The mod is under active testing. Some visual effects and sounds may differ between the host and 2P. Please [report problems](https://github.com/hamster4477/shotgun-king-coop/issues) with the version, campaign, player role, floor, and actions leading up to the issue. Screenshots or relevant logs help; remove invite codes, room keys, and personal information before posting logs publicly.

---

Mod author: **liber H :Aeon**. Original game by **PUNKCAKE Délicieux**. This is an unofficial community mod.
AI tools assisted with programming and debugging this mod.

[Development and source notes](DEVELOPMENT.md)
