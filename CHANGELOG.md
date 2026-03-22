# Changelog

All notable changes to PriorityHelper will be documented in this file.

## [1.9.0] - 2026-03-22

### Added
- **Mage support**: Arcane, Fire, Frost rotation modes
- Arcane: AB stack building to 4, AM dump at max stacks, Missile Barrage proc at 3+, Icy Veins/Arcane Power/Mirror Image/POM cooldown stacking, Evocation mana recovery
- Fire: Hot Streak instant Pyroblast, Living Bomb (only recast after expiry for explosion), Improved Scorch maintenance, Combustion (buff-aware), Brain Freeze instant Fireball, Fireball filler
- Frost: Fingers of Frost Ice Lance (stack consumption), Deep Freeze with FoF, Icy Veins, Frostbolt filler
- Arcane Blast stack tracking via combat log (not exposed via UnitBuff in 3.3.5a)
- Corrected buff IDs for AzerothCore: Hot Streak (48108), Combustion (28682)

### Known Issues
- Arcane Blast stack tracking via combat log may be unreliable in some edge cases
- Brain Freeze proc not detectable via UnitBuff on AzerothCore — Frost rotation cannot react to this proc
- Mage rotations need further tuning and testing

## [1.8.0] - 2026-03-22

### Added
- **Rogue support**: Assassination, Combat, Subtlety rotation modes
- Assassination: SnD/HfB maintenance, Envenom at 4-5 CP, Cut to the Chase SnD refresh, Mutilate builder
- Combat: SnD maintenance, Rupture at 5 CP, Eviscerate finisher, Killing Spree/Adrenaline Rush at low energy, Sinister Strike builder with talent cost reduction
- Subtlety: SnD maintenance, Shadow Dance with Ambush spam, Rupture/Eviscerate finishers, Hemorrhage builder
- All specs: energy regen sim with getWaitTime for accurate lookahead

## [1.7.0] - 2026-03-22

### Added
- **Death Knight support**: Blood (Tank), Frost (DPS), Unholy (DPS) rotation modes
- Rune system: real-time rune tracking via GetRuneCooldown/GetRuneType with Death rune substitution
- Rune recovery simulation: reads actual per-slot CD timers, recovers runes during sim lookahead
- Haste-adjusted rune CDs using observed duration from game (matches AzerothCore formula)
- Presence awareness: Blood recommends Frost Presence, Frost/Unholy recommend Unholy Presence
- Presence form handlers via GetShapeshiftForm (same pattern as Warrior stances)
- Disease management: Frost Fever/Blood Plague tracking with spec-appropriate refresh
- Glyph of Disease: Pestilence refreshes both diseases (Blood <=4s, Frost <=3s thresholds per sim APL)
- Unholy skips Pestilence for single target (matches uh_2h_ss APL)
- Proc awareness: Killing Machine, Rime/Freezing Fog (free Howling Blast), Sudden Doom (free Death Coil)
- Mode icons use presence textures (Blood=red, Frost=blue, Unholy=green)

## [1.6.0] - 2026-03-22

### Added
- **Hunter support**: Beast Mastery, Marksmanship, Survival rotation modes
- BM: Bestial Wrath, Kill Command, Serpent Sting, Multi/Aimed/Arcane Shot, Steady Shot filler
- MM: Chimera Shot (refreshes Serpent Sting), Aimed Shot, Improved Steady Shot proc awareness, Arcane Shot
- Survival: Explosive Shot, Black Arrow (Lock and Load trigger), LnL stack consumption, Explosive/Arcane shared CD
- All specs: Kill Shot execute phase, haste-adjusted Steady Shot cast time, glyph-aware CD reductions

## [1.5.0] - 2026-03-22

### Added
- **Warrior support**: Arms (DPS), Fury (DPS), Protection (Tank) rotation modes
- Arms: Mortal Strike, Taste for Blood Overpower proc, Sudden Death Execute, Rend maintenance, Slam filler
- Fury: Bloodthirst, Whirlwind, Bloodsurge instant Slam proc, Execute phase, Rend
- Protection: Shield Slam (Sword and Board procs), Revenge, Shockwave, Thunder Clap/Demo Shout maintenance, Devastate filler
- Stance awareness: recommends correct stance (Battle/Berserker/Defensive) via GetShapeshiftForm form handlers
- Rage estimation from auto-attacks using UnitAttackSpeed for accurate REC1-3 lookahead
- Prot tanks get bonus rage income estimate for damage taken

## [1.4.0] - 2026-03-22

### Added
- **Shaman support**: Enhancement (DPS) and Elemental (DPS) rotation modes
- Enhancement: Feral Spirit, MW5 instant Lightning Bolt, Stormstrike, Flame Shock/Earth Shock with shared shock CD, Fire Nova, Lava Lash, Shamanistic Rage mana recovery
- Elemental: Elemental Mastery, Flame Shock maintenance for Lava Burst auto-crit, Lava Burst on CD, Chain Lightning, Lightning Bolt filler with haste-adjusted cast times
- Enhancement wait-for-CD logic: advances sim to nearest ability when nothing is ready

## [1.3.0] - 2026-03-22

### Added
- **Warlock support**: Affliction, Demonology, Destruction rotation modes
- Affliction: Haunt on CD, Corruption/UA/CoA maintenance, Drain Soul execute, Nightfall procs, Shadow Bolt filler
- Demonology: Metamorphosis + Immolation Aura, Demonic Empowerment on CD, Decimation proc Soul Fire, Molten Core proc Incinerate
- Destruction: Immolate engine, Conflagrate (triggers Backdraft), Chaos Bolt, Incinerate filler with Backdraft cast reduction
- All Warlock specs: Life Tap mana management, Glyph of Life Tap buff uptime
- Cast time awareness: sim reads UnitCastingInfo/UnitChannelInfo and advances past in-progress casts before picking recommendations
- Detachable minimap button: right-click to toggle free movement, right-click again to reattach

### Fixed
- Caster sim predictions now use haste-adjusted cast times (was using raw base cast times)
- Duplicate icon bug when CreateMinimapButton called twice
- Demonic Empowerment no longer snoozeable (core rotational ability)

### Changed
- Core RunSimulation accounts for cast_remains (longer casts like Shadow Bolt) in addition to gcd_remains

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
