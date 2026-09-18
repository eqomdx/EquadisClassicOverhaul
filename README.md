# Equadis' Classic Overhaul

**One interface addon for World of Warcraft 1.12 (Vanilla / Turtle / OctoWoW).**

<https://github.com/eqomdx/EquadisClassicOverhaul>

Unit frames, nameplates, raid and party frames, action bars, buff frames, bags,
a damage meter, a threat meter, a class HUD, tooltips, map and waypoints, a
mailbox and a chat overhaul — one settings panel, one profile system, one look.

## Installation

1. Download and unpack.
2. The folder must be named **`EquadisClassicOverhaul`** exactly, or the bundled
   textures and fonts will not load.
3. Put it in `World of Warcraft\Interface\AddOns`.
4. Restart the game (a `/reload` is not enough for a new install — 1.12 reads an
   addon's file list once at startup).

Back up your `WTF` folder before replacing a UI addon. Saved-variable migrations
are provided, but a backup is cheaper than a migration.

## Getting around

```
/eq            the settings panel          (also /eco, /co, /ob)
/eq help       every setting, typeable
/eq setup      the first-run walkthrough
/eq test       preview every bar without a target
/eq profile    use | new | copy | delete
/eq reset      this profile back to defaults
```

**Edit mode** unlocks every frame for dragging: `/eqedit`, `/editmode`, or hold
**Ctrl+Shift+Alt**. A banner says it is on; drag anything outlined; do it again
to lock. Notices — a setting that needs a reload, for instance — appear in the
same banner.

Other windows have their own commands: `/bags`, `/way` (waypoints), `/db` (item
database), `/tt` (chat scan), `/us` (UnitScan), `/addons`, `/autoneed`,
`/autogreed`.

## Modules

Every module has a tab on the panel and can be switched off on the **Modules**
page. All ship on.

| Module | What it does |
|---|---|
| Unit Frames | Player, target, pet, target-of-target; cast bars; PvP timer; aura timers |
| Nameplates | Health, casts, debuff timers, threat colouring with a **Tank** mode |
| Party / Raid Frames | Class-coloured, grouped by raid group, out-of-range fade, dead/ghost/offline |
| Action Bars | Every bar movable and reshapeable; keybind, macro and item-count text; XP and reputation bars |
| Buff Frames | Rows for buffs, debuffs and weapon buffs; timers; expiry flash |
| Bags | One window for bags, bank and keyring; search; sort; favourites; other characters |
| Damage Meter · Threat Meter | The threat meter reads Turtle's own server threat packet |
| Omni Bars (HUD) | Health, resource, swing, combo points, druid mana, distance to target |
| Tooltip | Positioning, item values, drop sources, health bar |
| Map · Waypoints | Coordinates, square minimap, pins, arrow |
| Chat | Timestamps, URLs, history, channel colours |
| Character Panel | Stats pane with hit/crit from gear, sets and talents; coloured item borders |
| Mail | The bundled TurtleMail: rapid open, multi-send, autocomplete, log |
| Automation | Auto-roll rules, confirmation skips, dismount, camera |

## Optional client mods

The addon runs on a stock 1.12 client. With a client mod present it does more,
and `/eq selftest` reports which are detected:

- **Nampower** — engine range checks; exact yardage where the build exposes it.
- **SuperWoW** — nameplates addressable as units, so threat colouring works on
  every plate rather than only your target.
- **UnitXP SP3** — exact distance to anything and continuous line of sight.

Without an exact-distance source the Distance bar still works: it narrows the
range to a band by asking the engine about spells of known reach. With one, it
prints the yardage.

## When something looks wrong

```
/eq selftest      checks every API the addon needs against your client
/eq rangedebug    every raw value behind the distance readout
/eq threatdebug   where threat can come from on this server
```

`/eq selftest` first. It changes nothing and says which module, if any, failed to
build.

## Development

`tests/run.lua` boots the real addon against a stub of the 1.12 client and
runs about six thousand checks in thirty seconds:

```
luajit tests/run.lua
```

The game runs Lua **5.0**; the suite runs on LuaJIT, which accepts things 5.0
does not. `/eq selftest` in game is the other half of the check.

## Licence and credits

GPL-3.0. Built from Equadis' Rogue Bars, Threat Meter and UnitFrames, with
ported work from ShaguDPS and ShaguPlates (Shagu), Bagnon, DruidManaLib (Aviana),
TurtleMail (shirsig/sica), Atlas-CFM and UnitFramesImproved. Every bundled
licence is reproduced in `NOTICE`, and each ported file names its origin at the
top.
