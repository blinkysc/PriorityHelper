-- Classes/Warrior/Warrior.lua
-- Warrior class module: ability definitions + registration of all Warrior-specific data

local DH = PriorityHelper
if not DH then return end

-- Only load for Warriors
if select(2, UnitClass("player")) ~= "WARRIOR" then
    return
end

local ns = DH.ns
local class = DH.Class

-- ============================================================================
-- SPELL IDS (max rank for 3.3.5a)
-- ============================================================================

local SPELLS = {
    -- Arms
    MORTAL_STRIKE = 47486,
    OVERPOWER = 7384,
    REND = 47465,
    BLADESTORM = 46924,
    SWEEPING_STRIKES = 12328,

    -- Fury
    BLOODTHIRST = 23881,
    WHIRLWIND = 1680,
    SLAM = 47475,
    RAMPAGE = 29801,
    DEATH_WISH = 12292,

    -- Protection
    SHIELD_SLAM = 47488,
    REVENGE = 57823,
    DEVASTATE = 47498,
    SHOCKWAVE = 46968,
    THUNDER_CLAP = 47502,
    SHIELD_BLOCK = 2565,
    SHIELD_WALL = 871,
    LAST_STAND = 12975,
    SPELL_REFLECTION = 23920,
    CONCUSSION_BLOW = 12809,
    DISARM = 676,

    -- Shared
    EXECUTE = 47471,
    HEROIC_STRIKE = 47450,
    CLEAVE = 47520,
    SUNDER_ARMOR = 47467,
    SHATTERING_THROW = 64382,
    BATTLE_SHOUT = 47436,
    COMMANDING_SHOUT = 47440,
    DEMORALIZING_SHOUT = 25203,
    BERSERKER_RAGE = 18499,
    BLOODRAGE = 2687,
    RECKLESSNESS = 1719,
    PUMMEL = 6552,
    HAMSTRING = 7373,
    CHARGE = 11578,
    INTERCEPT = 20252,
    INTERVENE = 3411,
    HEROIC_THROW = 57755,

    -- Stances
    BATTLE_STANCE = 2457,
    DEFENSIVE_STANCE = 71,
    BERSERKER_STANCE = 2458,
}

ns.SPELLS = SPELLS

-- ============================================================================
-- ABILITY DEFINITIONS
-- ============================================================================

class.abilities = {
    -- Arms
    mortal_strike = {
        id = SPELLS.MORTAL_STRIKE,
        name = "Mortal Strike",
        texture = 132355,
    },
    overpower = {
        id = SPELLS.OVERPOWER,
        name = "Overpower",
        texture = 132223,
    },
    rend = {
        id = SPELLS.REND,
        name = "Rend",
        texture = 132155,
    },
    bladestorm = {
        id = SPELLS.BLADESTORM,
        name = "Bladestorm",
        texture = 236303,
    },

    -- Fury
    bloodthirst = {
        id = SPELLS.BLOODTHIRST,
        name = "Bloodthirst",
        texture = 136012,
    },
    whirlwind = {
        id = SPELLS.WHIRLWIND,
        name = "Whirlwind",
        texture = 132369,
    },
    slam = {
        id = SPELLS.SLAM,
        name = "Slam",
        texture = 132340,
    },
    death_wish = {
        id = SPELLS.DEATH_WISH,
        name = "Death Wish",
        texture = 136146,
    },

    -- Protection
    shield_slam = {
        id = SPELLS.SHIELD_SLAM,
        name = "Shield Slam",
        texture = 134951,
    },
    revenge = {
        id = SPELLS.REVENGE,
        name = "Revenge",
        texture = 132353,
    },
    devastate = {
        id = SPELLS.DEVASTATE,
        name = "Devastate",
        texture = 135291,
    },
    shockwave = {
        id = SPELLS.SHOCKWAVE,
        name = "Shockwave",
        texture = 236312,
    },
    thunder_clap = {
        id = SPELLS.THUNDER_CLAP,
        name = "Thunder Clap",
        texture = 136105,
    },
    shield_block = {
        id = SPELLS.SHIELD_BLOCK,
        name = "Shield Block",
        texture = 132110,
    },
    concussion_blow = {
        id = SPELLS.CONCUSSION_BLOW,
        name = "Concussion Blow",
        texture = 132325,
    },

    -- Shared
    execute = {
        id = SPELLS.EXECUTE,
        name = "Execute",
        texture = 135358,
    },
    heroic_strike = {
        id = SPELLS.HEROIC_STRIKE,
        name = "Heroic Strike",
        texture = 132282,
    },
    sunder_armor = {
        id = SPELLS.SUNDER_ARMOR,
        name = "Sunder Armor",
        texture = 132363,
    },
    battle_shout = {
        id = SPELLS.BATTLE_SHOUT,
        name = "Battle Shout",
        texture = 132333,
    },
    commanding_shout = {
        id = SPELLS.COMMANDING_SHOUT,
        name = "Commanding Shout",
        texture = 132351,
    },
    demoralizing_shout = {
        id = SPELLS.DEMORALIZING_SHOUT,
        name = "Demoralizing Shout",
        texture = 132366,
    },
    berserker_rage = {
        id = SPELLS.BERSERKER_RAGE,
        name = "Berserker Rage",
        texture = 136009,
    },
    recklessness = {
        id = SPELLS.RECKLESSNESS,
        name = "Recklessness",
        texture = 132109,
    },
    heroic_throw = {
        id = SPELLS.HEROIC_THROW,
        name = "Heroic Throw",
        texture = 132453,
    },

    -- Stances
    battle_stance = {
        id = SPELLS.BATTLE_STANCE,
        name = "Battle Stance",
        texture = 132349,
    },
    defensive_stance = {
        id = SPELLS.DEFENSIVE_STANCE,
        name = "Defensive Stance",
        texture = 132341,
    },
    berserker_stance = {
        id = SPELLS.BERSERKER_STANCE,
        name = "Berserker Stance",
        texture = 132275,
    },
}

-- Create name mapping and get textures from GetSpellInfo (3.3.5a compatible)
for key, ability in pairs(class.abilities) do
    ability.key = key
    class.abilityByName[ability.name] = ability
    if ability.id then
        local name, rank, icon = GetSpellInfo(ability.id)
        if icon then
            ability.texture = icon
        end
    end
end

-- Helper to get texture
function ns.GetAbilityTexture(key)
    local ability = class.abilities[key]
    if ability then
        if not ability.texture and ability.id then
            local _, _, icon = GetSpellInfo(ability.id)
            ability.texture = icon
        end
        return ability.texture or "Interface\\Icons\\INV_Misc_QuestionMark"
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- ============================================================================
-- REGISTER WARRIOR DATA INTO FRAMEWORK
-- ============================================================================

-- GCD reference spell (Heroic Strike)
DH:RegisterGCDSpell(SPELLS.HEROIC_STRIKE)

-- Stance form handlers (GetShapeshiftForm: 1=Battle, 2=Defensive, 3=Berserker)
-- Helper: reset all stance buffs before setting the active one
local function ResetStances(state)
    state.buff.battle_stance.expires = 0
    state.buff.battle_stance._isForm = true
    state.buff.defensive_stance.expires = 0
    state.buff.defensive_stance._isForm = true
    state.buff.berserker_stance.expires = 0
    state.buff.berserker_stance._isForm = true
end

DH:RegisterFormHandler(1, function(state)
    ResetStances(state)
    state.buff.battle_stance.expires = state.now + 3600
end)

DH:RegisterFormHandler(2, function(state)
    ResetStances(state)
    state.buff.defensive_stance.expires = state.now + 3600
end)

DH:RegisterFormHandler(3, function(state)
    ResetStances(state)
    state.buff.berserker_stance.expires = state.now + 3600
end)

-- Melee abilities (for UI range overlay)
DH:RegisterMeleeAbilities({
    "mortal_strike", "overpower", "rend", "bloodthirst", "whirlwind",
    "slam", "execute", "heroic_strike", "shield_slam", "revenge",
    "devastate", "thunder_clap", "sunder_armor", "shockwave",
    "concussion_blow",
})

-- Buffs to track
DH:RegisterBuffs({
    "battle_shout", "commanding_shout",
    "battle_stance", "defensive_stance", "berserker_stance",
    "bloodsurge",       -- instant Slam proc
    "sudden_death",     -- Execute usable
    "sword_and_board",  -- free Shield Slam proc
    "recklessness",
    "death_wish",
    "shield_block",
    "enrage",
    "taste_for_blood",  -- Overpower proc (Arms)
    "berserker_rage",
    "bloodrage",
})

-- Debuffs to track
DH:RegisterDebuffs({
    "rend",
    "sunder_armor",
    "thunder_clap",
    "demoralizing_shout",
    "hamstring",
    "deep_wounds",
})

-- Cooldowns
DH:RegisterCooldowns({
    mortal_strike = 47486,
    overpower = 7384,
    bladestorm = 46924,
    bloodthirst = 23881,
    whirlwind = 1680,
    slam = 47475,
    execute = 47471,
    shield_slam = 47488,
    revenge = 57823,
    devastate = 47498,
    shockwave = 46968,
    thunder_clap = 47502,
    shield_block = 2565,
    concussion_blow = 12809,
    death_wish = 12292,
    recklessness = 1719,
    berserker_rage = 18499,
    heroic_throw = 57755,
})

-- Talents
DH:RegisterTalents({
    -- Arms
    { 1, 1, "improved_heroic_strike" },
    { 1, 2, "deflection" },
    { 1, 3, "improved_rend" },
    { 1, 4, "improved_charge" },
    { 1, 5, "iron_will" },
    { 1, 6, "tactical_mastery" },
    { 1, 7, "improved_overpower" },
    { 1, 8, "anger_management" },
    { 1, 9, "impale" },
    { 1, 10, "deep_wounds" },
    { 1, 11, "two_handed_weapon_specialization" },
    { 1, 12, "taste_for_blood" },
    { 1, 13, "poleaxe_specialization" },
    { 1, 14, "sweeping_strikes" },
    { 1, 15, "mace_specialization" },
    { 1, 16, "sword_specialization" },
    { 1, 17, "weapon_mastery" },
    { 1, 18, "improved_hamstring" },
    { 1, 19, "trauma" },
    { 1, 20, "second_wind" },
    { 1, 21, "mortal_strike" },
    { 1, 22, "strength_of_arms" },
    { 1, 23, "improved_slam" },
    { 1, 24, "juggernaut" },
    { 1, 25, "improved_mortal_strike" },
    { 1, 26, "unrelenting_assault" },
    { 1, 27, "sudden_death" },
    { 1, 28, "endless_rage" },
    { 1, 29, "blood_frenzy" },
    { 1, 30, "wrecking_crew" },
    { 1, 31, "bladestorm" },

    -- Fury
    { 2, 1, "armored_to_the_teeth" },
    { 2, 2, "booming_voice" },
    { 2, 3, "cruelty" },
    { 2, 4, "improved_demoralizing_shout" },
    { 2, 5, "unbridled_wrath" },
    { 2, 6, "improved_cleave" },
    { 2, 7, "piercing_howl" },
    { 2, 8, "blood_craze" },
    { 2, 9, "commanding_presence" },
    { 2, 10, "dual_wield_specialization" },
    { 2, 11, "improved_execute" },
    { 2, 12, "enrage" },
    { 2, 13, "precision" },
    { 2, 14, "death_wish" },
    { 2, 15, "improved_intercept" },
    { 2, 16, "improved_berserker_rage" },
    { 2, 17, "flurry" },
    { 2, 18, "intensify_rage" },
    { 2, 19, "bloodthirst" },
    { 2, 20, "improved_whirlwind" },
    { 2, 21, "furious_attacks" },
    { 2, 22, "improved_berserker_stance" },
    { 2, 23, "heroic_fury" },
    { 2, 24, "rampage" },
    { 2, 25, "bloodsurge" },
    { 2, 26, "unending_fury" },
    { 2, 27, "titans_grip" },

    -- Protection
    { 3, 1, "improved_bloodrage" },
    { 3, 2, "shield_specialization" },
    { 3, 3, "improved_thunder_clap" },
    { 3, 4, "incite" },
    { 3, 5, "anticipation" },
    { 3, 6, "last_stand" },
    { 3, 7, "improved_revenge" },
    { 3, 8, "shield_mastery" },
    { 3, 9, "toughness" },
    { 3, 10, "improved_spell_reflection" },
    { 3, 11, "improved_disarm" },
    { 3, 12, "puncture" },
    { 3, 13, "improved_disciplines" },
    { 3, 14, "concussion_blow" },
    { 3, 15, "gag_order" },
    { 3, 16, "one_handed_weapon_specialization" },
    { 3, 17, "vigilance" },
    { 3, 18, "focused_rage" },
    { 3, 19, "vitality" },
    { 3, 20, "safeguard" },
    { 3, 21, "warbringer" },
    { 3, 22, "devastate" },
    { 3, 23, "critical_block" },
    { 3, 24, "sword_and_board" },
    { 3, 25, "damage_shield" },
    { 3, 26, "shockwave" },
})

-- Glyphs
DH:RegisterGlyphs({
    [58388] = "mortal_strike",   -- Glyph of Mortal Strike
    [58386] = "overpower",       -- Glyph of Overpower
    [58385] = "rend",            -- Glyph of Rending
    [58370] = "whirlwind",       -- Glyph of Whirlwind
    [58364] = "heroic_strike",   -- Glyph of Heroic Strike
    [58375] = "bloodthirst",     -- Glyph of Bloodthirst
    [58397] = "shield_block",    -- Glyph of Blocking
    [58387] = "revenge",         -- Glyph of Revenge
    [58356] = "devastate",       -- Glyph of Devastate
    [63324] = "bladestorm",      -- Glyph of Bladestorm
    [58384] = "cleave",          -- Glyph of Cleaving
    [58366] = "execution",       -- Glyph of Execution
})

-- Buff spell ID -> key mapping
DH:RegisterBuffMap({
    [47436] = "battle_shout",
    [47440] = "commanding_shout",
    [2457] = "battle_stance",
    [71] = "defensive_stance",
    [2458] = "berserker_stance",
    [46916] = "bloodsurge",
    [52437] = "sudden_death",
    [50227] = "sword_and_board",
    [1719] = "recklessness",
    [12292] = "death_wish",
    [2565] = "shield_block",
    [12880] = "enrage",
    [60503] = "taste_for_blood",
    [18499] = "berserker_rage",
    [2687] = "bloodrage",
})

-- Debuff spell ID -> key mapping (player-applied)
DH:RegisterDebuffMap({
    -- Rend (all ranks)
    [47465] = "rend", [47464] = "rend", [25874] = "rend",
    [11574] = "rend", [11573] = "rend", [6548] = "rend", [6547] = "rend", [772] = "rend",
    -- Sunder Armor
    [47467] = "sunder_armor", [7405] = "sunder_armor",
    -- Thunder Clap
    [47502] = "thunder_clap",
    -- Demoralizing Shout
    [25203] = "demoralizing_shout",
    -- Deep Wounds
    [12867] = "deep_wounds", [12868] = "deep_wounds",
    -- Hamstring
    [7373] = "hamstring", [1715] = "hamstring",
})

-- Debuff name patterns (fallback matching)
DH:RegisterDebuffNamePatterns({
    { "rend", "rend" },
    { "sunder armor", "sunder_armor" },
    { "thunder clap", "thunder_clap" },
    { "demoralizing shout", "demoralizing_shout" },
    { "deep wounds", "deep_wounds" },
    { "hamstring", "hamstring" },
})

-- External debuff mapping
DH:RegisterExternalDebuffMap({
    [47467] = "sunder_armor",   -- Sunder from another warrior
    [8647] = "sunder_armor",    -- Expose Armor (rogue)
})

DH:RegisterExternalDebuffNamePatterns({
    { "sunder", "sunder_armor" },
    { "expose armor", "sunder_armor" },
})

-- ============================================================================
-- SPEC DETECTION
-- ============================================================================

DH:RegisterSpecDetector(function()
    local arms, fury, prot = 0, 0, 0

    for i = 1, GetNumTalentTabs() do
        local _, _, points = GetTalentTabInfo(i)
        if i == 1 then arms = points
        elseif i == 2 then fury = points
        else prot = points
        end
    end

    if arms > fury and arms > prot then
        return "arms"
    elseif fury > prot then
        return "fury"
    else
        return "protection"
    end
end)

-- ============================================================================
-- DEFAULT SETTINGS (class-specific)
-- ============================================================================

DH:RegisterDefaults({
    arms = {
        enabled = true,
    },
    fury = {
        enabled = true,
    },
    protection = {
        enabled = true,
    },
    common = {
        dummy_ttd = 300,
    },
})

-- Major cooldowns: snoozeable if player skips them
DH:RegisterSnoozeable("recklessness", 60)
DH:RegisterSnoozeable("death_wish", 60)
DH:RegisterSnoozeable("bladestorm", 60)

-- ============================================================================
-- SLASH COMMANDS (Warrior-specific)
-- ============================================================================

DH:RegisterSlashCommand("war", function(cmd)
    local s = DH.State
    DH:UpdateState()
    DH:Print("--- Warrior Status ---")
    DH:Print("Rage: " .. tostring(s.rage.current))
    DH:Print("Rend: " .. (s.debuff.rend.up and string.format("%.1fs", s.debuff.rend.remains) or "DOWN"))
    DH:Print("Sunder: " .. tostring(s.debuff.sunder_armor.stacks or 0) .. " stacks")
    DH:Print("Bloodsurge: " .. (s.buff.bloodsurge.up and "UP" or "no"))
    DH:Print("Sudden Death: " .. (s.buff.sudden_death.up and "UP" or "no"))
    DH:Print("TTD: " .. tostring(s.target.time_to_die) .. "s")
end, "war - Show warrior status")

-- ============================================================================
-- DEBUG FRAME (Warrior-specific)
-- ============================================================================

ns.registered.debugFrameUpdater = function()
    if not ns.DebugFrame then return end

    local s = DH.State
    local rec1 = ns.recommendations[1] and ns.recommendations[1].ability or "none"
    local rec2 = ns.recommendations[2] and ns.recommendations[2].ability or "none"
    local rec3 = ns.recommendations[3] and ns.recommendations[3].ability or "none"

    local lines = {
        "|cFFFFFF00=== Live Debug ===|r",
        string.format("Rage: %d | GCD: %.2f", s.rage.current, s.gcd_remains),
        string.format("Rend: %.1f | Sunder: %d", s.debuff.rend.remains, s.debuff.sunder_armor.stacks or 0),
        string.format("|cFFFFFF00Rec: %s > %s > %s|r", rec1, rec2, rec3),
    }

    ns.DebugFrame.text:SetText(table.concat(lines, "\n"))
    ns.DebugFrame:Show()
end
