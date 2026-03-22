-- Classes/Warrior/Core.lua
-- Priority rotation logic for Warrior specs (3.3.5a compatible)
-- Uses core RunSimulation for CD-aware predictions

local DH = PriorityHelper
if not DH then return end

if select(2, UnitClass("player")) ~= "WARRIOR" then
    return
end

local ns = DH.ns
local class = DH.Class
local state = DH.State

-- ============================================================================
-- RAGE ESTIMATION
-- Estimate rage income from auto-attacks based on weapon speed.
-- Rough WotLK model: ~15 rage per mainhand hit, ~7.5 per offhand hit.
-- This gives the sim enough rage to look ahead for REC2/REC3.
-- ============================================================================

local function EstimateRageRegen()
    local mhSpeed, ohSpeed = UnitAttackSpeed("player")
    mhSpeed = mhSpeed or 3.0
    local rps = 15 / mhSpeed  -- ~15 rage per mainhand swing
    if ohSpeed and ohSpeed > 0 then
        rps = rps + 7.5 / ohSpeed  -- offhand generates ~half
    end
    return rps
end

-- ============================================================================
-- ARMS ROTATION
-- ============================================================================

local armsConfig = {
    gcdType = "melee",
    maxRecs = 3,
    allowDupes = true,
    resources = {
        {
            field = "rage",
            max = "rage_max",
            regen = 0,  -- set dynamically in initState
            initFrom = function(s) return s.rage.current end,
            initMaxFrom = function(s) return s.rage.max end,
        },
    },
    cds = {
        mortal_strike = "mortal_strike",
        overpower = "overpower",
        execute = "execute",
        bladestorm = "bladestorm",
        recklessness = "recklessness",
    },
    baseCDs = {
        mortal_strike = 6,
        overpower = 5,
        execute = 0,
        bladestorm = 90,
        recklessness = 300,
    },
    auras = {
        { up = "rend_up", remains = "rend_remains" },
    },
    initState = function(sim, s)
        -- Estimated rage regen from auto-attacks
        sim.rage_regen = EstimateRageRegen()

        -- Stance
        sim.in_battle = s.buff.battle_stance.up
        sim.in_defensive = s.buff.defensive_stance.up
        sim.in_berserker = s.buff.berserker_stance.up

        -- Debuffs
        sim.rend_up = s.debuff.rend.up
        sim.rend_remains = s.debuff.rend.remains

        -- Procs
        sim.taste_for_blood = s.buff.taste_for_blood.up
        sim.sudden_death = s.buff.sudden_death.up

        -- Talents
        sim.has_ms = s.talent.mortal_strike.rank > 0
        sim.has_bladestorm = s.talent.bladestorm.rank > 0
        sim.has_taste_for_blood = s.talent.taste_for_blood.rank > 0
        sim.has_sudden_death = s.talent.sudden_death.rank > 0

        -- Glyph of Rending (extends Rend to 21s)
        sim.rend_duration = (s.glyph.rend and s.glyph.rend.enabled) and 21 or 15
    end,
    getPriority = function(sim, recs)
        -- Need Battle Stance for Arms rotation
        if not sim.in_battle then
            return "battle_stance"
        end

        -- Execute phase (target < 20%) - spam Execute
        if sim.in_execute and sim.rage >= 15 then
            return "execute"
        end

        -- Sudden Death proc: Execute outside execute phase
        if sim.has_sudden_death and sim.sudden_death and sim.rage >= 15 then
            return "execute"
        end

        -- Rend: maintain DoT
        if (not sim.rend_up or sim.rend_remains < 2) and sim.rage >= 10 and sim.ttd > 6 then
            return "rend"
        end

        -- Overpower: only when Taste for Blood / dodge proc is active
        if sim.taste_for_blood and sim:ready("overpower") and sim.rage >= 5 then
            return "overpower"
        end

        -- Mortal Strike on CD
        if sim.has_ms and sim:ready("mortal_strike") and sim.rage >= 30 then
            return "mortal_strike"
        end

        -- Recklessness (use when rage is healthy)
        if sim:ready("recklessness") and not DH:IsSnoozed("recklessness") and sim.rage >= 20 then
            return "recklessness"
        end

        -- Slam filler
        if sim.rage >= 15 then
            return "slam"
        end

        return nil
    end,
    onCast = function(sim, key)
        if key == "battle_stance" then
            sim.in_battle = true
            sim.in_berserker = false
            sim.in_defensive = false
        elseif key == "mortal_strike" then
            sim.rage = math.max(0, sim.rage - 30)
        elseif key == "overpower" then
            sim.rage = math.max(0, sim.rage - 5)
            sim.taste_for_blood = false
        elseif key == "rend" then
            sim.rage = math.max(0, sim.rage - 10)
            sim.rend_up = true
            sim.rend_remains = sim.rend_duration
        elseif key == "execute" then
            sim.rage = math.max(0, sim.rage - 15)
            sim.sudden_death = false
        elseif key == "slam" then
            sim.rage = math.max(0, sim.rage - 15)
        end
    end,
    tickTime = function(sim, seconds)
        -- Accumulate rage from auto-attacks
        sim.rage = math.min(sim.rage_max or 100, sim.rage + (sim.rage_regen or 0) * seconds)
    end,
    getWaitTime = function(sim)
        local nearest = 999
        local keys = { "mortal_strike", "overpower" }
        for _, key in ipairs(keys) do
            local cd = sim.cd[key] or 0
            if cd > 0 and cd < nearest then
                nearest = cd
            end
        end
        if nearest < 999 then return nearest end
        return sim.gcd
    end,
}

local function GetArmsRecommendations(addon)
    return DH:RunSimulation(state, armsConfig)
end

-- ============================================================================
-- FURY ROTATION
-- ============================================================================

local furyConfig = {
    gcdType = "melee",
    maxRecs = 3,
    allowDupes = true,
    resources = {
        {
            field = "rage",
            max = "rage_max",
            regen = 0,
            initFrom = function(s) return s.rage.current end,
            initMaxFrom = function(s) return s.rage.max end,
        },
    },
    cds = {
        bloodthirst = "bloodthirst",
        whirlwind = "whirlwind",
        execute = "execute",
        death_wish = "death_wish",
        recklessness = "recklessness",
    },
    baseCDs = {
        bloodthirst = 4,
        whirlwind = 10,
        execute = 0,
        death_wish = 180,
        recklessness = 300,
    },
    auras = {
        { up = "rend_up", remains = "rend_remains" },
    },
    initState = function(sim, s)
        -- Estimated rage regen (fury dual-wields so higher income)
        sim.rage_regen = EstimateRageRegen()

        -- Stance
        sim.in_berserker = s.buff.berserker_stance.up

        -- Debuffs
        sim.rend_up = s.debuff.rend.up
        sim.rend_remains = s.debuff.rend.remains

        -- Procs
        sim.bloodsurge = s.buff.bloodsurge.up

        -- Talents
        sim.has_bt = s.talent.bloodthirst.rank > 0
        sim.has_death_wish = s.talent.death_wish.rank > 0
        sim.has_bloodsurge = s.talent.bloodsurge.rank > 0

        -- Glyph of Whirlwind (reduces CD to 8s)
        sim.ww_cd = (s.glyph.whirlwind and s.glyph.whirlwind.enabled) and 8 or 10

        -- Glyph of Rending
        sim.rend_duration = (s.glyph.rend and s.glyph.rend.enabled) and 21 or 15
    end,
    getPriority = function(sim, recs)
        -- Need Berserker Stance for Fury rotation
        if not sim.in_berserker then
            return "berserker_stance"
        end

        -- Execute phase
        if sim.in_execute and sim.rage >= 15 then
            return "execute"
        end

        -- Bloodsurge proc: instant free Slam
        if sim.has_bloodsurge and sim.bloodsurge then
            return "slam"
        end

        -- Bloodthirst on CD (primary ability)
        if sim.has_bt and sim:ready("bloodthirst") and sim.rage >= 20 then
            return "bloodthirst"
        end

        -- Whirlwind
        if sim:ready("whirlwind") and sim.rage >= 25 then
            return "whirlwind"
        end

        -- Death Wish (when rage is healthy)
        if sim.has_death_wish and sim:ready("death_wish") and not DH:IsSnoozed("death_wish") and sim.rage >= 10 then
            return "death_wish"
        end

        -- Recklessness
        if sim:ready("recklessness") and not DH:IsSnoozed("recklessness") and sim.rage >= 10 then
            return "recklessness"
        end

        -- Rend maintenance
        if (not sim.rend_up or sim.rend_remains < 2) and sim.rage >= 10 and sim.ttd > 10 then
            return "rend"
        end

        -- Slam filler (rage dump)
        if sim.rage >= 30 then
            return "slam"
        end

        return nil
    end,
    onCast = function(sim, key)
        if key == "berserker_stance" then
            sim.in_berserker = true
            sim.in_battle = false
            sim.in_defensive = false
        elseif key == "bloodthirst" then
            sim.rage = math.max(0, sim.rage - 20)
        elseif key == "whirlwind" then
            sim.rage = math.max(0, sim.rage - 25)
            sim.cd["whirlwind"] = sim.ww_cd
        elseif key == "slam" then
            if not sim.bloodsurge then
                sim.rage = math.max(0, sim.rage - 15)
            end
            sim.bloodsurge = false
        elseif key == "execute" then
            sim.rage = math.max(0, sim.rage - 15)
        elseif key == "rend" then
            sim.rage = math.max(0, sim.rage - 10)
            sim.rend_up = true
            sim.rend_remains = sim.rend_duration
        end
    end,
    tickTime = function(sim, seconds)
        sim.rage = math.min(sim.rage_max or 100, sim.rage + (sim.rage_regen or 0) * seconds)
    end,
    getWaitTime = function(sim)
        local nearest = 999
        local keys = { "bloodthirst", "whirlwind" }
        for _, key in ipairs(keys) do
            local cd = sim.cd[key] or 0
            if cd > 0 and cd < nearest then
                nearest = cd
            end
        end
        if nearest < 999 then return nearest end
        return sim.gcd
    end,
}

local function GetFuryRecommendations(addon)
    return DH:RunSimulation(state, furyConfig)
end

-- ============================================================================
-- PROTECTION ROTATION
-- ============================================================================

local protConfig = {
    gcdType = "melee",
    maxRecs = 3,
    allowDupes = true,
    resources = {
        {
            field = "rage",
            max = "rage_max",
            regen = 0,
            initFrom = function(s) return s.rage.current end,
            initMaxFrom = function(s) return s.rage.max end,
        },
    },
    cds = {
        shield_slam = "shield_slam",
        revenge = "revenge",
        devastate = "devastate",
        shockwave = "shockwave",
        thunder_clap = "thunder_clap",
        concussion_blow = "concussion_blow",
        shield_block = "shield_block",
    },
    baseCDs = {
        shield_slam = 6,
        revenge = 5,
        devastate = 0,
        shockwave = 20,
        thunder_clap = 6,
        concussion_blow = 30,
        shield_block = 60,
    },
    auras = {
        { up = "tc_up", remains = "tc_remains" },
        { up = "demo_shout_up", remains = "demo_shout_remains" },
    },
    initState = function(sim, s)
        -- Tanks get hit so rage income is higher; estimate ~8 rage/sec
        local mhSpeed = UnitAttackSpeed("player") or 2.0
        sim.rage_regen = 15 / mhSpeed + 8  -- auto-attacks + damage taken

        -- Stance
        sim.in_defensive = s.buff.defensive_stance.up

        -- Debuffs
        sim.tc_up = s.debuff.thunder_clap.up
        sim.tc_remains = s.debuff.thunder_clap.remains
        sim.demo_shout_up = s.debuff.demoralizing_shout.up
        sim.demo_shout_remains = s.debuff.demoralizing_shout.remains
        sim.sunder_stacks = s.debuff.sunder_armor.stacks or 0

        -- Procs
        sim.sword_and_board = s.buff.sword_and_board.up

        -- Talents
        sim.has_shockwave = s.talent.shockwave.rank > 0
        sim.has_devastate = s.talent.devastate.rank > 0
        sim.has_concussion_blow = s.talent.concussion_blow.rank > 0

        -- Shield Mastery reduces Shield Block CD
        local sm_rank = s.talent.shield_mastery.rank or 0
        sim.shield_block_cd = 60 - (sm_rank * 10)
    end,
    getPriority = function(sim, recs)
        -- Need Defensive Stance for Prot rotation
        if not sim.in_defensive then
            return "defensive_stance"
        end

        -- Shield Slam (highest threat, Sword and Board = free)
        if sim:ready("shield_slam") and (sim.rage >= 20 or sim.sword_and_board) then
            return "shield_slam"
        end

        -- Revenge (high threat, low cost)
        if sim:ready("revenge") and sim.rage >= 5 then
            return "revenge"
        end

        -- Shockwave
        if sim.has_shockwave and sim:ready("shockwave") and sim.rage >= 15 then
            return "shockwave"
        end

        -- Thunder Clap: maintain debuff
        if (not sim.tc_up or sim.tc_remains < 3) and sim:ready("thunder_clap") and sim.rage >= 20 then
            return "thunder_clap"
        end

        -- Demoralizing Shout: maintain debuff
        if (not sim.demo_shout_up or sim.demo_shout_remains < 3) and sim.rage >= 10 then
            return "demoralizing_shout"
        end

        -- Shield Block (active mitigation)
        if sim:ready("shield_block") and sim.rage >= 10 then
            return "shield_block"
        end

        -- Devastate (filler, builds Sunder stacks)
        if sim.has_devastate and sim.rage >= 15 then
            return "devastate"
        end

        return nil
    end,
    onCast = function(sim, key)
        if key == "defensive_stance" then
            sim.in_defensive = true
            sim.in_battle = false
            sim.in_berserker = false
        elseif key == "shield_slam" then
            if not sim.sword_and_board then
                sim.rage = math.max(0, sim.rage - 20)
            end
            sim.sword_and_board = false
        elseif key == "revenge" then
            sim.rage = math.max(0, sim.rage - 5)
        elseif key == "devastate" then
            sim.rage = math.max(0, sim.rage - 15)
            sim.sunder_stacks = math.min(5, sim.sunder_stacks + 1)
        elseif key == "thunder_clap" then
            sim.rage = math.max(0, sim.rage - 20)
            sim.tc_up = true
            sim.tc_remains = 30
        elseif key == "demoralizing_shout" then
            sim.rage = math.max(0, sim.rage - 10)
            sim.demo_shout_up = true
            sim.demo_shout_remains = 30
        elseif key == "shockwave" then
            sim.rage = math.max(0, sim.rage - 15)
        elseif key == "shield_block" then
            sim.rage = math.max(0, sim.rage - 10)
            sim.cd["shield_block"] = sim.shield_block_cd
        end
    end,
    tickTime = function(sim, seconds)
        sim.rage = math.min(sim.rage_max or 100, sim.rage + (sim.rage_regen or 0) * seconds)
    end,
    getWaitTime = function(sim)
        local nearest = 999
        local keys = { "shield_slam", "revenge", "thunder_clap", "shockwave" }
        for _, key in ipairs(keys) do
            local cd = sim.cd[key] or 0
            if cd > 0 and cd < nearest then
                nearest = cd
            end
        end
        if nearest < 999 then return nearest end
        return sim.gcd
    end,
}

local function GetProtectionRecommendations(addon)
    return DH:RunSimulation(state, protConfig)
end

-- ============================================================================
-- ROTATION MODES
-- ============================================================================

DH:RegisterMode("arms", {
    name = "Arms (DPS)",
    icon = select(3, GetSpellInfo(47486)) or "Interface\\Icons\\Ability_Warrior_SavageBlow",
    rotation = function(addon)
        return GetArmsRecommendations(addon)
    end,
})

DH:RegisterMode("fury", {
    name = "Fury (DPS)",
    icon = select(3, GetSpellInfo(23881)) or "Interface\\Icons\\Spell_Nature_BloodLust",
    rotation = function(addon)
        return GetFuryRecommendations(addon)
    end,
})

DH:RegisterMode("prot_warrior", {
    name = "Protection (Tank)",
    icon = select(3, GetSpellInfo(47488)) or "Interface\\Icons\\INV_Shield_04",
    rotation = function(addon)
        return GetProtectionRecommendations(addon)
    end,
})
