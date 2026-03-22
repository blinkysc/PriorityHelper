# Changelog

All notable changes to PriorityHelper will be documented in this file.

## [1.2.0] - 2026-03-21

### Added
- Core `RunSimulation()` framework: generic sim loop that any class can use.
  Class provides a priority function, core handles CD tracking, time
  advancement, and recommendation building.
- Priority function now receives current recommendations, enabling
  tier-aware logic (e.g., Prot 969 always picks 6s ability before 9s)
- Sim advances time to next ability when on CD, so abilities flow naturally
  through Rec3 -> Rec2 -> Rec1 as cooldowns tick down
- 5-minute combat simulation tests at 200Hz with 100 randomized CD configs

### Fixed
- Prot 969: 6s abilities (SoR/HotR) now ALWAYS take Rec1, matching wotlk
  sim APL. Consecration can no longer jump into Rec1 when a 6s ability is
  on cooldown.
- Smoothing duplicate prevention: abilities can no longer appear in multiple
  slots simultaneously
- Divine Plea now appears when mana < 40% (was buried below all 9s abilities)
- Minimap button detachable by MBB and similar addons (guard against double
  creation, defer to PLAYER_LOGIN)

### Changed
- Prot rotation rewritten with simulation: predictions based on actual CD
  tracking instead of snapshot queue
- Ret priority order updated to match wotlk sim APL: Judge > CS > DS
- Smoothing rewritten: forward-only placement prevents abilities from
  moving backward in the display

## [1.1.7] - 2026-03-15

### Fixed
- Revert Paladin to queue-based priority system (sim approach caused duplicates
  and incorrect ordering)
- Fix duplicate abilities appearing in Prot recommendations (SoR/HotR removed
  from queue, only handled by interleave logic)
- Duplicate prevention at every insertion point

## [1.1.6] - 2026-03-15

### Added
- Recommendation smoothing system: slots resist changing for 0.3s to prevent
  visual stutter from micro-timing fluctuations

### Removed
- Debug logging system (3.3.5a client restrictions prevent reliable disk writes)

## [1.1.5] - 2026-03-15

### Changed
- Druid Cat sim now uses framework: SimInitEnergy, SimInitGCD (melee haste),
  SimInitRage, SimInitTarget, SimTickEnergy, SimTickCD
- Druid Balance sim now uses framework: SimInitGCD (spell haste), SimCastTime,
  SimInitTarget, SimTickCD
- Cat GCD now haste-adjusted (was hardcoded 1.0s)
- Cat energy wait accounts for GCD minimum
- Energy cap uses sim.energy_max instead of hardcoded 100
- All CD tick-downs use SimTickCD helper

## [1.1.4] - 2026-03-15

### Added
- `SimWaitTime()` framework helper: ensures sim advances by at least one GCD
  when waiting for abilities, preventing low-priority abilities from jumping
  ahead of higher-priority ones that are fractions of a second behind

### Fixed
- Paladin: abilities within one GCD of each other now both resolve before
  priority decides (e.g., Exorcism no longer jumps ahead of CS by 0.3s)
- Prot Paladin: Divine Plea properly simulated in GCD gaps

## [1.1.3] - 2026-03-15

### Added
- Core simulation framework: GCD/haste, mana, energy, rage, cooldown, target helpers
- Mana simulation for Paladin: ability costs, JoW return (25%), Replenishment ticking
- `RegisterManaCosts()`, `RegisterAbilityCooldowns()` framework APIs
- `SimInitGCD()` with melee/spell haste support
- `SimInitMana/Energy/Rage/Target/CD()` helpers for all classes
- Divine Plea integrated into sim (appears in GCD gaps when mana < 40%)

### Fixed
- Paladin GCD now haste-adjusted (was hardcoded 1.5s)
- Judgement CD now respects Improved Judgements talent (8s with 2/2)
- Judgement cooldown sweep now shows in UI (key mismatch fix)
- Divine Plea no longer pops in as Rec1 over DPS abilities

### Changed
- Paladin rotations fully simulation-driven with mana tracking
- Removed seal and Divine Plea snoozing (handled by sim instead)

## [1.1.2] - 2026-03-15

### Added
- Balance Druid simulation system: predicts 3 GCDs ahead like Feral Cat
- Haste-adjusted cast times (Wrath, Starfire) and GCD in Balance sim
- Nature's Splendor talent support for DoT duration (Moonfire 15s, IS 14s)
- Eclipse ICD simulation: properly tracks Lunar ICD through Eclipse expiry

### Fixed
- Balance DoTs no longer flicker — simulation predicts when they'll expire
- Insect Swarm now properly recommended when down (removed overly strict ICD gate)
- Moonfire/IS refresh timing matches wowhead guide ("allow to fall off before reapplying")

### Changed
- Balance rotation rewritten with full simulation (was static priority checks)
- DoT refresh threshold tightened to < 1s remaining (from < 3s pandemic window)

## [1.1.1] - 2026-03-15

### Fixed
- Prot Paladin 969 rotation now properly shows SoR/HotR in upcoming slots
- Added Divine Plea to Prot rotation (mana < 60%)
- Duplicate ability prevention in priority queue

## [1.1.0] - 2026-03-15

### Added
- **Paladin support**: Retribution (DPS) and Protection (Tank) rotation modes
- Minimap button with dropdown for rotation mode selection
- Cooldown snooze system: skipped major CDs (e.g. Avenging Wrath) stop nagging for 60s
- Target-aware priorities: Exorcism prioritized vs Undead/Demon (100% crit), Holy Wrath only shown vs valid targets
- `UnitCreatureType` detection for Paladin ability conditions

### Fixed
- GCD detection now properly handles haste and spells with real CDs as reference
- Permanent buffs (Righteous Fury, auras, seals) no longer treated as expired
- Init lifecycle: guards against double-run, Config.lua forces init if ADDON_LOADED fires early
- Removed seal recommendations from Paladin (player decision based on AoE vs single target)

### Changed
- Balance Druid rotation rewritten based on wowsim APL: proper ICD-aware Eclipse fishing, correct Insect Swarm timing
- Removed Maul from Bear and Bearweave rotations (player decision)
- Bearweave toggle now driven by mode selection instead of DB setting

## [1.0.0] - 2026-03-15

### Added
- Initial release as PriorityHelper (renamed from DruidHelper)
- **Druid support**: Cat (DPS), Cat + Bearweave (DPS), Bear (Tank), Boomkin (DPS)
- Generic framework with registration API for multi-class support
- Feral cat rotation with SR/Rip desync logic, Clearcasting, FF weaving
- Bearweaving (Lacerateweave) with entry/exit timing
- Balance rotation with Eclipse fishing
- Movable icon display with cooldown sweep animations
- Range indicator for melee abilities
- Live debug frame (`/ph live`)
- Slash commands (`/ph`)
