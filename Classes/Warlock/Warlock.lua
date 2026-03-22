-- Classes/Warlock/Warlock.lua
-- Warlock class module: ability definitions + registration of all Warlock-specific data

local DH = PriorityHelper
if not DH then return end

-- Only load for Warlocks
if select(2, UnitClass("player")) ~= "WARLOCK" then
    return
end

local ns = DH.ns
local class = DH.Class

-- ============================================================================
-- SPELL IDS (max rank for 3.3.5a)
-- ============================================================================

local SPELLS = {
    -- Shadow
    SHADOW_BOLT = 47809,
    CORRUPTION = 47813,
    CURSE_OF_AGONY = 47864,
    CURSE_OF_DOOM = 47867,
    CURSE_OF_ELEMENTS = 47865,
    CURSE_OF_WEAKNESS = 50511,
    CURSE_OF_TONGUES = 11719,
    DRAIN_SOUL = 47855,
    DRAIN_LIFE = 47857,
    SEED_OF_CORRUPTION = 47836,
    DEATH_COIL = 47860,
    FEAR = 6215,
    HOWL_OF_TERROR = 17928,
    SHADOWBURN = 47827,
    SHADOW_CLEAVE = 47838,  -- not a real spell, placeholder

    -- Affliction
    HAUNT = 59164,
    UNSTABLE_AFFLICTION = 47843,

    -- Fire
    IMMOLATE = 47811,
    INCINERATE = 47838,
    CHAOS_BOLT = 59172,
    CONFLAGRATE = 17962,
    SEARING_PAIN = 47815,
    SOUL_FIRE = 47825,
    RAIN_OF_FIRE = 47820,
    HELLFIRE = 47823,
    SHADOWFURY = 47847,

    -- Demonology
    METAMORPHOSIS = 47241,
    DEMONIC_EMPOWERMENT = 47193,
    IMMOLATION_AURA = 50589,

    -- Utility
    LIFE_TAP = 57946,
    DARK_PACT = 59092,
    FEL_ARMOR = 47893,
    DEMON_ARMOR = 47889,
    SHADOW_WARD = 47891,

    -- Pet summons
    SUMMON_IMP = 688,
    SUMMON_VOIDWALKER = 697,
    SUMMON_SUCCUBUS = 712,
    SUMMON_FELHUNTER = 691,
    SUMMON_FELGUARD = 30146,
    SUMMON_INFERNAL = 1122,
    SUMMON_DOOMGUARD = 18540,
}

ns.SPELLS = SPELLS

-- ============================================================================
-- ABILITY DEFINITIONS
-- ============================================================================

class.abilities = {
    -- Shadow
    shadow_bolt = {
        id = SPELLS.SHADOW_BOLT,
        name = "Shadow Bolt",
        texture = 136197,
    },
    corruption = {
        id = SPELLS.CORRUPTION,
        name = "Corruption",
        texture = 136118,
    },
    curse_of_agony = {
        id = SPELLS.CURSE_OF_AGONY,
        name = "Curse of Agony",
        texture = 136139,
    },
    curse_of_doom = {
        id = SPELLS.CURSE_OF_DOOM,
        name = "Curse of Doom",
        texture = 136122,
    },
    curse_of_elements = {
        id = SPELLS.CURSE_OF_ELEMENTS,
        name = "Curse of Elements",
        texture = 136130,
    },
    drain_soul = {
        id = SPELLS.DRAIN_SOUL,
        name = "Drain Soul",
        texture = 136163,
    },
    seed_of_corruption = {
        id = SPELLS.SEED_OF_CORRUPTION,
        name = "Seed of Corruption",
        texture = 136193,
    },
    shadowburn = {
        id = SPELLS.SHADOWBURN,
        name = "Shadowburn",
        texture = 136191,
    },

    -- Affliction
    haunt = {
        id = SPELLS.HAUNT,
        name = "Haunt",
        texture = 236298,
    },
    unstable_affliction = {
        id = SPELLS.UNSTABLE_AFFLICTION,
        name = "Unstable Affliction",
        texture = 136228,
    },

    -- Fire
    immolate = {
        id = SPELLS.IMMOLATE,
        name = "Immolate",
        texture = 135817,
    },
    incinerate = {
        id = SPELLS.INCINERATE,
        name = "Incinerate",
        texture = 135789,
    },
    chaos_bolt = {
        id = SPELLS.CHAOS_BOLT,
        name = "Chaos Bolt",
        texture = 236291,
    },
    conflagrate = {
        id = SPELLS.CONFLAGRATE,
        name = "Conflagrate",
        texture = 135807,
    },
    searing_pain = {
        id = SPELLS.SEARING_PAIN,
        name = "Searing Pain",
        texture = 135827,
    },
    soul_fire = {
        id = SPELLS.SOUL_FIRE,
        name = "Soul Fire",
        texture = 135808,
    },
    shadowfury = {
        id = SPELLS.SHADOWFURY,
        name = "Shadowfury",
        texture = 136201,
    },

    -- Demonology
    metamorphosis = {
        id = SPELLS.METAMORPHOSIS,
        name = "Metamorphosis",
        texture = 237558,
    },
    demonic_empowerment = {
        id = SPELLS.DEMONIC_EMPOWERMENT,
        name = "Demonic Empowerment",
        texture = 236292,
    },
    immolation_aura = {
        id = SPELLS.IMMOLATION_AURA,
        name = "Immolation Aura",
        texture = 135818,
    },

    -- Utility
    life_tap = {
        id = SPELLS.LIFE_TAP,
        name = "Life Tap",
        texture = 136126,
    },
    dark_pact = {
        id = SPELLS.DARK_PACT,
        name = "Dark Pact",
        texture = 136141,
    },
    fel_armor = {
        id = SPELLS.FEL_ARMOR,
        name = "Fel Armor",
        texture = 136156,
    },
    demon_armor = {
        id = SPELLS.DEMON_ARMOR,
        name = "Demon Armor",
        texture = 136185,
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
-- REGISTER WARLOCK DATA INTO FRAMEWORK
-- ============================================================================

-- GCD reference spell (Shadow Bolt)
DH:RegisterGCDSpell(SPELLS.SHADOW_BOLT)

-- Melee abilities (none for warlock, but register empty for framework)
DH:RegisterMeleeAbilities({})

-- Buffs to track
DH:RegisterBuffs({
    -- Self buffs
    "fel_armor", "demon_armor",
    "shadow_trance",  -- Nightfall proc (instant Shadow Bolt)
    "backdraft",
    "molten_core",
    "decimation",
    "metamorphosis",
    "life_tap_glyph",  -- Glyph of Life Tap spirit buff
    "eradication",
    "empowered_imp",
    "demonic_pact",
    "nether_protection",
    "backlash",
})

-- Debuffs to track
DH:RegisterDebuffs({
    "corruption",
    "immolate",
    "curse_of_agony",
    "curse_of_doom",
    "curse_of_elements",
    "unstable_affliction",
    "haunt",
    "seed_of_corruption",
    "shadow_embrace",
    "shadow_mastery",
})

-- Cooldowns
DH:RegisterCooldowns({
    haunt = 59164,
    conflagrate = 17962,
    chaos_bolt = 59172,
    shadowburn = 47827,
    shadowfury = 47847,
    demonic_empowerment = 47193,
    metamorphosis = 47241,
    immolation_aura = 50589,
    death_coil = 47860,
    soul_fire = 47825,
    curse_of_doom = 47867,
})

-- Talents
DH:RegisterTalents({
    -- Affliction
    { 1, 1, "improved_curse_of_agony" },
    { 1, 2, "suppression" },
    { 1, 3, "improved_corruption" },
    { 1, 4, "improved_curse_of_weakness" },
    { 1, 5, "improved_drain_soul" },
    { 1, 6, "improved_life_tap" },
    { 1, 7, "soul_siphon" },
    { 1, 8, "improved_fear" },
    { 1, 9, "fel_concentration" },
    { 1, 10, "amplify_curse" },
    { 1, 11, "grim_reach" },
    { 1, 12, "nightfall" },
    { 1, 13, "empowered_corruption" },
    { 1, 14, "shadow_embrace" },
    { 1, 15, "siphon_life" },
    { 1, 16, "curse_of_exhaustion" },
    { 1, 17, "improved_felhunter" },
    { 1, 18, "shadow_mastery" },
    { 1, 19, "eradication" },
    { 1, 20, "contagion" },
    { 1, 21, "dark_pact" },
    { 1, 22, "improved_howl_of_terror" },
    { 1, 23, "malediction" },
    { 1, 24, "death_embrace" },
    { 1, 25, "unstable_affliction" },
    { 1, 26, "pandemic" },
    { 1, 27, "everlasting_affliction" },
    { 1, 28, "haunt" },

    -- Demonology
    { 2, 1, "improved_healthstone" },
    { 2, 2, "improved_imp" },
    { 2, 3, "demonic_embrace" },
    { 2, 4, "fel_synergy" },
    { 2, 5, "improved_health_funnel" },
    { 2, 6, "demonic_brutality" },
    { 2, 7, "fel_vitality" },
    { 2, 8, "improved_succubus" },
    { 2, 9, "soul_link" },
    { 2, 10, "fel_domination" },
    { 2, 11, "demonic_aegis" },
    { 2, 12, "unholy_power" },
    { 2, 13, "master_summoner" },
    { 2, 14, "mana_feed" },
    { 2, 15, "master_conjuror" },
    { 2, 16, "master_demonologist" },
    { 2, 17, "molten_core" },
    { 2, 18, "demonic_resilience" },
    { 2, 19, "demonic_empowerment" },
    { 2, 20, "demonic_knowledge" },
    { 2, 21, "demonic_tactics" },
    { 2, 22, "decimation" },
    { 2, 23, "improved_demonic_tactics" },
    { 2, 24, "summon_felguard" },
    { 2, 25, "nemesis" },
    { 2, 26, "demonic_pact" },
    { 2, 27, "metamorphosis" },

    -- Destruction
    { 3, 1, "improved_shadow_bolt" },
    { 3, 2, "bane" },
    { 3, 3, "aftermath" },
    { 3, 4, "molten_skin" },
    { 3, 5, "cataclysm" },
    { 3, 6, "demonic_power" },
    { 3, 7, "shadowburn" },
    { 3, 8, "ruin" },
    { 3, 9, "intensity" },
    { 3, 10, "destructive_reach" },
    { 3, 11, "improved_searing_pain" },
    { 3, 12, "backlash" },
    { 3, 13, "improved_immolate" },
    { 3, 14, "devastation" },
    { 3, 15, "nether_protection" },
    { 3, 16, "emberstorm" },
    { 3, 17, "conflagrate" },
    { 3, 18, "soul_leech" },
    { 3, 19, "pyroclasm" },
    { 3, 20, "shadow_and_flame" },
    { 3, 21, "improved_soul_leech" },
    { 3, 22, "backdraft" },
    { 3, 23, "shadowfury" },
    { 3, 24, "empowered_imp" },
    { 3, 25, "fire_and_brimstone" },
    { 3, 26, "chaos_bolt" },
})

-- Glyphs
DH:RegisterGlyphs({
    [63302] = "life_tap",      -- Glyph of Life Tap
    [56218] = "haunt",         -- Glyph of Haunt
    [56232] = "quick_decay",   -- Glyph of Quick Decay
    [56235] = "conflagrate",   -- Glyph of Conflagrate
    [56242] = "incinerate",    -- Glyph of Incinerate
    [56246] = "immolate",      -- Glyph of Immolate
    [56244] = "corruption",    -- Glyph of Corruption
    [56226] = "shadow_bolt",   -- Glyph of Shadow Bolt
    [56248] = "felguard",      -- Glyph of Felguard
    [56250] = "metamorphosis", -- Glyph of Metamorphosis
    [56241] = "chaos_bolt",    -- Glyph of Chaos Bolt
    [56247] = "cursor_of_agony", -- Glyph of Curse of Agony
})

-- Buff spell ID -> key mapping
DH:RegisterBuffMap({
    [47893] = "fel_armor",
    [47889] = "demon_armor",
    [17941] = "shadow_trance",   -- Nightfall proc
    [54277] = "backdraft",
    [71165] = "molten_core",
    [63167] = "decimation",
    [47241] = "metamorphosis",
    [63321] = "life_tap_glyph",  -- Glyph of Life Tap spirit buff
    [64371] = "eradication",
    [47283] = "empowered_imp",
    [47240] = "demonic_pact",
    [30299] = "nether_protection",
    [34936] = "backlash",
})

-- Debuff spell ID -> key mapping (player-applied)
DH:RegisterDebuffMap({
    -- Corruption (all ranks)
    [47813] = "corruption", [47812] = "corruption", [27216] = "corruption",
    [25311] = "corruption", [11672] = "corruption", [11671] = "corruption",
    [7648] = "corruption", [6223] = "corruption", [6222] = "corruption", [172] = "corruption",
    -- Immolate (all ranks)
    [47811] = "immolate", [47810] = "immolate", [27215] = "immolate",
    [25309] = "immolate", [11668] = "immolate", [11667] = "immolate",
    [2941] = "immolate", [1094] = "immolate", [707] = "immolate", [348] = "immolate",
    -- Curse of Agony (all ranks)
    [47864] = "curse_of_agony", [47863] = "curse_of_agony", [27218] = "curse_of_agony",
    [11713] = "curse_of_agony", [11712] = "curse_of_agony",
    [6217] = "curse_of_agony", [980] = "curse_of_agony",
    -- Curse of Doom
    [47867] = "curse_of_doom",
    -- Curse of Elements
    [47865] = "curse_of_elements",
    -- Unstable Affliction
    [47843] = "unstable_affliction", [47841] = "unstable_affliction",
    [30405] = "unstable_affliction", [30404] = "unstable_affliction",
    [30108] = "unstable_affliction",
    -- Haunt
    [59164] = "haunt",
    -- Seed of Corruption
    [47836] = "seed_of_corruption",
    -- Shadow Embrace
    [32391] = "shadow_embrace",
})

-- Debuff name patterns (fallback matching)
DH:RegisterDebuffNamePatterns({
    { "corruption", "corruption" },
    { "immolate", "immolate" },
    { "curse of agony", "curse_of_agony" },
    { "curse of doom", "curse_of_doom" },
    { "curse of the elements", "curse_of_elements" },
    { "unstable affliction", "unstable_affliction" },
    { "haunt", "haunt" },
    { "seed of corruption", "seed_of_corruption" },
    { "shadow embrace", "shadow_embrace" },
})

-- External debuff mapping (from other players)
DH:RegisterExternalDebuffMap({
    [47865] = "curse_of_elements",  -- CoE from another warlock
    [47867] = "curse_of_doom",
    [22959] = "fire_vulnerability",  -- Improved Scorch (mage)
    [33198] = "misery",              -- Misery (shadow priest)
})

DH:RegisterExternalDebuffNamePatterns({
    { "curse of the elements", "curse_of_elements" },
    { "earth and moon", "curse_of_elements" },  -- Druid equivalent
    { "ebon plague", "curse_of_elements" },      -- DK equivalent
})

-- ============================================================================
-- SPEC DETECTION
-- ============================================================================

DH:RegisterSpecDetector(function()
    local affliction, demonology, destruction = 0, 0, 0

    for i = 1, GetNumTalentTabs() do
        local _, _, points = GetTalentTabInfo(i)
        if i == 1 then affliction = points
        elseif i == 2 then demonology = points
        else destruction = points
        end
    end

    if affliction > demonology and affliction > destruction then
        return "affliction"
    elseif demonology > destruction then
        return "demonology"
    else
        return "destruction"
    end
end)

-- ============================================================================
-- DEFAULT SETTINGS (class-specific)
-- ============================================================================

DH:RegisterDefaults({
    affliction = {
        enabled = true,
        use_drain_soul_execute = true,
        life_tap_pct = 30,
    },
    demonology = {
        enabled = true,
        life_tap_pct = 30,
    },
    destruction = {
        enabled = true,
        life_tap_pct = 30,
    },
    common = {
        dummy_ttd = 300,
    },
})

-- Major cooldowns: snoozeable if player skips them (60s snooze)
DH:RegisterSnoozeable("metamorphosis", 60)

-- ============================================================================
-- SLASH COMMANDS (Warlock-specific)
-- ============================================================================

DH:RegisterSlashCommand("lock", function(cmd)
    local s = DH.State
    DH:UpdateState()
    DH:Print("--- Warlock Status ---")
    DH:Print("Mana: " .. tostring(math.floor(s.mana.pct)) .. "%")
    DH:Print("Corruption: " .. (s.debuff.corruption.up and string.format("%.1fs", s.debuff.corruption.remains) or "DOWN"))
    DH:Print("Immolate: " .. (s.debuff.immolate.up and string.format("%.1fs", s.debuff.immolate.remains) or "DOWN"))
    DH:Print("CoA: " .. (s.debuff.curse_of_agony.up and string.format("%.1fs", s.debuff.curse_of_agony.remains) or "DOWN"))
    DH:Print("UA: " .. (s.debuff.unstable_affliction.up and string.format("%.1fs", s.debuff.unstable_affliction.remains) or "DOWN"))
    DH:Print("Haunt: " .. (s.debuff.haunt.up and string.format("%.1fs", s.debuff.haunt.remains) or "DOWN"))
    DH:Print("TTD: " .. tostring(s.target.time_to_die) .. "s")
end, "lock - Show warlock status")

-- ============================================================================
-- DEBUG FRAME (Warlock-specific)
-- ============================================================================

ns.registered.debugFrameUpdater = function()
    if not ns.DebugFrame then return end

    local s = DH.State
    local rec1 = ns.recommendations[1] and ns.recommendations[1].ability or "none"
    local rec2 = ns.recommendations[2] and ns.recommendations[2].ability or "none"
    local rec3 = ns.recommendations[3] and ns.recommendations[3].ability or "none"

    local lines = {
        "|cFFFFFF00=== Live Debug ===|r",
        string.format("Mana: %d%% | GCD: %.2f", math.floor(s.mana.pct), s.gcd_remains),
        string.format("Corr:%.1f Immo:%.1f UA:%.1f", s.debuff.corruption.remains, s.debuff.immolate.remains, s.debuff.unstable_affliction.remains),
        string.format("CoA:%.1f Haunt:%.1f", s.debuff.curse_of_agony.remains, s.debuff.haunt.remains),
        string.format("|cFFFFFF00Rec: %s > %s > %s|r", rec1, rec2, rec3),
    }

    ns.DebugFrame.text:SetText(table.concat(lines, "\n"))
    ns.DebugFrame:Show()
end
