-- Classes/Paladin/Core.lua
-- Priority rotation logic for Paladin specs (3.3.5a compatible)
-- Uses core RunSimulation for CD-aware predictions

local DH = PriorityHelper
if not DH then return end

if select(2, UnitClass("player")) ~= "PALADIN" then
    return
end

local ns = DH.ns
local class = DH.Class
local state = DH.State

-- ============================================================================
-- RETRIBUTION ROTATION
-- ============================================================================

local retConfig = {
    gcdType = "melee",
    maxRecs = 3,
    cds = {
        crusader_strike = "crusader_strike",
        judgement_of_wisdom = "judgement",
        divine_storm = "divine_storm",
        consecration = "consecration",
        exorcism = "exorcism",
        hammer_of_wrath = "hammer_of_wrath",
        holy_wrath = "holy_wrath",
        avenging_wrath = "avenging_wrath",
        divine_plea = "divine_plea",
    },
    baseCDs = {
        crusader_strike = 4,
        judgement_of_wisdom = 8,
        divine_storm = 10,
        consecration = 8,
        exorcism = 15,
        hammer_of_wrath = 6,
        holy_wrath = 30,
        avenging_wrath = 120,
        divine_plea = 60,
    },
    initState = function(sim, s)
        sim.aow_up = s.buff.art_of_war.up
        sim.aw_up = s.buff.avenging_wrath.up
        sim.has_ds = s.talent.divine_storm.rank > 0
        sim.is_undead_demon = (UnitCreatureType("target") == "Undead"
            or UnitCreatureType("target") == "Demon")
    end,
    getPriority = function(sim, recs)
        -- Avenging Wrath
        if sim:ready("avenging_wrath") and not sim.aw_up
            and not DH:IsSnoozed("avenging_wrath") then
            return "avenging_wrath"
        end

        -- Divine Plea (high priority when mana is critical)
        if sim.mana_pct < 40 and sim:ready("divine_plea") then
            return "divine_plea"
        end

        -- Execute: Hammer of Wrath
        if sim.in_execute and sim:ready("hammer_of_wrath") then
            return "hammer_of_wrath"
        end

        -- Exorcism vs Undead/Demon with AoW (100% crit)
        if sim.is_undead_demon and sim.aow_up and sim:ready("exorcism") then
            return "exorcism"
        end

        -- Core FCFS (wotlk sim APL order: Judge > CS > DS)
        if sim:ready("judgement_of_wisdom") then
            return "judgement_of_wisdom"
        end

        if sim:ready("crusader_strike") then
            return "crusader_strike"
        end

        if sim.has_ds and sim:ready("divine_storm") then
            return "divine_storm"
        end

        -- Consecration
        if sim:ready("consecration") and sim.ttd > 4 then
            return "consecration"
        end

        -- Exorcism vs normal targets with AoW
        if not sim.is_undead_demon and sim.aow_up and sim:ready("exorcism") then
            return "exorcism"
        end

        -- Holy Wrath (undead/demons only)
        if sim.is_undead_demon and sim:ready("holy_wrath") then
            return "holy_wrath"
        end

        -- Nothing ready — return nearest FCFS ability not already recommended
        local function hasRec(key)
            for _, r in ipairs(recs) do if r.ability == key then return true end end
            return false
        end
        local nearest, nearestCD = nil, 999
        local fcfs = { "judgement_of_wisdom", "crusader_strike" }
        if sim.has_ds then table.insert(fcfs, "divine_storm") end
        table.insert(fcfs, "consecration")
        for _, key in ipairs(fcfs) do
            if not hasRec(key) then
                local cd = sim:remains(key)
                if cd < nearestCD then
                    nearest = key
                    nearestCD = cd
                end
            end
        end
        return nearest
    end,
    onCast = function(sim, key)
        if key == "avenging_wrath" then
            sim.aw_up = true
        elseif key == "exorcism" then
            sim.aow_up = false  -- Consumes AoW proc
        end
    end,
}

local function GetRetributionRecommendations(addon)
    return DH:RunSimulation(state, retConfig)
end

-- ============================================================================
-- PROTECTION ROTATION (969 pattern)
-- ============================================================================

local protConfig = {
    gcdType = "melee",
    maxRecs = 3,
    cds = {
        shield_of_righteousness = "shield_of_righteousness",
        hammer_of_the_righteous = "hammer_of_the_righteous",
        consecration = "consecration",
        holy_shield = "holy_shield",
        judgement_of_wisdom = "judgement",
        hammer_of_wrath = "hammer_of_wrath",
        divine_plea = "divine_plea",
    },
    baseCDs = {
        shield_of_righteousness = 6,
        hammer_of_the_righteous = 6,
        consecration = 8,
        holy_shield = 8,
        judgement_of_wisdom = 8,
        hammer_of_wrath = 6,
        divine_plea = 60,
    },
    initState = function(sim, s)
        sim.rf_up = s.buff.righteous_fury.up
    end,
    getPriority = function(sim, recs)
        -- Righteous Fury always first
        if not sim.rf_up then
            return "righteous_fury"
        end

        -- Helper: is ability already recommended?
        local function hasRec(key)
            for _, r in ipairs(recs) do
                if r.ability == key then return true end
            end
            return false
        end

        -- 969 pattern: always pick a 6s ability first, then a 9s, alternating.
        -- Count how many 6s abilities are already recommended
        local has6s = hasRec("shield_of_righteousness") or hasRec("hammer_of_the_righteous")

        -- If no 6s ability in recs yet, ALWAYS pick the nearest 6s (even if on CD)
        if not has6s then
            local sor = sim:remains("shield_of_righteousness")
            local hotr = sim:remains("hammer_of_the_righteous")
            if sor <= hotr then
                return "shield_of_righteousness"
            else
                return "hammer_of_the_righteous"
            end
        end

        -- We have a 6s in recs. Now pick a 9s ability (must be ready).
        -- Execute: Hammer of Wrath
        if sim.in_execute and sim:ready("hammer_of_wrath") then
            return "hammer_of_wrath"
        end

        -- Divine Plea (high priority when mana is critical)
        if sim.mana_pct < 40 and sim:ready("divine_plea") then
            return "divine_plea"
        end

        if sim:ready("consecration") then
            return "consecration"
        end

        if sim:ready("holy_shield") then
            return "holy_shield"
        end

        if sim:ready("judgement_of_wisdom") then
            return "judgement_of_wisdom"
        end

        -- No 9s ability ready — return the nearest 9s on CD.
        -- The sim will wait for it, so it shows up in Rec3 approaching.
        local nearest9s, nearest9sCD = nil, 999
        local nines = { "consecration", "holy_shield", "judgement_of_wisdom" }
        if sim.in_execute then table.insert(nines, 1, "hammer_of_wrath") end
        for _, key in ipairs(nines) do
            if not hasRec(key) then
                local cd = sim:remains(key)
                if cd < nearest9sCD then
                    nearest9s = key
                    nearest9sCD = cd
                end
            end
        end
        if nearest9s then return nearest9s end

        -- Absolute fallback: pick whichever 6s isn't recommended yet
        if not hasRec("shield_of_righteousness") then return "shield_of_righteousness" end
        if not hasRec("hammer_of_the_righteous") then return "hammer_of_the_righteous" end

        return nil
    end,
    onCast = function(sim, key)
        if key == "righteous_fury" then
            sim.rf_up = true
        end
    end,
}

local function GetProtectionRecommendations(addon)
    return DH:RunSimulation(state, protConfig)
end

-- ============================================================================
-- ROTATION MODES
-- ============================================================================

DH:RegisterMode("ret", {
    name = "Retribution (DPS)",
    icon = select(3, GetSpellInfo(35395)) or "Interface\\Icons\\Ability_ThunderClap",
    rotation = function(addon)
        return GetRetributionRecommendations(addon)
    end,
})

DH:RegisterMode("prot_paladin", {
    name = "Protection (Tank)",
    icon = select(3, GetSpellInfo(48827)) or "Interface\\Icons\\Spell_Holy_AvengersShield",
    rotation = function(addon)
        return GetProtectionRecommendations(addon)
    end,
})
