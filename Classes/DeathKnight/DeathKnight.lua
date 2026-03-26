-- Classes/DeathKnight/DeathKnight.lua
-- Death Knight class module: ability definitions + registration

local DH = PriorityHelper
if not DH then return end

-- Only load for Death Knights
if select(2, UnitClass("player")) ~= "DEATHKNIGHT" then
    return
end

local ns = DH.ns
local class = DH.Class

-- ============================================================================
-- SPELL IDS (max rank for 3.3.5a)
-- ============================================================================

local SPELLS = {
    -- Disease application
    ICY_TOUCH = 59131,
    PLAGUE_STRIKE = 49921,
    PESTILENCE = 50842,

    -- Frost
    OBLITERATE = 51425,
    FROST_STRIKE = 55268,
    HOWLING_BLAST = 51411,
    UNBREAKABLE_ARMOR = 51271,

    -- Unholy
    SCOURGE_STRIKE = 55271,
    DEATH_COIL = 49895,
    DEATH_AND_DECAY = 49938,
    SUMMON_GARGOYLE = 49206,
    GHOUL_FRENZY = 63560,
    RAISE_DEAD = 46584,

    -- Blood
    HEART_STRIKE = 55262,
    BLOOD_STRIKE = 49930,
    DEATH_STRIKE = 49924,
    BLOOD_BOIL = 49941,
    RUNE_TAP = 48982,
    VAMPIRIC_BLOOD = 55233,
    DANCING_RUNE_WEAPON = 49028,
    MARK_OF_BLOOD = 49005,

    -- Shared
    BLOOD_TAP = 45529,
    HORN_OF_WINTER = 57623,
    EMPOWER_RUNE_WEAPON = 47568,
    RUNE_STRIKE = 56815,
    ARMY_OF_THE_DEAD = 42650,
    ANTI_MAGIC_SHELL = 48707,
    ICEBOUND_FORTITUDE = 48792,
    BONE_SHIELD = 49222,
    UNHOLY_FRENZY = 49016,

    -- Presences
    BLOOD_PRESENCE = 48263,
    FROST_PRESENCE = 48266,
    UNHOLY_PRESENCE = 48265,
}

ns.SPELLS = SPELLS

-- ============================================================================
-- ABILITY DEFINITIONS
-- ============================================================================

class.abilities = {
    -- Disease
    icy_touch = {
        id = SPELLS.ICY_TOUCH,
        name = "Icy Touch",
        texture = 237527,
    },
    plague_strike = {
        id = SPELLS.PLAGUE_STRIKE,
        name = "Plague Strike",
        texture = 237530,
    },
    pestilence = {
        id = SPELLS.PESTILENCE,
        name = "Pestilence",
        texture = 237532,
    },

    -- Frost
    obliterate = {
        id = SPELLS.OBLITERATE,
        name = "Obliterate",
        texture = 135771,
    },
    frost_strike = {
        id = SPELLS.FROST_STRIKE,
        name = "Frost Strike",
        texture = 237520,
    },
    howling_blast = {
        id = SPELLS.HOWLING_BLAST,
        name = "Howling Blast",
        texture = 237533,
    },
    unbreakable_armor = {
        id = SPELLS.UNBREAKABLE_ARMOR,
        name = "Unbreakable Armor",
        texture = 237510,
    },

    -- Unholy
    scourge_strike = {
        id = SPELLS.SCOURGE_STRIKE,
        name = "Scourge Strike",
        texture = 237530,
    },
    death_coil = {
        id = SPELLS.DEATH_COIL,
        name = "Death Coil",
        texture = 136145,
    },
    death_and_decay = {
        id = SPELLS.DEATH_AND_DECAY,
        name = "Death and Decay",
        texture = 136144,
    },
    summon_gargoyle = {
        id = SPELLS.SUMMON_GARGOYLE,
        name = "Summon Gargoyle",
        texture = 132182,
    },
    raise_dead = {
        id = SPELLS.RAISE_DEAD,
        name = "Raise Dead",
        texture = 136994,
    },

    -- Blood
    heart_strike = {
        id = SPELLS.HEART_STRIKE,
        name = "Heart Strike",
        texture = 135675,
    },
    blood_strike = {
        id = SPELLS.BLOOD_STRIKE,
        name = "Blood Strike",
        texture = 237517,
    },
    death_strike = {
        id = SPELLS.DEATH_STRIKE,
        name = "Death Strike",
        texture = 237517,
    },
    blood_boil = {
        id = SPELLS.BLOOD_BOIL,
        name = "Blood Boil",
        texture = 237513,
    },
    vampiric_blood = {
        id = SPELLS.VAMPIRIC_BLOOD,
        name = "Vampiric Blood",
        texture = 136168,
    },
    dancing_rune_weapon = {
        id = SPELLS.DANCING_RUNE_WEAPON,
        name = "Dancing Rune Weapon",
        texture = 135277,
    },
    rune_tap = {
        id = SPELLS.RUNE_TAP,
        name = "Rune Tap",
        texture = 237529,
    },

    -- Shared
    blood_tap = {
        id = SPELLS.BLOOD_TAP,
        name = "Blood Tap",
        texture = 237515,
    },
    horn_of_winter = {
        id = SPELLS.HORN_OF_WINTER,
        name = "Horn of Winter",
        texture = 134228,
    },
    empower_rune_weapon = {
        id = SPELLS.EMPOWER_RUNE_WEAPON,
        name = "Empower Rune Weapon",
        texture = 135372,
    },
    anti_magic_shell = {
        id = SPELLS.ANTI_MAGIC_SHELL,
        name = "Anti-Magic Shell",
        texture = 136120,
    },
    icebound_fortitude = {
        id = SPELLS.ICEBOUND_FORTITUDE,
        name = "Icebound Fortitude",
        texture = 237525,
    },
    bone_shield = {
        id = SPELLS.BONE_SHIELD,
        name = "Bone Shield",
        texture = 132728,
    },

    -- Off-GCD
    rune_strike = {
        id = SPELLS.RUNE_STRIKE,
        name = "Rune Strike",
        texture = 237518,
    },

    -- Presences
    blood_presence = {
        id = SPELLS.BLOOD_PRESENCE,
        name = "Blood Presence",
        texture = 135770,
    },
    frost_presence = {
        id = SPELLS.FROST_PRESENCE,
        name = "Frost Presence",
        texture = 135773,
    },
    unholy_presence = {
        id = SPELLS.UNHOLY_PRESENCE,
        name = "Unholy Presence",
        texture = 135775,
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

---Returns icon texture path for an ability key, with fallback question mark icon.
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
-- REGISTER DK DATA INTO FRAMEWORK
-- ============================================================================

DH:RegisterGCDSpell(SPELLS.ICY_TOUCH)

-- Presence form handlers (GetShapeshiftForm: 1=Blood, 2=Frost, 3=Unholy)
---Clears presence form auras before applying the currently active presence.
local function ResetPresences(state)
    state.buff.blood_presence.expires = 0
    state.buff.blood_presence._isForm = true
    state.buff.frost_presence.expires = 0
    state.buff.frost_presence._isForm = true
    state.buff.unholy_presence.expires = 0
    state.buff.unholy_presence._isForm = true
end

DH:RegisterFormHandler(1, function(state)
    ResetPresences(state)
    state.buff.blood_presence.expires = state.now + 3600
end)

DH:RegisterFormHandler(2, function(state)
    ResetPresences(state)
    state.buff.frost_presence.expires = state.now + 3600
end)

DH:RegisterFormHandler(3, function(state)
    ResetPresences(state)
    state.buff.unholy_presence.expires = state.now + 3600
end)

DH:RegisterMeleeAbilities({
    "icy_touch", "plague_strike", "obliterate", "frost_strike",
    "scourge_strike", "death_strike", "heart_strike", "blood_strike",
    "blood_boil", "pestilence", "howling_blast",
})

-- Buffs to track
DH:RegisterBuffs({
    "blood_presence", "frost_presence", "unholy_presence",
    "horn_of_winter",
    "strength_of_earth_totem",
    "killing_machine",
    "freezing_fog",     -- Rime proc (free Howling Blast)
    "unbreakable_armor",
    "sudden_doom",      -- Free Death Coil proc
    "bone_shield",
    "vampiric_blood",
    "icebound_fortitude",
    "dancing_rune_weapon",
    "unholy_frenzy",
    "desolation",
    "summon_gargoyle",
})

-- Debuffs to track
DH:RegisterDebuffs({
    "frost_fever",
    "blood_plague",
    "ebon_plague",
    "crypt_fever",
})

-- Cooldowns
DH:RegisterCooldowns({
    icy_touch = 59131,
    plague_strike = 49921,
    obliterate = 51425,
    frost_strike = 55268,
    howling_blast = 51411,
    unbreakable_armor = 51271,
    scourge_strike = 55271,
    death_coil = 49895,
    heart_strike = 55262,
    blood_strike = 49930,
    death_strike = 49924,
    blood_boil = 49941,
    pestilence = 50842,
    death_and_decay = 49938,
    blood_tap = 45529,
    horn_of_winter = 57623,
    empower_rune_weapon = 47568,
    summon_gargoyle = 49206,
    dancing_rune_weapon = 49028,
    vampiric_blood = 55233,
    icebound_fortitude = 48792,
    bone_shield = 49222,
    anti_magic_shell = 48707,
    rune_tap = 48982,
    unholy_frenzy = 49016,
})

-- Talents
DH:RegisterTalents({
    -- Blood
    { 1, 1, "butchery" },
    { 1, 2, "subversion" },
    { 1, 3, "blade_barrier" },
    { 1, 4, "bladed_armor" },
    { 1, 5, "scent_of_blood" },
    { 1, 6, "two_handed_weapon_specialization" },
    { 1, 7, "rune_tap" },
    { 1, 8, "dark_conviction" },
    { 1, 9, "death_rune_mastery" },
    { 1, 10, "improved_rune_tap" },
    { 1, 11, "spell_deflection" },
    { 1, 12, "vendetta" },
    { 1, 13, "bloody_vengeance" },
    { 1, 14, "abominations_might" },
    { 1, 15, "blood_worms" },
    { 1, 16, "hysteria" },
    { 1, 17, "improved_blood_presence" },
    { 1, 18, "improved_death_strike" },
    { 1, 19, "sudden_doom" },
    { 1, 20, "vampiric_blood" },
    { 1, 21, "will_of_the_necropolis" },
    { 1, 22, "heart_strike" },
    { 1, 23, "might_of_mograine" },
    { 1, 24, "blood_gorged" },
    { 1, 28, "dancing_rune_weapon" },

    -- Frost
    { 2, 1, "improved_icy_touch" },
    { 2, 2, "runic_power_mastery" },
    { 2, 3, "toughness" },
    { 2, 4, "icy_reach" },
    { 2, 5, "black_ice" },
    { 2, 6, "nerves_of_cold_steel" },
    { 2, 7, "icy_talons" },
    { 2, 8, "lichborne" },
    { 2, 9, "annihilation" },
    { 2, 10, "killing_machine" },
    { 2, 11, "chill_of_the_grave" },
    { 2, 12, "endless_winter" },
    { 2, 13, "frigid_dreadplate" },
    { 2, 14, "glacier_rot" },
    { 2, 15, "deathchill" },
    { 2, 16, "improved_icy_talons" },
    { 2, 17, "merciless_combat" },
    { 2, 18, "rime" },
    { 2, 19, "chillblains" },
    { 2, 20, "hungering_cold" },
    { 2, 21, "improved_frost_presence" },
    { 2, 22, "threat_of_thassarian" },
    { 2, 23, "blood_of_the_north" },
    { 2, 24, "unbreakable_armor" },
    { 2, 25, "acclimation" },
    { 2, 26, "frost_strike" },
    { 2, 27, "guile_of_gorefiend" },
    { 2, 28, "tundra_stalker" },
    { 2, 29, "howling_blast" },

    -- Unholy
    { 3, 1, "vicious_strikes" },
    { 3, 2, "virulence" },
    { 3, 3, "anticipation" },
    { 3, 4, "epidemic" },
    { 3, 5, "morbidity" },
    { 3, 6, "unholy_command" },
    { 3, 7, "ravenous_dead" },
    { 3, 8, "outbreak" },
    { 3, 9, "necrosis" },
    { 3, 10, "corpse_explosion" },
    { 3, 11, "on_a_pale_horse" },
    { 3, 12, "blood_caked_blade" },
    { 3, 13, "night_of_the_dead" },
    { 3, 14, "unholy_blight" },
    { 3, 15, "impurity" },
    { 3, 16, "dirge" },
    { 3, 17, "desecration" },
    { 3, 18, "magic_suppression" },
    { 3, 19, "reaping" },
    { 3, 20, "master_of_ghouls" },
    { 3, 21, "desolation" },
    { 3, 22, "anti_magic_zone" },
    { 3, 23, "improved_unholy_presence" },
    { 3, 24, "ghoul_frenzy" },
    { 3, 25, "crypt_fever" },
    { 3, 26, "bone_shield" },
    { 3, 27, "wandering_plague" },
    { 3, 28, "ebon_plaguebringer" },
    { 3, 29, "scourge_strike" },
    { 3, 30, "rage_of_rivendare" },
    { 3, 31, "summon_gargoyle" },
})

-- Glyphs
DH:RegisterGlyphs({
    [58631] = "icy_touch",
    [58657] = "obliterate",
    [58625] = "frost_strike",
    [58647] = "frost_strike",
    [63331] = "howling_blast",
    [58642] = "scourge_strike",
    [58677] = "death_coil",
    [58669] = "death_strike",
    [58671] = "heart_strike",
    [58680] = "rune_strike",
    [63330] = "dancing_rune_weapon",
    [63334] = "disease",
    [58676] = "horn_of_winter",
})

-- Buff spell ID -> key mapping
DH:RegisterBuffMap({
    [48263] = "blood_presence",
    [48266] = "frost_presence",
    [48265] = "unholy_presence",
    [57623] = "horn_of_winter",
    -- Strength of Earth (all ranks) so HoW suppression works regardless of aura rank
    [8076] = "strength_of_earth_totem",
    [8160] = "strength_of_earth_totem",
    [8161] = "strength_of_earth_totem",
    [10442] = "strength_of_earth_totem",
    [25361] = "strength_of_earth_totem",
    [25528] = "strength_of_earth_totem",
    [57622] = "strength_of_earth_totem",
    [58643] = "strength_of_earth_totem",
    [51124] = "killing_machine",
    [59052] = "freezing_fog",
    [51271] = "unbreakable_armor",
    [81340] = "sudden_doom",
    [49222] = "bone_shield",
    [55233] = "vampiric_blood",
    [48792] = "icebound_fortitude",
    [49028] = "dancing_rune_weapon",
    [49016] = "unholy_frenzy",
    [66803] = "desolation",
    [49206] = "summon_gargoyle",
})

-- Debuff spell ID -> key mapping
DH:RegisterDebuffMap({
    [55095] = "frost_fever",
    [55078] = "blood_plague",
    [51735] = "ebon_plague",
    [50510] = "crypt_fever",
})

DH:RegisterDebuffNamePatterns({
    { "frost fever", "frost_fever" },
    { "blood plague", "blood_plague" },
    { "ebon plague", "ebon_plague" },
    { "crypt fever", "crypt_fever" },
})

-- Name-based fallback for buffs whose spell IDs vary by rank/talent
DH:RegisterBuffNamePatterns({
    { "strength of earth", "strength_of_earth_totem" },
})

DH:RegisterExternalDebuffMap({})
DH:RegisterExternalDebuffNamePatterns({})

-- ============================================================================
-- SPEC DETECTION
-- ============================================================================

DH:RegisterSpecDetector(function()
    local blood, frost, unholy = 0, 0, 0

    for i = 1, GetNumTalentTabs() do
        local _, _, points = GetTalentTabInfo(i)
        if i == 1 then blood = points
        elseif i == 2 then frost = points
        else unholy = points
        end
    end

    if blood > frost and blood > unholy then
        return "blood"
    elseif frost > unholy then
        return "frost"
    else
        return "unholy"
    end
end)

-- ============================================================================
-- DEFAULT SETTINGS
-- ============================================================================

DH:RegisterDefaults({
    blood = { enabled = true },
    frost = { enabled = true },
    unholy = { enabled = true },
    common = { dummy_ttd = 300 },
})

DH:RegisterSnoozeable("dancing_rune_weapon", 60)
DH:RegisterSnoozeable("summon_gargoyle", 60)
DH:RegisterSnoozeable("empower_rune_weapon", 60)

-- ============================================================================
-- RUNE HELPER (used by Core.lua)
-- Reads GetRuneCooldown/GetRuneType to count available runes.
-- Rune slots: 1-2 Blood, 3-4 Unholy, 5-6 Frost (or Death runes)
-- ============================================================================

---Returns counts of ready blood, frost, unholy, and death runes.
function ns.GetRuneCounts()
    local blood, frost, unholy, death = 0, 0, 0, 0
    for i = 1, 6 do
        local start, duration, ready = GetRuneCooldown(i)
        if ready then
            local runeType = GetRuneType(i)
            if runeType == 1 then blood = blood + 1
            elseif runeType == 2 then unholy = unholy + 1  -- 2 = Unholy in 3.3.5a
            elseif runeType == 3 then frost = frost + 1
            elseif runeType == 4 then death = death + 1
            end
        end
    end
    return blood, frost, unholy, death
end

-- ============================================================================
-- SLASH COMMANDS
-- ============================================================================

DH:RegisterSlashCommand("dk", function(cmd)
    local s = DH.State
    DH:UpdateState()
    local b, f, u, d = ns.GetRuneCounts()
    DH:Print("--- Death Knight Status ---")
    DH:Print(string.format("Runes: B:%d F:%d U:%d D:%d | RP: %d", b, f, u, d, s.runic_power.current))
    DH:Print("Frost Fever: " .. (s.debuff.frost_fever.up and string.format("%.1fs", s.debuff.frost_fever.remains) or "DOWN"))
    DH:Print("Blood Plague: " .. (s.debuff.blood_plague.up and string.format("%.1fs", s.debuff.blood_plague.remains) or "DOWN"))
    DH:Print("KM: " .. (s.buff.killing_machine.up and "UP" or "no") .. " | Rime: " .. (s.buff.freezing_fog.up and "UP" or "no"))
    DH:Print("TTD: " .. tostring(s.target.time_to_die) .. "s")
end, "dk - Show death knight status")

-- ============================================================================
-- DEBUG FRAME
-- ============================================================================

ns.registered.debugFrameUpdater = function()
    if not ns.DebugFrame then return end

    local s = DH.State
    local b, f, u, d = ns.GetRuneCounts()
    local rec1 = ns.recommendations[1] and ns.recommendations[1].ability or "none"
    local rec2 = ns.recommendations[2] and ns.recommendations[2].ability or "none"
    local rec3 = ns.recommendations[3] and ns.recommendations[3].ability or "none"

    local lines = {
        "|cFFFFFF00=== Live Debug ===|r",
        string.format("B:%d F:%d U:%d D:%d | RP:%d", b, f, u, d, s.runic_power.current),
        string.format("FF:%.1f BP:%.1f", s.debuff.frost_fever.remains, s.debuff.blood_plague.remains),
        string.format("KM:%s Rime:%s SD:%s", s.buff.killing_machine.up and "Y" or "N", s.buff.freezing_fog.up and "Y" or "N", s.buff.sudden_doom.up and "Y" or "N"),
        string.format("|cFFFFFF00Rec: %s > %s > %s|r", rec1, rec2, rec3),
    }

    ns.DebugFrame.text:SetText(table.concat(lines, "\n"))
    ns.DebugFrame:Show()
end

