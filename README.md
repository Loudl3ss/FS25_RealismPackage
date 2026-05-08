# FS25_RealismPackage

A Farming Simulator 25 mod that introduces realistic vehicle maintenance, wear, and damage mechanics to replace the game's simplified defaults.

---

## Features

- **Wear System** — Vehicles accumulate wear over operating hours based on their type (tractor, combine, truck, car). Wear builds up realistically and must be addressed through servicing.
- **Damage Logic** — Vehicles take damage from collisions (speed-threshold based) and from driving while already damaged (engine power degrades gradually as damage increases, down to a configurable floor). Three difficulty profiles control how fast damage and wear accumulate.
- **Air Filter System** — Engines clog their air filters over time. Filters degrade faster in dusty conditions (when implements are actively working) and slower during light use. A dirty filter reduces engine power output.
- **Workshop Actions** — Two service actions are added to the workshop screen:
  - **Full Service** — Resets wear and replaces the air filter. Cost scales with accumulated wear.
  - **Clean Air Filter** — Cheaper targeted action to restore filter condition and recover lost power.
- **In-Game Settings Menu** — A settings panel injected into the game's options screen lets players toggle wear, damage, and air filter systems individually, and switch difficulty profiles at any time without restarting.
- **Multiplayer Support** — All settings changes and workshop actions are synchronized across clients via custom network events.

---

## Difficulty Profiles

| Profile     | Service Interval (car / truck) | Operating Hours Between Services | Annual Service Cycle | Damage Scale |
|-------------|-------------------------------|----------------------------------|----------------------|--------------|
| `FS25`      | 1,000 / 3,000 km              | 50 h                             | ~36.5 days           | 0.1×         |
| `NORMAL`    | 5,000 / 15,000 km             | 250 h                            | ~182.5 days          | 0.5×         |
| `REAL_LIFE` | 10,000 / 30,000 km            | 500 h                            | 365 days             | 1.0×         |

The default profile is **NORMAL**. All three can be switched live from the settings menu.

---

## Logic Overview

### Wear System (`WearSystem.lua`)
Classifies each vehicle as a tractor, combine, harvester, truck, or car using its type name, category, and attached specializations. Wear rate is calculated per vehicle class against the active difficulty profile's operating-hour interval.

### Damage Logic (`DamageLogic.lua`)
- **Collision damage**: Triggers above a configurable speed threshold (default 20 km/h). Damage per hit scales with impact intensity and is capped per collision.
- **Speed-drop fallback**: Detects sudden deceleration (e.g., hitting an object at low speed) as an alternative collision signal when direct impact data is unavailable.
- **Engine power penalty**: Once damage exceeds 15%, engine output is reduced proportionally. At full damage the vehicle is limited to a minimum speed (configurable, default ~5 km/h reference).

### Air Filter System (`AirFilterSystem.lua`)
- Tracks filter condition per vehicle.
- Degrades faster when implements are actively attached and working (dusty environment), using a shorter interval (default 30 h vs. 100 h clean).
- Filter degradation is further accelerated in `FS25` profile (3×) and `NORMAL` profile (2×) relative to `REAL_LIFE`.
- Applies an engine power multiplier on top of the damage penalty when the filter is dirty.

### Workshop Costs (`DamageLogic.lua` — `WORKSHOP_COST`)
```
Full Service  = 1,500 base + (wear × 4,500) + (filter condition × 400)
Filter Clean  =   300 base + (wear × 1,800)
```

### Settings & Networking (`RealismSettings.lua`, `RealismSettingsEvent.lua`, `RealismWorkshopActionEvent.lua`)
Settings are stored on the `RealismPackage` global table and persisted across sessions. Changes are broadcast from client to server via `RealismSettingsEvent`. Workshop actions are sent via `RealismWorkshopActionEvent` and executed server-side to keep the simulation authoritative.

---

## File Structure

```
FS25_RealismPackage/
├── modDesc.xml                        # Mod metadata, input bindings, i18n keys
├── icon.dds                           # Mod icon
└── scripts/
    ├── RealismPackage.lua             # Entry point, settings table, specialization injection
    ├── DamageLogic.lua                # Collision & engine-damage specialization
    ├── WearSystem.lua                 # Vehicle classification & wear calculation
    ├── AirFilterSystem.lua            # Air filter degradation & power penalty
    ├── RealismSettings.lua            # In-game settings UI panel
    ├── RealismSettingsEvent.lua       # Network event for settings sync
    ├── RealismWorkshopActions.lua     # Workshop screen button injection
    └── RealismWorkshopActionEvent.lua # Network event for workshop actions
```

---

## Installation

1. Copy the `FS25_RealismPackage` folder into your Farming Simulator 25 `mods/` directory.
2. Enable the mod in the mod manager before starting or loading a save.
3. Adjust settings via **Options → Realism Package** in-game.