# SoilWorkYieldBonus

SoilWorkYieldBonus is a lightweight gameplay script mod for Farming Simulator 25. It adds a small yield bonus for meaningful soil preparation work without adding menus, map icons, settings screens, or any extra player-facing configuration.

The mod runs in the background and adds one compact line to the standard field information panel.

## Features

- Disking gives up to `+4%` yield bonus.
- Cultivating gives up to `+6%` yield bonus.
- Disking and cultivating do not stack.
- If both operations are recorded on the same field, only the higher soil preparation bonus is used.
- Maximum bonus from this mod is `+6%`.
- The active or pending bonus is shown in the normal field information panel as `Yield bonus`.
- Multiplayer is supported. The server keeps the authoritative field state and synchronizes it to clients for UI display.

Mulching and soil rolling are not modified by this mod. Farming Simulator already handles their own base-game yield effects, so this mod only fills the missing soil preparation gap.

## Balance

The goal is to make soil preparation matter without making the economy too generous.

```text
soilPrepBonus = max(diskingBonus, cultivatingBonus)
finalBonus = min(0.06, soilPrepBonus)
```

Examples:

| Field work | Mod bonus |
| --- | ---: |
| Disking only | `+4%` |
| Cultivating only | `+6%` |
| Disking + cultivating | `+6%` |
| Mulching only | `0%` from this mod |
| Soil rolling only | `0%` from this mod |

## Coverage Requirement

An operation only becomes active after enough of the field has been worked. This prevents very small passes from activating a full-field bonus.

The threshold scales with field size:

| Field size | Required coverage |
| ---: | ---: |
| Up to 5 ha | `80%` |
| 10 ha | `85%` |
| 15 ha | `90%` |
| 20+ ha | `95%` |

Pending bonus example:

```text
Yield bonus: +4% 42/80%
```

Active bonus example:

```text
Yield bonus: +4% 91%
```

## How It Works

The mod tracks soil preparation progress per field on the server side. Field progress is saved in a separate file:

```text
soilWorkYieldBonus.xml
```

It does not edit the base game `fields.xml`.

When harvesting starts, the mod applies the active field bonus to harvested liters through the standard combine harvest path. It multiplies the vanilla harvest amount instead of replacing fertilizer, lime, weed, Precision Farming, or other base game modifiers.

After enough of the field has been harvested, the stored soil work state is reset for the next crop cycle.

## Compatibility

Designed for Farming Simulator 25, script version `1.20.0.0`.

The mod should work with vanilla equipment and most modded tools that use the standard GIANTS specializations:

- `Cultivator`
- `Cutter`
- `Combine`

Disking and cultivating are detected from the cultivator specialization and tool metadata. Some modded tools may classify themselves differently; in that case the mod falls back conservatively.

## Multiplayer

The server is authoritative:

- soil work progress is recorded on the server;
- savegame state is written only by the server;
- clients receive synchronized field progress for the field information panel.

All players in a multiplayer session must use the same mod version.

## Installation

1. Download `FS25_SoilWorkYieldBonus.zip` from the latest GitHub release.
2. Place the zip file in your Farming Simulator 25 `mods` folder.
3. Enable the mod when starting or loading a savegame.

Do not unpack the zip into the `mods` folder unless you are actively developing the mod.

## Development

Repository layout:

```text
FS25_SoilWorkYieldBonus/
  modDesc.xml
  icon_SoilWorkYieldBonus.dds
  scripts/
    SoilWorkYieldBonus.lua
```

To create a release build, zip the project contents so `modDesc.xml` is at the root of the archive.

## Notes

- No custom UI menu.
- No player settings.
- No map icons.
- No base-game XML edits.
- Existing saved state from older development versions may be ignored if it only contained removed mulching or rolling progress.
