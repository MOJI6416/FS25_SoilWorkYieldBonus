# Changelog

## 1.0.0.24

- Added multiplayer synchronization for field bonus progress shown in the field information panel.
- Server remains authoritative for recording soil work, saving state, and applying harvest bonuses.
- Added initial client state sync through the standard mission client-state path.
- Kept mulching and soil rolling untouched because the base game already handles those yield effects.
- Fixed release packaging expectations so `scripts/SoilWorkYieldBonus.lua` is loaded from the zip root structure.

## 1.0.0.0

- Initial public MVP.
- Added disking bonus up to `+4%`.
- Added cultivating bonus up to `+6%`.
- Prevented stacking between disking and cultivating.
- Added field coverage threshold before a bonus becomes active.
- Added savegame persistence in `soilWorkYieldBonus.xml`.
- Added standard field information panel display.
