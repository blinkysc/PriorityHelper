-- Classes/Priest/Priest.lua
-- Priest class module: ability definitions + registration (Shadow DPS only)

local DH = PriorityHelper
if not DH then return end

if select(2, UnitClass("player")) ~= "PRIEST" then
    return
end

local ns = DH.ns
local class = DH.Class

-- ============================================================================
-- SPELL IDS (max rank for 3.3.5a)
-- ============================================================================

local SPELLS = {
    -- Shadow
    SHADOW_WORD_PAIN = 48125,
    VAMPIRIC_TOUCH = 48160,
    DEVOURING_PLAGUE = 48300,
    MIND_BLAST = 48127,
    MIND_FLAY = 48156,
    MIND_SEAR = 53023,
    SHADOW_WORD_DEATH = 48158,
    SHADOWFIEND = 34433,
    DISPERSION = 47585,
    SHADOWFORM = 15473,
    VAMPIRIC_EMBRACE = 15286,
    INNER_FOCUS = 14751,

    -- Shared
    POWER_WORD_SHIELD = 48066,
    FADE = 586,
}

ns.SPELLS = SPELLS

-- ============================================================================
-- ABILITY DEFINITIONS
-- ============================================================================

class.abilities = {
    shadow_word_pain = {
        id = SPELLS.SHADOW_WORD_PAIN,
        name = "Shadow Word: Pain",
        texture = 136207,
    },
    vampiric_touch = {
        id = SPELLS.VAMPIRIC_TOUCH,
        name = "Vampiric Touch",
        texture = 135978,
    },
    devouring_plague = {
        id = SPELLS.DEVOURING_PLAGUE,
        name = "Devouring Plague",
        texture = 136188,
    },
    mind_blast = {
        id = SPELLS.MIND_BLAST,
        name = "Mind Blast",
        texture = 136224,
    },
    mind_flay = {
        id = SPELLS.MIND_FLAY,
        name = "Mind Flay",
        texture = 136208,
    },
    shadow_word_death = {
        id = SPELLS.SHADOW_WORD_DEATH,
        name = "Shadow Word: Death",
        texture = 136149,
    },
    shadowfiend = {
        id = SPELLS.SHADOWFIEND,
        name = "Shadowfiend",
        texture = 136199,
    },
    dispersion = {
        id = SPELLS.DISPERSION,
        name = "Dispersion",
        texture = 237563,
    },
    shadowform = {
        id = SPELLS.SHADOWFORM,
        name = "Shadowform",
        texture = 136200,
    },
    vampiric_embrace = {
        id = SPELLS.VAMPIRIC_EMBRACE,
        name = "Vampiric Embrace",
        texture = 136230,
    },
    inner_focus = {
        id = SPELLS.INNER_FOCUS,
        name = "Inner Focus",
        texture = 135863,
    },
}

-- Create name mapping and get textures
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
-- REGISTER PRIEST DATA INTO FRAMEWORK
-- ============================================================================

DH:RegisterGCDSpell(SPELLS.MIND_BLAST)

DH:RegisterMeleeAbilities({})

-- Buffs to track
DH:RegisterBuffs({
    "shadowform",
    "vampiric_embrace",
    "inner_focus",
    "shadow_weaving",
    "improved_spirit_tap",
    "dispersion",
})

-- Debuffs to track
DH:RegisterDebuffs({
    "shadow_word_pain",
    "vampiric_touch",
    "devouring_plague",
    "shadow_weaving_debuff",
    "misery",
})

-- Cooldowns
DH:RegisterCooldowns({
    mind_blast = 48127,
    shadow_word_death = 48158,
    shadowfiend = 34433,
    dispersion = 47585,
    inner_focus = 14751,
})

-- Talents
DH:RegisterTalents({
    -- Discipline
    { 1, 3, "inner_focus" },
    { 1, 5, "improved_power_word_fortitude" },
    { 1, 7, "meditation" },
    { 1, 9, "inner_focus_talent" },
    { 1, 14, "focused_power" },

    -- Holy (minimal for Shadow)
    { 2, 1, "healing_focus" },
    { 2, 3, "improved_renew" },

    -- Shadow
    { 3, 1, "spirit_tap" },
    { 3, 2, "improved_spirit_tap" },
    { 3, 3, "darkness" },
    { 3, 4, "shadow_affinity" },
    { 3, 5, "improved_shadow_word_pain" },
    { 3, 6, "shadow_focus" },
    { 3, 7, "improved_psychic_scream" },
    { 3, 8, "improved_mind_blast" },
    { 3, 9, "mind_flay" },
    { 3, 10, "veiled_shadows" },
    { 3, 11, "shadow_reach" },
    { 3, 12, "shadow_weaving" },
    { 3, 13, "silence" },
    { 3, 14, "vampiric_embrace" },
    { 3, 15, "improved_vampiric_embrace" },
    { 3, 16, "focused_mind" },
    { 3, 17, "mind_melt" },
    { 3, 18, "improved_devouring_plague" },
    { 3, 19, "shadowform" },
    { 3, 20, "shadow_power" },
    { 3, 21, "improved_shadowform" },
    { 3, 22, "misery" },
    { 3, 23, "psychic_horror" },
    { 3, 24, "vampiric_touch" },
    { 3, 25, "pain_and_suffering" },
    { 3, 26, "twisted_faith" },
    { 3, 27, "dispersion" },
})

-- Glyphs
DH:RegisterGlyphs({
    [55687] = "shadow_word_pain",  -- Glyph of SWP
    [55688] = "mind_flay",         -- Glyph of Mind Flay
    [55689] = "shadow",            -- Glyph of Shadow (Shadowy Insight)
    [55691] = "mind_blast",        -- Glyph of Mind Blast (not a real one, placeholder)
    [63229] = "dispersion",        -- Glyph of Dispersion
    [55692] = "shadow_word_death", -- Glyph of SWD
})

-- Buff spell ID -> key mapping
DH:RegisterBuffMap({
    [15473] = "shadowform",
    [15286] = "vampiric_embrace",
    [14751] = "inner_focus",
    [15258] = "shadow_weaving",
    [59000] = "improved_spirit_tap",
    [47585] = "dispersion",
})

-- Debuff spell ID -> key mapping
DH:RegisterDebuffMap({
    -- Shadow Word: Pain (all ranks)
    [48125] = "shadow_word_pain", [48124] = "shadow_word_pain",
    [25368] = "shadow_word_pain", [11679] = "shadow_word_pain",
    [11678] = "shadow_word_pain", [10894] = "shadow_word_pain",
    [10893] = "shadow_word_pain", [2767] = "shadow_word_pain", [594] = "shadow_word_pain",
    -- Vampiric Touch
    [48160] = "vampiric_touch", [48159] = "vampiric_touch",
    [34917] = "vampiric_touch", [34916] = "vampiric_touch", [34914] = "vampiric_touch",
    -- Devouring Plague
    [48300] = "devouring_plague", [48299] = "devouring_plague",
    [25467] = "devouring_plague",
})

DH:RegisterDebuffNamePatterns({
    { "shadow word: pain", "shadow_word_pain" },
    { "vampiric touch", "vampiric_touch" },
    { "devouring plague", "devouring_plague" },
})

DH:RegisterExternalDebuffMap({})
DH:RegisterExternalDebuffNamePatterns({})

-- ============================================================================
-- SPEC DETECTION
-- ============================================================================

DH:RegisterSpecDetector(function()
    local disc, holy, shadow = 0, 0, 0

    for i = 1, GetNumTalentTabs() do
        local _, _, points = GetTalentTabInfo(i)
        if i == 1 then disc = points
        elseif i == 2 then holy = points
        else shadow = points
        end
    end

    if shadow > disc and shadow > holy then
        return "shadow"
    elseif disc > holy then
        return "discipline"
    else
        return "holy"
    end
end)

-- ============================================================================
-- DEFAULT SETTINGS
-- ============================================================================

DH:RegisterDefaults({
    shadow = { enabled = true },
    common = { dummy_ttd = 300 },
})

DH:RegisterSnoozeable("shadowfiend", 60)

-- ============================================================================
-- SLASH COMMANDS
-- ============================================================================

DH:RegisterSlashCommand("sp", function(cmd)
    local s = DH.State
    DH:UpdateState()
    DH:Print("--- Shadow Priest Status ---")
    DH:Print("Mana: " .. tostring(math.floor(s.mana.pct)) .. "%")
    DH:Print("SWP: " .. (s.debuff.shadow_word_pain.up and string.format("%.1fs", s.debuff.shadow_word_pain.remains) or "DOWN"))
    DH:Print("VT: " .. (s.debuff.vampiric_touch.up and string.format("%.1fs", s.debuff.vampiric_touch.remains) or "DOWN"))
    DH:Print("DP: " .. (s.debuff.devouring_plague.up and string.format("%.1fs", s.debuff.devouring_plague.remains) or "DOWN"))
    DH:Print("MB CD: " .. (s.cooldown.mind_blast.ready and "READY" or string.format("%.1fs", s.cooldown.mind_blast.remains)))
    DH:Print("TTD: " .. tostring(s.target.time_to_die) .. "s")
end, "sp - Show shadow priest status")

-- ============================================================================
-- DEBUG FRAME
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
        string.format("SWP:%.1f VT:%.1f DP:%.1f", s.debuff.shadow_word_pain.remains, s.debuff.vampiric_touch.remains, s.debuff.devouring_plague.remains),
        string.format("MB: %s | SWD: %s", s.cooldown.mind_blast.ready and "RDY" or string.format("%.1f", s.cooldown.mind_blast.remains), s.cooldown.shadow_word_death.ready and "RDY" or string.format("%.1f", s.cooldown.shadow_word_death.remains)),
        string.format("|cFFFFFF00Rec: %s > %s > %s|r", rec1, rec2, rec3),
    }

    ns.DebugFrame.text:SetText(table.concat(lines, "\n"))
    ns.DebugFrame:Show()
end

-- ============================================================================
-- MIND FLAY CLIP GLOW
-- Glow REC1 icon right after a Mind Flay tick lands to signal optimal clip time.
-- MF has 3 ticks over the channel duration (haste-adjusted).
-- Glow activates in a 0.3s window after each tick completes.
-- Only glows when REC1 is NOT mind_flay (i.e., something higher priority is ready).
-- ============================================================================

ns.registered.glowUpdater = function()
    ns.glowButtons = nil  -- reset each frame

    -- Only relevant when channeling Mind Flay
    local spell, _, _, _, startTime, endTime = UnitChannelInfo("player")
    if not spell or not startTime or not endTime then return end

    -- Check if channeling Mind Flay (match by name since ID may vary)
    local mfName = GetSpellInfo(SPELLS.MIND_FLAY)
    if spell ~= mfName then return end

    -- Only glow if REC1 is something other than Mind Flay (something to clip for)
    local rec1 = ns.recommendations[1]
    if not rec1 or rec1.ability == "mind_flay" then return end

    -- Calculate tick timing
    local now = GetTime()
    local channelStart = startTime / 1000
    local channelEnd = endTime / 1000
    local channelDuration = channelEnd - channelStart
    local tickInterval = channelDuration / 3  -- 3 ticks
    local elapsed = now - channelStart

    -- Check if we're in the clip window (within 0.3s after a tick)
    local currentTick = math.floor(elapsed / tickInterval)
    if currentTick >= 1 then
        local timeSinceTick = elapsed - (currentTick * tickInterval)
        if timeSinceTick >= 0 and timeSinceTick < 0.3 then
            ns.glowButtons = { [1] = true }
        end
    end
end
