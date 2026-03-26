-- Classes/DeathKnight/Core.lua
-- Priority rotation logic for Death Knight specs (3.3.5a compatible)
-- Uses core RunSimulation with rune-aware priority

local DH = PriorityHelper
if not DH then return end

if select(2, UnitClass("player")) ~= "DEATHKNIGHT" then
    return
end

local ns = DH.ns
local class = DH.Class
local state = DH.State

-- ============================================================================
-- RUNE COST HELPERS
-- Death runes can substitute for any rune type.
-- canAfford checks if rune costs are met, spending death runes as needed.
-- spendRunes deducts from sim rune counts.
-- ============================================================================

---Returns true when rune and RP requirements can be paid with typed+death runes.
local function canAfford(sim, bCost, fCost, uCost, rpCost)
    rpCost = rpCost or 0
    if sim.rp < rpCost then return false end

    local bNeed = math.max(0, bCost - sim.blood)
    local fNeed = math.max(0, fCost - sim.frost)
    local uNeed = math.max(0, uCost - sim.unholy)
    local deathNeed = bNeed + fNeed + uNeed
    if deathNeed > sim.death then return false end
    return true
end

---Consumes requested runes, using death runes as overflow, then grants RP.
local function spendRunes(sim, bCost, fCost, uCost, rpGain)
    -- Spend typed runes first, overflow to death
    local bSpend = math.min(bCost, sim.blood)
    sim.blood = sim.blood - bSpend
    local bOver = bCost - bSpend

    local fSpend = math.min(fCost, sim.frost)
    sim.frost = sim.frost - fSpend
    local fOver = fCost - fSpend

    local uSpend = math.min(uCost, sim.unholy)
    sim.unholy = sim.unholy - uSpend
    local uOver = uCost - uSpend

    sim.death = sim.death - (bOver + fOver + uOver)

    -- Gain RP
    sim.rp = math.min(sim.rp_max, sim.rp + (rpGain or 10))
end

---Spends runic power without letting it drop below zero.
local function spendRP(sim, cost)
    sim.rp = math.max(0, sim.rp - cost)
end

-- Both diseases up?
---Returns true when Frost Fever and Blood Plague are both active.
local function diseasesUp(sim)
    return sim.ff_up and sim.bp_up
end

---Returns time until next rune of the given type is ready.
local function nextRuneReady(sim, runeType)
    if not sim.rune_recovery or not sim.rune_recovery[runeType] then
        return 999
    end
    local timers = sim.rune_recovery[runeType]
    if timers[1] then
        return timers[1]
    end
    return 999
end

-- Preserve a Blood/Death rune for Glyph of Disease refresh windows.
-- If we spend the last Blood/Death rune too early, diseases can drop and force IT+PS.
---Determines whether to reserve a blood/death rune for upcoming Pestilence refresh.
-- pendingDeathCost: number of Death runes the candidate spell will consume (default 0).
-- The check accounts for those runes being spent so we don't stave Pest of its rune.
local function shouldReserveDiseaseRefreshRune(sim, pendingDeathCost)
    if not sim.has_glyph_disease or not diseasesUp(sim) then
        return false
    end

    local availableBD = (sim.blood or 0) + (sim.death or 0)
    if availableBD - (pendingDeathCost or 0) >= 1 then
        return false
    end

    local minDiseaseRemains = math.min(sim.ff_remains or 0, sim.bp_remains or 0)
    if minDiseaseRemains > 8 then
        return false
    end

    -- Wowsim uses a tighter 1.5s Pest window for sub-Blood and a looser 3.0s
    -- window for sub-Unholy/Epidemic. We keep 1.5s here for both specs for now;
    -- this can be loosened later if the reserve logic proves too strict.
    local timeUntilSafeRefresh = math.max(0, minDiseaseRemains - 1.5)
    local nextBD = math.min(nextRuneReady(sim, "blood"), nextRuneReady(sim, "death"))
    return nextBD > timeUntilSafeRefresh
end

---Returns the number of Death runes Obliterate would consume (0, 1, or 2).
-- Oblit costs 1 Frost + 1 Unholy; any shortfall is covered by Death runes.
local function obliterateDeathRuneCost(sim)
    local frostShortfall = math.max(0, 1 - (sim.frost or 0))
    local unholyShortfall = math.max(0, 1 - (sim.unholy or 0))
    return frostShortfall + unholyShortfall
end

-- ============================================================================
-- RUNE RECOVERY TRACKING
-- Reads actual rune cooldown timers to estimate when runes come back.
-- tickTime restores runes as their CDs expire during sim lookahead.
-- ============================================================================

-- Get per-rune cooldown remaining for all 6 slots, grouped by type
-- Returns recovery timers AND the observed haste-adjusted rune CD duration
---Reads rune cooldowns and returns per-type recovery timers and observed duration.
local function GetRuneRecoveryTimes()
    local recovery = { blood = {}, frost = {}, unholy = {}, death = {} }
    local observedDuration = 10  -- fallback
    local now = GetTime()
    for i = 1, 6 do
        local start, duration, ready = GetRuneCooldown(i)
        if start and duration and duration > 0 then
            -- Capture the actual haste-adjusted rune CD the game uses
            if duration > 1 then
                observedDuration = duration
            end
            if not ready then
                local remains = math.max(0, start + duration - now)
                local runeType = GetRuneType(i)
                if runeType == 1 then table.insert(recovery.blood, remains)
                elseif runeType == 2 then table.insert(recovery.unholy, remains)
                elseif runeType == 3 then table.insert(recovery.frost, remains)
                elseif runeType == 4 then table.insert(recovery.death, remains)
                end
            end
        end
    end
    table.sort(recovery.blood)
    table.sort(recovery.frost)
    table.sort(recovery.unholy)
    table.sort(recovery.death)
    return recovery, observedDuration
end

-- Tick rune recovery: as sim time advances, runes come off CD
---Advances rune recovery timers and restores runes that have completed cooldown.
local function tickRuneRecovery(sim, seconds)
    if not sim.rune_recovery then return end
    for _, runeType in ipairs({"blood", "frost", "unholy", "death"}) do
        local timers = sim.rune_recovery[runeType]
        if timers then
            local i = 1
            while i <= #timers do
                timers[i] = timers[i] - seconds
                if timers[i] <= 0 then
                    -- Rune recovered
                    sim[runeType] = (sim[runeType] or 0) + 1
                    table.remove(timers, i)
                else
                    i = i + 1
                end
            end
        end
    end
end

-- When spending a rune in the sim, queue its recovery using observed duration
---Queues cooldown recovery for a spent rune of the given type.
local function queueRuneRecovery(sim, runeType)
    if not sim.rune_recovery then return end
    if not sim.rune_recovery[runeType] then sim.rune_recovery[runeType] = {} end
    -- Use the observed rune CD from the game (already haste-adjusted)
    table.insert(sim.rune_recovery[runeType], sim.rune_cd_duration or 10)
end

-- Updated spendRunes that queues recovery
---Consumes runes, queues their recovery timers, and grants RP.
local function spendRunesTracked(sim, bCost, fCost, uCost, rpGain)
    -- Spend typed runes first, overflow to death
    local bSpend = math.min(bCost, sim.blood)
    sim.blood = sim.blood - bSpend
    for i = 1, bSpend do queueRuneRecovery(sim, "blood") end
    local bOver = bCost - bSpend

    local fSpend = math.min(fCost, sim.frost)
    sim.frost = sim.frost - fSpend
    for i = 1, fSpend do queueRuneRecovery(sim, "frost") end
    local fOver = fCost - fSpend

    local uSpend = math.min(uCost, sim.unholy)
    sim.unholy = sim.unholy - uSpend
    for i = 1, uSpend do queueRuneRecovery(sim, "unholy") end
    local uOver = uCost - uSpend

    local deathSpend = bOver + fOver + uOver
    sim.death = sim.death - deathSpend
    for i = 1, deathSpend do queueRuneRecovery(sim, "death") end

    -- Gain RP
    sim.rp = math.min(sim.rp_max, sim.rp + (rpGain or 10))
end

-- ============================================================================
-- BLOOD (TANK) ROTATION
-- ============================================================================

local bloodConfig = {
    gcdType = "melee",
    maxRecs = 3,
    allowDupes = true,
    cds = {
        dancing_rune_weapon = "dancing_rune_weapon",
        vampiric_blood = "vampiric_blood",
        bone_shield = "bone_shield",
        empower_rune_weapon = "empower_rune_weapon",
        rune_tap = "rune_tap",
    },
    baseCDs = {
        dancing_rune_weapon = 60,
        vampiric_blood = 60,
        bone_shield = 60,
        empower_rune_weapon = 300,
        rune_tap = 60,
    },
    auras = {
        { up = "ff_up", remains = "ff_remains" },
        { up = "bp_up", remains = "bp_remains" },
    },
    initState = function(sim, s)
        -- Runes + recovery timers
        local b, f, u, d = ns.GetRuneCounts()
        sim.blood = b
        sim.frost = f
        sim.unholy = u
        sim.death = d
        sim.rune_recovery, sim.rune_cd_duration = GetRuneRecoveryTimes()

        -- RP
        sim.rp = s.runic_power.current
        sim.rp_max = s.runic_power.max or 100

        -- Diseases
        sim.ff_up = s.debuff.frost_fever.up
        sim.ff_remains = s.debuff.frost_fever.remains
        sim.bp_up = s.debuff.blood_plague.up
        sim.bp_remains = s.debuff.blood_plague.remains

        -- Procs
        sim.sudden_doom = s.buff.sudden_doom.up

        -- Talents
        sim.has_heart_strike = s.talent.heart_strike.rank > 0
        sim.has_drw = s.talent.dancing_rune_weapon.rank > 0
        sim.has_vb = s.talent.vampiric_blood.rank > 0
        sim.has_rune_tap = s.talent.rune_tap.rank > 0
        sim.has_glyph_disease = s.glyph.disease and s.glyph.disease.enabled
        sim.in_frost_presence = s.buff.frost_presence.up
    end,
    getPriority = function(sim, recs)
        -- Blood tank wants Frost Presence
        if not sim.in_frost_presence then
            return "frost_presence"
        end

        -- Glyph of Disease: Pestilence refreshes both diseases (1 Blood rune)
        -- Blood uses <=4s threshold per sim APL
        if sim.has_glyph_disease and sim.ff_up and sim.bp_up
            and (sim.ff_remains < 4 or sim.bp_remains < 4)
            and canAfford(sim, 1, 0, 0) and sim.ttd > 9 then
            return "pestilence"
        end

        -- Diseases: Icy Touch if Frost Fever down/expiring
        if (not sim.ff_up or sim.ff_remains < 3) and canAfford(sim, 0, 1, 0) then
            return "icy_touch"
        end

        -- Plague Strike if Blood Plague down/expiring
        if (not sim.bp_up or sim.bp_remains < 3) and canAfford(sim, 0, 0, 1) then
            return "plague_strike"
        end

        -- Death Strike (primary survival tool, Frost+Unholy) - only with diseases
        if diseasesUp(sim) and canAfford(sim, 0, 1, 1) then
            return "death_strike"
        end

        -- Dancing Rune Weapon (major tank CD)
        if sim.has_drw and sim:ready("dancing_rune_weapon") and not DH:IsSnoozed("dancing_rune_weapon") and sim.rp >= 60 then
            return "dancing_rune_weapon"
        end

        -- Heart Strike (Blood rune, main threat) - only with diseases
        if sim.has_heart_strike and diseasesUp(sim) and canAfford(sim, 1, 0, 0) then
            return "heart_strike"
        end

        -- Blood Tap: convert Blood to Death when F/U depleted and ERW not ready
        if sim.blood > 0 and sim.frost == 0 and sim.unholy == 0 and sim.death == 0
            and not sim:ready("empower_rune_weapon") then
            return "blood_tap"
        end

        -- Sudden Doom proc: free Death Coil
        if sim.sudden_doom then
            return "death_coil"
        end

        -- Death Coil (RP dump)
        if sim.rp >= 40 then
            return "death_coil"
        end

        -- Empower Rune Weapon (no F/U/Death runes available)
        if sim.frost == 0 and sim.unholy == 0 and sim.death == 0
            and sim:ready("empower_rune_weapon") and not DH:IsSnoozed("empower_rune_weapon") then
            return "empower_rune_weapon"
        end

        -- Horn of Winter (free GCD, RP generation)
        return "horn_of_winter"
    end,
    onCast = function(sim, key)
        if key == "frost_presence" then
            sim.in_frost_presence = true
        elseif key == "icy_touch" then
            spendRunesTracked(sim, 0, 1, 0, 10)
            sim.ff_up = true
            sim.ff_remains = 15
        elseif key == "plague_strike" then
            spendRunesTracked(sim, 0, 0, 1, 10)
            sim.bp_up = true
            sim.bp_remains = 15
        elseif key == "death_strike" then
            spendRunesTracked(sim, 0, 1, 1, 15)
        elseif key == "heart_strike" then
            spendRunesTracked(sim, 1, 0, 0, 10)
        elseif key == "death_coil" then
            if not sim.sudden_doom then
                spendRP(sim, 40)
            end
            sim.sudden_doom = false
        elseif key == "dancing_rune_weapon" then
            spendRP(sim, 60)
        elseif key == "blood_tap" then
            if sim.blood > 0 then
                sim.blood = sim.blood - 1
                sim.death = sim.death + 1
            end
        elseif key == "empower_rune_weapon" then
            sim.blood = 2
            sim.frost = 2
            sim.unholy = 2
            sim.death = 0
            sim.rp = math.min(sim.rp_max, sim.rp + 25)
            sim.rune_recovery = { blood = {}, frost = {}, unholy = {}, death = {} }
        elseif key == "pestilence" then
            spendRunesTracked(sim, 1, 0, 0, 10)
            if sim.has_glyph_disease then
                sim.ff_remains = 15
                sim.bp_remains = 15
            end
        elseif key == "horn_of_winter" then
            sim.rp = math.min(sim.rp_max, sim.rp + 10)
        end
    end,
    tickTime = function(sim, seconds)
        tickRuneRecovery(sim, seconds)
    end,
    getWaitTime = function(sim)
        -- Find nearest rune recovery
        local nearest = 999
        if sim.rune_recovery then
            for _, timers in pairs(sim.rune_recovery) do
                if timers[1] and timers[1] < nearest then
                    nearest = timers[1]
                end
            end
        end
        if nearest < 999 then return nearest end
        return sim.gcd
    end,
}

---Runs Blood DK simulation and returns recommendation list.
local function GetBloodRecommendations(addon)
    return DH:RunSimulation(state, bloodConfig)
end

-- ============================================================================
-- FROST (DPS) ROTATION
-- ============================================================================

local frostConfig = {
    gcdType = "melee",
    maxRecs = 3,
    allowDupes = true,
    cds = {
        unbreakable_armor = "unbreakable_armor",
        blood_tap = "blood_tap",
        horn_of_winter = "horn_of_winter",
        empower_rune_weapon = "empower_rune_weapon",
    },
    baseCDs = {
        unbreakable_armor = 60,
        blood_tap = 60,
        horn_of_winter = 20,
        empower_rune_weapon = 300,
    },
    auras = {
        { up = "ff_up", remains = "ff_remains" },
        { up = "bp_up", remains = "bp_remains" },
    },
    initState = function(sim, s)
        -- Runes + recovery timers
        local b, f, u, d = ns.GetRuneCounts()
        sim.blood = b
        sim.frost = f
        sim.unholy = u
        sim.death = d
        sim.rune_recovery, sim.rune_cd_duration = GetRuneRecoveryTimes()

        -- RP
        sim.rp = s.runic_power.current
        sim.rp_max = s.runic_power.max or 100

        -- Diseases
        sim.ff_up = s.debuff.frost_fever.up
        sim.ff_remains = s.debuff.frost_fever.remains
        sim.bp_up = s.debuff.blood_plague.up
        sim.bp_remains = s.debuff.blood_plague.remains

        -- Procs
        sim.killing_machine = s.buff.killing_machine.up
        sim.rime = s.buff.freezing_fog.up

        -- Talents
        sim.has_howling_blast = s.talent.howling_blast.rank > 0
        sim.has_frost_strike = s.talent.frost_strike.rank > 0
        sim.has_unbreakable_armor = s.talent.unbreakable_armor.rank > 0
        sim.unbreakable_armor_up = s.buff.unbreakable_armor.up
        sim.horn_of_winter_up = s.buff.horn_of_winter.up
        sim.strength_of_earth_totem_up = s.buff.strength_of_earth_totem.up

        -- Epidemic talent: +3s disease duration per rank (max rank 3 = +6s)
        sim.disease_duration = 15 + (s.talent.epidemic.rank or 0) * 3

        -- Glyph of Frost Strike (32 RP instead of 40)
        sim.fs_cost = (s.glyph.frost_strike and s.glyph.frost_strike.enabled) and 32 or 40
        sim.has_glyph_disease = s.glyph.disease and s.glyph.disease.enabled
        sim.in_blood_presence = s.buff.blood_presence.up
    end,
    getPriority = function(sim, recs)
        -- Keep AP/STR raid buff up: Horn if neither Horn nor Strength of Earth is active
        if not sim.horn_of_winter_up and not sim.strength_of_earth_totem_up
            and sim:ready("horn_of_winter") then
            return "horn_of_winter"
        end

        -- Frost DPS wants Blood Presence for damage
        if not sim.in_blood_presence then
            return "blood_presence"
        end

        -- Glyph of Disease: Pestilence refreshes both diseases (1 Blood rune)
        -- Frost uses <=3s threshold per sim APL
        if sim.has_glyph_disease and sim.ff_up and sim.bp_up
            and (sim.ff_remains < 3 or sim.bp_remains < 3)
            and canAfford(sim, 1, 0, 0) then
            return "pestilence"
        end

        -- Blood Tap emergency: disease refresh fallback.
        -- No Blood/Death rune for Pestilence when diseases are about to expire.
        if sim.has_glyph_disease and sim.ff_up and sim.bp_up
            and (sim.ff_remains < 3 or sim.bp_remains < 3)
            and sim.blood == 0 and sim.death == 0
            and sim:ready("blood_tap") then
            return "blood_tap"
        end

        -- Diseases: Icy Touch if Frost Fever down
        if (not sim.ff_up or sim.ff_remains < 3) and canAfford(sim, 0, 1, 0) then
            return "icy_touch"
        end

        -- Plague Strike if Blood Plague down
        if (not sim.bp_up or sim.bp_remains < 3) and canAfford(sim, 0, 0, 1) then
            return "plague_strike"
        end

        -- Blood Tap opener: convert Blood → Death before UA so UA consumes
        -- a Death rune instead of a Frost rune, keeping F+U paired.
        -- NOTE: wowsim sub-Unholy (Epidemic) does Pest before BT+UA to start
        -- Blood CD earlier; with 21s diseases the window is generous enough
        -- that the current BT→UA→OB order still works safely for both specs.
        if sim.has_unbreakable_armor and not sim.unbreakable_armor_up
            and sim:ready("unbreakable_armor") and not DH:IsSnoozed("unbreakable_armor")
            and sim.death == 0 and sim.blood > 0
            and diseasesUp(sim) and sim:ready("blood_tap") then
            return "blood_tap"
        end

        -- Unbreakable Armor after BT has created a Death rune (or if Death rune already exists)
        if sim.has_unbreakable_armor and not sim.unbreakable_armor_up
            and sim:ready("unbreakable_armor") and not DH:IsSnoozed("unbreakable_armor") then
            return "unbreakable_armor"
        end

        -- Killing Machine: consume on Frost Strike for maximum crit value.
        -- KM only buffs Icy Touch, Howling Blast, and Frost Strike — not Obliterate.
        if sim.killing_machine and sim.has_frost_strike and sim.rp >= sim.fs_cost then
            return "frost_strike"
        end

        -- Rime proc: free Howling Blast (also applies FF).
        -- Skip when KM is active to preserve the proc for Frost Strike.
        if sim.rime and sim.has_howling_blast and not sim.killing_machine then
            return "howling_blast"
        end

        -- Obliterate (main damage, Frost+Unholy) - only with diseases.
        -- OB does not consume KM, so it's safe to cast while KM is up.
        if diseasesUp(sim) and canAfford(sim, 0, 1, 1)
            and not shouldReserveDiseaseRefreshRune(sim, obliterateDeathRuneCost(sim)) then
            return "obliterate"
        end

            -- Empower Rune Weapon: fire before Frost Strike/Blood Strike when F/U/Blood are all gone
            -- and we cannot reach an Obliterate (e.g. post-Pestilence opener: F:0,U:0,B:0,D:1 left).
            -- Note: live updates can still show ERW briefly in slot 2/3 if an earlier projection
            -- is consumed by a higher-priority GCD spender before ERW reaches the top slot.
            if sim.frost == 0 and sim.unholy == 0 and sim.blood == 0
                and not canAfford(sim, 0, 1, 1)
                and sim:ready("empower_rune_weapon") and not DH:IsSnoozed("empower_rune_weapon") then
                return "empower_rune_weapon"
            end

        -- Frost Strike (RP dump)
        if sim.has_frost_strike and sim.rp >= sim.fs_cost then
            return "frost_strike"
        end

        -- Rime fallback: if we couldn't OB or FS above, use the Rime proc now
        if sim.rime and sim.has_howling_blast then
            return "howling_blast"
        end

        -- Opener Pestilence sync: F+U spent after first OB, Blood rune still available,
        -- ERW is ready (haven't used it yet). Dump the Blood rune on Pestilence to align
        -- all rune timers before ERW resets everything. Requires Glyph of Disease.
        if sim.has_glyph_disease and diseasesUp(sim)
            and sim.frost == 0 and sim.unholy == 0
            and sim.blood > 0
            and sim:ready("empower_rune_weapon") and not DH:IsSnoozed("empower_rune_weapon") then
            return "pestilence"
        end

        -- Blood Strike (Blood rune spender, converts to Death runes)
        -- Keep one Blood/Death rune banked if Glyph of Disease refresh is approaching.
        if canAfford(sim, 1, 0, 0) and not shouldReserveDiseaseRefreshRune(sim, 1) then
            return "blood_strike"
        end

        -- Horn of Winter (filler: only when no rune is about to recover)
        local minRune = math.min(
            nextRuneReady(sim, "blood"), nextRuneReady(sim, "frost"),
            nextRuneReady(sim, "unholy"), nextRuneReady(sim, "death"))
        if sim:ready("horn_of_winter") and minRune > 0.5 then
            return "horn_of_winter"
        end

        return nil
    end,
    onCast = function(sim, key)
        if key == "blood_presence" then
            sim.in_blood_presence = true
        elseif key == "icy_touch" then
            spendRunesTracked(sim, 0, 1, 0, 10)
            sim.ff_up = true
            sim.ff_remains = sim.disease_duration
        elseif key == "plague_strike" then
            spendRunesTracked(sim, 0, 0, 1, 10)
            sim.bp_up = true
            sim.bp_remains = sim.disease_duration
        elseif key == "obliterate" then
            spendRunesTracked(sim, 0, 1, 1, 15)
            sim.killing_machine = false
        elseif key == "howling_blast" then
            if not sim.rime then
                spendRunesTracked(sim, 0, 1, 1, 15)
            end
            sim.rime = false
            sim.ff_up = true
            sim.ff_remains = sim.disease_duration
        elseif key == "unbreakable_armor" then
            if sim.death > 0 then
                sim.death = sim.death - 1
                queueRuneRecovery(sim, "death")
            else
                spendRunesTracked(sim, 0, 1, 0, 0)
            end
            sim.rp = math.min(sim.rp_max, sim.rp + 10)
            sim.unbreakable_armor_up = true
        elseif key == "blood_strike" then
            spendRunesTracked(sim, 1, 0, 0, 10)
        elseif key == "frost_strike" then
            spendRP(sim, sim.fs_cost)
        elseif key == "blood_tap" then
            local hasDepletedBlood = sim.rune_recovery and sim.rune_recovery.blood
                and #sim.rune_recovery.blood > 0
            if hasDepletedBlood then
                -- Activate depleted Blood rune as Death (preserves ready Blood for Pestilence)
                table.remove(sim.rune_recovery.blood, 1)
                sim.death = sim.death + 1
            elseif sim.blood > 0 then
                sim.blood = sim.blood - 1
                sim.death = sim.death + 1
            else
                sim.death = sim.death + 1
            end
        elseif key == "empower_rune_weapon" then
            sim.blood = 2
            sim.frost = 2
            sim.unholy = 2
            sim.death = 0
            sim.rp = math.min(sim.rp_max, sim.rp + 25)
            sim.rune_recovery = { blood = {}, frost = {}, unholy = {}, death = {} }
        elseif key == "pestilence" then
            spendRunesTracked(sim, 1, 0, 0, 10)
            if sim.has_glyph_disease then
                sim.ff_remains = sim.disease_duration
                sim.bp_remains = sim.disease_duration
            end
        elseif key == "horn_of_winter" then
            sim.rp = math.min(sim.rp_max, sim.rp + 10)
            sim.horn_of_winter_up = true
        end
    end,
    tickTime = function(sim, seconds)
        tickRuneRecovery(sim, seconds)
    end,
    getAdvanceTime = function(sim, action)
        if action == "blood_tap" then
            return 0
        end
        return sim.gcd
    end,
    getWaitTime = function(sim)
        local nearest = 999
        if sim.rune_recovery then
            for _, timers in pairs(sim.rune_recovery) do
                if timers[1] and timers[1] < nearest then
                    nearest = timers[1]
                end
            end
        end
        if nearest < 999 then return nearest end
        return sim.gcd
    end,
}

---Runs Frost DK simulation and returns recommendation list.
local function GetFrostRecommendations(addon)
    return DH:RunSimulation(state, frostConfig)
end

-- ============================================================================
-- UNHOLY (DPS) ROTATION
-- ============================================================================

local unholyConfig = {
    gcdType = "melee",
    maxRecs = 3,
    allowDupes = true,
    cds = {
        summon_gargoyle = "summon_gargoyle",
        empower_rune_weapon = "empower_rune_weapon",
        bone_shield = "bone_shield",
    },
    baseCDs = {
        summon_gargoyle = 180,
        empower_rune_weapon = 300,
        bone_shield = 60,
    },
    auras = {
        { up = "ff_up", remains = "ff_remains" },
        { up = "bp_up", remains = "bp_remains" },
    },
    initState = function(sim, s)
        -- Runes + recovery timers
        local b, f, u, d = ns.GetRuneCounts()
        sim.blood = b
        sim.frost = f
        sim.unholy = u
        sim.death = d
        sim.rune_recovery, sim.rune_cd_duration = GetRuneRecoveryTimes()

        -- RP
        sim.rp = s.runic_power.current
        sim.rp_max = s.runic_power.max or 100

        -- Diseases
        sim.ff_up = s.debuff.frost_fever.up
        sim.ff_remains = s.debuff.frost_fever.remains
        sim.bp_up = s.debuff.blood_plague.up
        sim.bp_remains = s.debuff.blood_plague.remains

        -- Procs
        sim.sudden_doom = s.buff.sudden_doom.up

        -- Talents
        sim.has_scourge_strike = s.talent.scourge_strike.rank > 0
        sim.has_gargoyle = s.talent.summon_gargoyle.rank > 0
        sim.has_bone_shield = s.talent.bone_shield.rank > 0
        sim.in_unholy_presence = s.buff.unholy_presence.up
        sim.gargoyle_up = s.buff.summon_gargoyle.up
    end,
    getPriority = function(sim, recs)
        -- Unholy DPS wants Unholy Presence
        if not sim.in_unholy_presence then
            return "unholy_presence"
        end

        -- Diseases: Icy Touch if Frost Fever down
        if (not sim.ff_up or sim.ff_remains < 3) and canAfford(sim, 0, 1, 0) then
            return "icy_touch"
        end

        -- Plague Strike if Blood Plague down
        if (not sim.bp_up or sim.bp_remains < 3) and canAfford(sim, 0, 0, 1) then
            return "plague_strike"
        end

        -- Summon Gargoyle (major CD)
        if sim.has_gargoyle and sim:ready("summon_gargoyle") and not DH:IsSnoozed("summon_gargoyle") and sim.rp >= 60 then
            return "summon_gargoyle"
        end

        -- Scourge Strike (main damage, Frost+Unholy) - only with diseases
        if sim.has_scourge_strike and diseasesUp(sim) and canAfford(sim, 0, 1, 1) then
            return "scourge_strike"
        end

        -- Blood Strike (Blood rune spender, converts to Death runes)
        if canAfford(sim, 1, 0, 0) then
            return "blood_strike"
        end

        -- Blood Tap: convert Blood rune to Death when F/U depleted
        if sim.blood > 0 and sim.frost == 0 and sim.unholy == 0 and sim.death == 0
            and not sim:ready("empower_rune_weapon") then
            return "blood_tap"
        end

        -- Sudden Doom proc: free Death Coil
        if sim.sudden_doom then
            return "death_coil"
        end

        -- Death Coil (RP dump)
        if sim.rp >= 40 then
            return "death_coil"
        end

        -- Empower Rune Weapon (Unholy: use during Gargoyle for max burst)
        if sim.gargoyle_up and sim:ready("empower_rune_weapon") and not DH:IsSnoozed("empower_rune_weapon") then
            return "empower_rune_weapon"
        end

        -- Horn of Winter (free GCD, RP gen)
        return "horn_of_winter"
    end,
    onCast = function(sim, key)
        if key == "unholy_presence" then
            sim.in_unholy_presence = true
        elseif key == "icy_touch" then
            spendRunesTracked(sim, 0, 1, 0, 10)
            sim.ff_up = true
            sim.ff_remains = 15
        elseif key == "plague_strike" then
            spendRunesTracked(sim, 0, 0, 1, 10)
            sim.bp_up = true
            sim.bp_remains = 15
        elseif key == "scourge_strike" then
            spendRunesTracked(sim, 0, 1, 1, 15)
        elseif key == "blood_strike" then
            spendRunesTracked(sim, 1, 0, 0, 10)
        elseif key == "death_coil" then
            if not sim.sudden_doom then
                spendRP(sim, 40)
            end
            sim.sudden_doom = false
        elseif key == "summon_gargoyle" then
            spendRP(sim, 60)
        elseif key == "blood_tap" then
            if sim.blood > 0 then
                sim.blood = sim.blood - 1
                sim.death = sim.death + 1
            end
        elseif key == "empower_rune_weapon" then
            sim.blood = 2
            sim.frost = 2
            sim.unholy = 2
            sim.death = 0
            sim.rp = math.min(sim.rp_max, sim.rp + 25)
            sim.rune_recovery = { blood = {}, frost = {}, unholy = {}, death = {} }
        elseif key == "pestilence" then
            spendRunesTracked(sim, 1, 0, 0, 10)
            if sim.has_glyph_disease then
                sim.ff_remains = 15
                sim.bp_remains = 15
            end
        elseif key == "horn_of_winter" then
            sim.rp = math.min(sim.rp_max, sim.rp + 10)
        end
    end,
    tickTime = function(sim, seconds)
        tickRuneRecovery(sim, seconds)
    end,
    getWaitTime = function(sim)
        local nearest = 999
        if sim.rune_recovery then
            for _, timers in pairs(sim.rune_recovery) do
                if timers[1] and timers[1] < nearest then
                    nearest = timers[1]
                end
            end
        end
        if nearest < 999 then return nearest end
        return sim.gcd
    end,
}

---Runs Unholy DK simulation and returns recommendation list.
local function GetUnholyRecommendations(addon)
    return DH:RunSimulation(state, unholyConfig)
end

-- ============================================================================
-- ROTATION MODES
-- ============================================================================

DH:RegisterMode("blood_dk", {
    name = "Blood (Tank)",
    icon = "Interface\\Icons\\Spell_Deathknight_BloodPresence",
    rotation = function(addon)
        return GetBloodRecommendations(addon)
    end,
})

DH:RegisterMode("frost_dk", {
    name = "Frost (DPS)",
    icon = "Interface\\Icons\\Spell_Deathknight_FrostPresence",
    rotation = function(addon)
        return GetFrostRecommendations(addon)
    end,
})

DH:RegisterMode("unholy_dk", {
    name = "Unholy (DPS)",
    icon = "Interface\\Icons\\Spell_Deathknight_UnholyPresence",
    rotation = function(addon)
        return GetUnholyRecommendations(addon)
    end,
})
