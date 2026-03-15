-- Classes/Paladin/Core.lua
-- Priority rotation logic for Paladin specs (3.3.5a compatible)
-- Based on wowsim/wotlk APL + wowhead guides
-- Uses queue-based priority with ready-first ordering

local DH = PriorityHelper
if not DH then return end

if select(2, UnitClass("player")) ~= "PALADIN" then
    return
end

local ns = DH.ns
local class = DH.Class
local state = DH.State

-- Helper to add a recommendation
local function addRec(recommendations, key)
    local ability = class.abilities[key]
    if ability then
        table.insert(recommendations, {
            ability = key,
            texture = ability.texture,
            name = ability.name,
        })
    end
    return #recommendations >= 3
end

-- Helper to check duplicates
local function isDuplicate(recommendations, key)
    for _, rec in ipairs(recommendations) do
        if rec.ability == key then return true end
    end
    return false
end

-- ============================================================================
-- RETRIBUTION ROTATION
-- Priority: HoW (execute) > CS > Judge > DS > Cons > Exorcism (AoW) > Holy Wrath
-- Undead/Demon: Exorcism boosted above CS (100% crit)
-- ============================================================================

local function GetRetributionRecommendations(addon)
    local recommendations = {}
    local s = state

    if not s.target.exists or not s.target.canAttack then
        return recommendations
    end

    -- Avenging Wrath (snoozeable)
    if s.cooldown.avenging_wrath.ready and not s.buff.avenging_wrath.up
        and not DH:IsSnoozed("avenging_wrath") then
        if addRec(recommendations, "avenging_wrath") then return recommendations end
    end

    -- Target type detection
    local creatureType = UnitCreatureType("target")
    local isUndeadOrDemon = creatureType == "Undead" or creatureType == "Demon"

    -- Build priority queue
    local queue = {}
    local function queueAbility(abilityKey, cdKey, condition)
        if condition == false then return end
        local cd = s.cooldown[cdKey]
        local remains = cd and cd.remains or 0
        local ready = remains <= 0.1
        table.insert(queue, { ability = abilityKey, ready = ready, remains = remains })
    end

    -- Execute: Hammer of Wrath
    if s.target.health.pct < 20 then
        queueAbility("hammer_of_wrath", "hammer_of_wrath")
    end

    -- Exorcism vs Undead/Demon (100% crit, high priority)
    if isUndeadOrDemon and s.buff.art_of_war.up then
        queueAbility("exorcism", "exorcism")
    end

    -- Core FCFS (wowhead priority)
    queueAbility("crusader_strike", "crusader_strike")
    queueAbility("judgement_of_wisdom", "judgement")
    queueAbility("divine_storm", "divine_storm", s.talent.divine_storm.rank > 0)

    -- Consecration
    if s.target.time_to_die > 4 then
        queueAbility("consecration", "consecration")
    end

    -- Exorcism vs normal targets (lower priority)
    if not isUndeadOrDemon and s.buff.art_of_war.up then
        queueAbility("exorcism", "exorcism")
    end

    -- Holy Wrath (undead/demons only)
    if isUndeadOrDemon then
        queueAbility("holy_wrath", "holy_wrath")
    end

    -- Divine Plea (low mana)
    if s.mana.pct < 40 then
        queueAbility("divine_plea", "divine_plea")
    end

    -- Pass 1: ready abilities in priority order (skip any already added above)
    for _, entry in ipairs(queue) do
        if entry.ready and not isDuplicate(recommendations, entry.ability) then
            if addRec(recommendations, entry.ability) then return recommendations end
        end
    end

    -- Pass 2: fill with next off CD (shortest first, skip any already shown)
    local onCD = {}
    for _, entry in ipairs(queue) do
        if not entry.ready and not isDuplicate(recommendations, entry.ability) then
            table.insert(onCD, entry)
        end
    end
    table.sort(onCD, function(a, b) return a.remains < b.remains end)
    for _, entry in ipairs(onCD) do
        if #recommendations >= 3 then break end
        if not isDuplicate(recommendations, entry.ability) then
            addRec(recommendations, entry.ability)
        end
    end

    return recommendations
end

-- ============================================================================
-- PROTECTION ROTATION (969 pattern)
-- Priority: SoR/HotR interleave > HoW (execute) > Cons > Holy Shield > Judge
-- ============================================================================

local function GetProtectionRecommendations(addon)
    local recommendations = {}
    local s = state

    if not s.target.exists or not s.target.canAttack then
        return recommendations
    end

    -- Righteous Fury check
    if not s.buff.righteous_fury.up then
        if addRec(recommendations, "righteous_fury") then return recommendations end
    end

    -- SoR / HotR interleave
    local sor_ready = s.cooldown.shield_of_righteousness.ready
    local hotr_ready = s.cooldown.hammer_of_the_righteous.ready
    local sor_remains = s.cooldown.shield_of_righteousness.remains
    local hotr_remains = s.cooldown.hammer_of_the_righteous.remains

    if sor_ready and hotr_remains <= 3 then
        if addRec(recommendations, "shield_of_righteousness") then return recommendations end
    elseif hotr_ready and sor_remains <= 3 then
        if addRec(recommendations, "hammer_of_the_righteous") then return recommendations end
    elseif sor_ready then
        if addRec(recommendations, "shield_of_righteousness") then return recommendations end
    elseif hotr_ready then
        if addRec(recommendations, "hammer_of_the_righteous") then return recommendations end
    end

    -- Build queue for remaining slots
    local queue = {}
    local function queueAbility(abilityKey, cdKey, condition)
        if condition == false then return end
        local cd = s.cooldown[cdKey]
        local remains = cd and cd.remains or 0
        local ready = remains <= 0.1
        table.insert(queue, { ability = abilityKey, ready = ready, remains = remains })
    end

    if s.target.health.pct < 20 then
        queueAbility("hammer_of_wrath", "hammer_of_wrath")
    end
    queueAbility("consecration", "consecration")
    queueAbility("holy_shield", "holy_shield")
    queueAbility("judgement_of_wisdom", "judgement")

    if s.mana.pct < 40 then
        queueAbility("divine_plea", "divine_plea")
    end

    -- Pass 1: ready abilities in priority order (skip any already added above)
    for _, entry in ipairs(queue) do
        if entry.ready and not isDuplicate(recommendations, entry.ability) then
            if addRec(recommendations, entry.ability) then return recommendations end
        end
    end

    -- Pass 2: fill with next off CD (shortest first, skip any already shown)
    local onCD = {}
    -- Include SoR/HotR for lookahead
    if not isDuplicate(recommendations, "shield_of_righteousness") and sor_remains > 0 then
        table.insert(onCD, { ability = "shield_of_righteousness", remains = sor_remains })
    end
    if not isDuplicate(recommendations, "hammer_of_the_righteous") and hotr_remains > 0 then
        table.insert(onCD, { ability = "hammer_of_the_righteous", remains = hotr_remains })
    end
    for _, entry in ipairs(queue) do
        if not entry.ready and not isDuplicate(recommendations, entry.ability) then
            table.insert(onCD, entry)
        end
    end
    table.sort(onCD, function(a, b) return a.remains < b.remains end)
    for _, entry in ipairs(onCD) do
        if #recommendations >= 3 then break end
        if not isDuplicate(recommendations, entry.ability) then
            addRec(recommendations, entry.ability)
        end
    end

    return recommendations
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
