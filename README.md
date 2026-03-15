# PriorityHelper

A priority rotation helper addon for World of Warcraft 3.3.5a (WotLK). Shows recommended abilities in real-time based on your current state, buffs, debuffs, and cooldowns.

## Supported Classes

### Druid
- **Cat (DPS)** — Full feral cat rotation with SR/Rip desync logic, Clearcasting, FF weaving
- **Cat + Bearweave (DPS)** — Cat rotation with Lacerateweave during energy-starved windows
- **Bear (Tank)** — Bear tank rotation with Lacerate/Mangle priority
- **Boomkin (DPS)** — Balance rotation with ICD-aware Eclipse fishing (based on wowsim APL)

## Installation

1. Download or clone this repository
2. Copy the `PriorityHelper` folder to your `Interface/AddOns` directory
3. Restart WoW or `/reload`

## Usage

Click the **minimap button** to select your rotation mode. The addon shows the next 3 recommended abilities when you have an attackable target.

### Slash Commands

| Command | Description |
|---------|-------------|
| `/ph` | Show all commands |
| `/ph toggle` | Enable/disable addon |
| `/ph lock` | Lock/unlock display position |
| `/ph reset` | Reset display position |
| `/ph scale <0.5-2.0>` | Set display scale |
| `/ph live` | Toggle live debug frame |
| `/ph cat` | Show feral cat status |
| `/ph bear` | Show bear/bearweave status |
| `/ph minimap` | Toggle minimap button |

## Requirements

- World of Warcraft 3.3.5a client

## License

MIT
