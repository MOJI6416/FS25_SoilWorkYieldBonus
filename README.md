# SoilWorkYieldBonus

SoilWorkYieldBonus is a lightweight gameplay script mod for Farming Simulator 25 that gives soil preparation work a small, clear yield impact.

The mod is intentionally simple: no settings menu, no custom icons on the map, and no extra configuration UI. It runs in the background and adds one compact line to the standard field information panel.

## Features

- Disking gives up to `+4%` yield bonus.
- Cultivating gives up to `+6%` yield bonus.
- Disking and cultivating do not stack with each other.
- If both operations are present, only the higher soil preparation value is used.
- Maximum bonus from this mod is `+6%`.
- Mulching and soil rolling are not modified by this mod, because the base game already handles their yield effects.
- The active value is shown in the standard field info panel as `Yield bonus`.

## Balance

The goal is to make soil preparation matter without making the economy too generous.

Formula:

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

In the field information panel, a pending bonus is shown as:

```text
Yield bonus: +4% 42/80%
```

An active bonus is shown as:

```text
Yield bonus: +4% 91%
```

## How It Works

The mod tracks soil preparation progress per `fieldId` on the server side.

When harvesting, it applies the active field bonus to the harvested liters through the standard combine harvest path. It multiplies the vanilla harvest amount instead of replacing other base game systems.

Stored state is saved in:

```text
soilWorkYieldBonus.xml
```

The mod does not edit the base game `fields.xml`.

## Compatibility

Designed for Farming Simulator 25.

The mod should work with vanilla equipment and most modded tools that use the standard GIANTS specializations:

- `Cultivator`
- `Cutter`
- `Combine`

The mod does not hook into `Mulcher` or `Roller`.

## Installation

1. Download `FS25_SoilWorkYieldBonus.zip`.
2. Place it in your Farming Simulator 25 `mods` folder.
3. Enable the mod when starting or loading a savegame.

## Notes

- No player-facing settings are added.
- No new map icons are added.
- No custom menu is added.
- Multiplayer is supported.
- Existing saved state from older versions may be ignored if it only contains mulching or rolling progress.
