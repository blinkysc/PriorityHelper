-- Classes/Priest/Core.lua
-- Priority rotation logic for Priest Shadow spec (3.3.5a compatible)
-- Uses core RunSimulation for CD-aware predictions

local DH = PriorityHelper
if not DH then return end

if select(2, UnitClass("player")) ~= "PRIEST" then
    return
end

local ns = DH.ns
local class = DH.Class
local state = DH.State

-- ============================================================================
-- SHADOW ROTATION
-- DoT maintenance > Mind Blast on CD > Mind Flay filler
-- ============================================================================

local shadowConfig = {
    gcdType = "spell",
    maxRecs = 3,
    allowDupes = true,
    cds = {
        mind_blast = "mind_blast",
        shadow_word_death = "shadow_word_death",
        shadowfiend = "shadowfiend",
        dispersion = "dispersion",
        inner_focus = "inner_focus",
    },
    baseCDs = {
        mind_blast = 8,
        shadow_word_death = 12,
        shadowfiend = 300,
        dispersion = 120,
        inner_focus = 180,
    },
    auras = {
        { up = "swp_up", remains = "swp_remains" },
        { up = "vt_up", remains = "vt_remains" },
        { up = "dp_up", remains = "dp_remains" },
    },
    initState = function(sim, s)
        -- DoTs
        sim.swp_up = s.debuff.shadow_word_pain.up
        sim.swp_remains = s.debuff.shadow_word_pain.remains
        sim.vt_up = s.debuff.vampiric_touch.up
        sim.vt_remains = s.debuff.vampiric_touch.remains
        sim.dp_up = s.debuff.devouring_plague.up
        sim.dp_remains = s.debuff.devouring_plague.remains

        -- Buffs
        sim.shadowform_up = s.buff.shadowform.up

        -- Talents
        sim.has_vt = s.talent.vampiric_touch.rank > 0
        sim.has_dp = true  -- all priests have DP
        sim.has_dispersion = s.talent.dispersion.rank > 0
        sim.has_shadowform = s.talent.shadowform.rank > 0
        sim.has_mind_flay = s.talent.mind_flay.rank > 0

        -- Improved Mind Blast reduces CD
        local imb_rank = s.talent.improved_mind_blast.rank or 0
        sim.mb_cd = 8 - (imb_rank * 0.5)

        -- Glyph of Dispersion
        sim.disp_cd = (s.glyph.dispersion and s.glyph.dispersion.enabled) and 75 or 120
    end,
    getPriority = function(sim, recs)
        -- Shadowform if not active
        if sim.has_shadowform and not sim.shadowform_up then
            return "shadowform"
        end

        -- Dispersion for mana emergency
        if sim.has_dispersion and sim.mana_pct < 10 and sim:ready("dispersion") and sim.ttd > 6 then
            return "dispersion"
        end

        -- Shadowfiend for mana
        if sim.mana_pct < 30 and sim:ready("shadowfiend") and not DH:IsSnoozed("shadowfiend") then
            return "shadowfiend"
        end

        -- Vampiric Touch: maintain (cast time ~1.5s, refresh before it falls off)
        if sim.has_vt and (not sim.vt_up or sim.vt_remains < 2) and sim.ttd > 6 then
            return "vampiric_touch"
        end

        -- Devouring Plague: maintain (instant)
        if not sim.dp_up and sim.ttd > 6 then
            return "devouring_plague"
        end

        -- Shadow Word: Pain: maintain (instant)
        if (not sim.swp_up or sim.swp_remains < 2) and sim.ttd > 6 then
            return "shadow_word_pain"
        end

        -- Mind Blast on CD (high damage, generates Replenishment with VT)
        if sim:ready("mind_blast") then
            return "mind_blast"
        end

        -- Shadow Word: Death (execute / filler when MB on CD)
        if sim:ready("shadow_word_death") and sim.in_execute then
            return "shadow_word_death"
        end

        -- Mind Flay filler
        if sim.has_mind_flay then
            return "mind_flay"
        end

        return nil
    end,
    onCast = function(sim, key)
        if key == "vampiric_touch" then
            sim.vt_up = true
            sim.vt_remains = 15
        elseif key == "devouring_plague" then
            sim.dp_up = true
            sim.dp_remains = 24
        elseif key == "shadow_word_pain" then
            sim.swp_up = true
            sim.swp_remains = 18
        elseif key == "mind_blast" then
            sim.cd["mind_blast"] = sim.mb_cd
        elseif key == "dispersion" then
            sim.mana_pct = math.min(100, sim.mana_pct + 36)
            sim.cd["dispersion"] = sim.disp_cd
        elseif key == "shadowform" then
            sim.shadowform_up = true
        end
    end,
    getAdvanceTime = function(sim, action)
        local h = sim.haste or 1
        if action == "vampiric_touch" then return math.max(sim.gcd, 1.5 / h) end
        if action == "mind_blast" then return math.max(sim.gcd, 1.5 / h) end
        if action == "mind_flay" then return math.max(sim.gcd, 3.0 / h) end  -- full channel
        if action == "dispersion" then return math.max(sim.gcd, 6.0) end
        return sim.gcd  -- instants: SWP, DP, SWD, Shadowfiend, Shadowform
    end,
}

local function GetShadowRecommendations(addon)
    return DH:RunSimulation(state, shadowConfig)
end

-- ============================================================================
-- ROTATION MODES
-- ============================================================================

DH:RegisterMode("shadow", {
    name = "Shadow (DPS)",
    icon = select(3, GetSpellInfo(15473)) or "Interface\\Icons\\Spell_Shadow_Shadowform",
    rotation = function(addon)
        return GetShadowRecommendations(addon)
    end,
})
