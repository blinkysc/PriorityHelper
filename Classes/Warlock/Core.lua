-- Classes/Warlock/Core.lua
-- Priority rotation logic for Warlock specs (3.3.5a compatible)
-- Uses core RunSimulation for CD-aware predictions

local DH = PriorityHelper
if not DH then return end

if select(2, UnitClass("player")) ~= "WARLOCK" then
    return
end

local ns = DH.ns
local class = DH.Class
local state = DH.State

-- ============================================================================
-- SHARED HELPERS
-- ============================================================================

-- Common auras used across specs
local function MakeDoTAura(name)
    return { up = name .. "_up", remains = name .. "_remains" }
end

-- Life Tap check: shared across all specs
local function NeedsLifeTap(sim)
    return sim.mana_pct < (DH.db and DH.db[sim._spec] and DH.db[sim._spec].life_tap_pct or 30)
end

-- Glyph of Life Tap buff maintenance
local function NeedsLifeTapGlyph(sim)
    return sim.has_life_tap_glyph and sim.life_tap_glyph_remains < 3 and sim.ttd > 10
end

-- ============================================================================
-- AFFLICTION ROTATION
-- ============================================================================

local afflictionConfig = {
    gcdType = "spell",
    maxRecs = 3,
    allowDupes = true,
    cds = {
        haunt = "haunt",
        curse_of_doom = "curse_of_doom",
    },
    baseCDs = {
        haunt = 8,
        curse_of_doom = 60,
    },
    auras = {
        { up = "corruption_up", remains = "corruption_remains" },
        { up = "ua_up", remains = "ua_remains" },
        { up = "coa_up", remains = "coa_remains" },
        { up = "haunt_up", remains = "haunt_remains" },
        { up = "shadow_embrace_up", remains = "shadow_embrace_remains" },
        { up = "life_tap_glyph_up", remains = "life_tap_glyph_remains" },
    },
    initState = function(sim, s)
        sim._spec = "affliction"
        -- DoTs
        sim.corruption_up = s.debuff.corruption.up
        sim.corruption_remains = s.debuff.corruption.remains
        sim.ua_up = s.debuff.unstable_affliction.up
        sim.ua_remains = s.debuff.unstable_affliction.remains
        sim.coa_up = s.debuff.curse_of_agony.up
        sim.coa_remains = s.debuff.curse_of_agony.remains
        sim.haunt_up = s.debuff.haunt.up
        sim.haunt_remains = s.debuff.haunt.remains
        sim.shadow_embrace_up = s.debuff.shadow_embrace.up
        sim.shadow_embrace_remains = s.debuff.shadow_embrace.remains

        -- Buffs
        sim.shadow_trance = s.buff.shadow_trance.up  -- Nightfall proc
        sim.life_tap_glyph_up = s.buff.life_tap_glyph.up
        sim.life_tap_glyph_remains = s.buff.life_tap_glyph.remains
        sim.eradication_up = s.buff.eradication.up

        -- Talents & glyphs
        sim.has_haunt = s.talent.haunt.rank > 0
        sim.has_ua = s.talent.unstable_affliction.rank > 0
        sim.has_everlasting = s.talent.everlasting_affliction.rank > 0
        sim.has_life_tap_glyph = s.glyph.life_tap and s.glyph.life_tap.enabled
        sim.has_drain_soul_execute = DH.db and DH.db.affliction and DH.db.affliction.use_drain_soul_execute
    end,
    getPriority = function(sim, recs)
        -- Life Tap when mana is low
        if NeedsLifeTap(sim) and sim.ttd > 5 then
            return "life_tap"
        end

        -- Glyph of Life Tap maintenance
        if NeedsLifeTapGlyph(sim) then
            return "life_tap"
        end

        -- Haunt on CD (highest DPS priority - amplifies all DoTs)
        if sim.has_haunt and sim:ready("haunt") then
            return "haunt"
        end

        -- Corruption (instant, maintain at all times)
        if not sim.corruption_up and sim.ttd > 6 then
            return "corruption"
        end

        -- Unstable Affliction (maintain DoT)
        if sim.has_ua and (not sim.ua_up or sim.ua_remains < 2) and sim.ttd > 8 then
            return "unstable_affliction"
        end

        -- Curse of Agony (maintain)
        if (not sim.coa_up or sim.coa_remains < 2) and sim.ttd > 8 then
            return "curse_of_agony"
        end

        -- Execute phase: Drain Soul below 25% HP
        if sim.has_drain_soul_execute and sim.in_execute then
            return "drain_soul"
        end

        -- Nightfall proc: instant Shadow Bolt
        if sim.shadow_trance then
            return "shadow_bolt"
        end

        -- Filler: Shadow Bolt
        return "shadow_bolt"
    end,
    onCast = function(sim, key)
        if key == "corruption" then
            sim.corruption_up = true
            sim.corruption_remains = 18  -- 6 ticks x 3s
        elseif key == "unstable_affliction" then
            sim.ua_up = true
            sim.ua_remains = 15  -- 5 ticks x 3s
        elseif key == "curse_of_agony" then
            sim.coa_up = true
            sim.coa_remains = 24  -- 12 ticks x 2s
        elseif key == "haunt" then
            sim.haunt_up = true
            sim.haunt_remains = 12
        elseif key == "life_tap" then
            sim.mana_pct = math.min(100, sim.mana_pct + 20)
            if sim.has_life_tap_glyph then
                sim.life_tap_glyph_up = true
                sim.life_tap_glyph_remains = 40
            end
        elseif key == "shadow_bolt" then
            sim.shadow_trance = false  -- consume Nightfall proc
            sim.shadow_embrace_up = true
            sim.shadow_embrace_remains = 12
        elseif key == "drain_soul" then
            -- channeled, no special sim state
        end
    end,
    getAdvanceTime = function(sim, action)
        local h = sim.haste or 1
        if action == "unstable_affliction" then return math.max(sim.gcd, 1.5 / h) end
        if action == "shadow_bolt" then
            if sim.shadow_trance then return sim.gcd end  -- instant with Nightfall
            return math.max(sim.gcd, 2.5 / h)
        end
        if action == "haunt" then return math.max(sim.gcd, 1.5 / h) end
        if action == "soul_fire" then return math.max(sim.gcd, 4.0 / h) end
        if action == "drain_soul" then return math.max(sim.gcd, 3.0 / h) end  -- 1 tick
        return sim.gcd  -- instants: corruption, CoA, life tap
    end,
}

local function GetAfflictionRecommendations(addon)
    return DH:RunSimulation(state, afflictionConfig)
end

-- ============================================================================
-- DEMONOLOGY ROTATION
-- ============================================================================

local demonologyConfig = {
    gcdType = "spell",
    maxRecs = 3,
    allowDupes = true,
    cds = {
        metamorphosis = "metamorphosis",
        demonic_empowerment = "demonic_empowerment",
        immolation_aura = "immolation_aura",
        curse_of_doom = "curse_of_doom",
    },
    baseCDs = {
        metamorphosis = 180,
        demonic_empowerment = 60,
        immolation_aura = 30,
        curse_of_doom = 60,
    },
    auras = {
        { up = "corruption_up", remains = "corruption_remains" },
        { up = "immolate_up", remains = "immolate_remains" },
        { up = "coa_up", remains = "coa_remains" },
        { up = "life_tap_glyph_up", remains = "life_tap_glyph_remains" },
        { up = "decimation_up", remains = "decimation_remains" },
        { up = "molten_core_up", remains = "molten_core_remains" },
        { up = "meta_up", remains = "meta_remains" },
    },
    initState = function(sim, s)
        sim._spec = "demonology"
        -- DoTs
        sim.corruption_up = s.debuff.corruption.up
        sim.corruption_remains = s.debuff.corruption.remains
        sim.immolate_up = s.debuff.immolate.up
        sim.immolate_remains = s.debuff.immolate.remains
        sim.coa_up = s.debuff.curse_of_agony.up
        sim.coa_remains = s.debuff.curse_of_agony.remains

        -- Buffs/procs
        sim.decimation_up = s.buff.decimation.up
        sim.decimation_remains = s.buff.decimation.remains
        sim.molten_core_up = s.buff.molten_core.up
        sim.molten_core_remains = s.buff.molten_core.remains
        sim.molten_core_stacks = s.buff.molten_core.stacks or 0
        sim.meta_up = s.buff.metamorphosis.up
        sim.meta_remains = s.buff.metamorphosis.remains
        sim.life_tap_glyph_up = s.buff.life_tap_glyph.up
        sim.life_tap_glyph_remains = s.buff.life_tap_glyph.remains

        -- Talents & glyphs
        sim.has_meta = s.talent.metamorphosis.rank > 0
        sim.has_decimation = s.talent.decimation.rank > 0
        sim.has_molten_core = s.talent.molten_core.rank > 0
        sim.has_demonic_emp = s.talent.demonic_empowerment.rank > 0
        sim.has_life_tap_glyph = s.glyph.life_tap and s.glyph.life_tap.enabled
    end,
    getPriority = function(sim, recs)
        -- Life Tap when mana is low
        if NeedsLifeTap(sim) and sim.ttd > 5 then
            return "life_tap"
        end

        -- Glyph of Life Tap maintenance
        if NeedsLifeTapGlyph(sim) then
            return "life_tap"
        end

        -- Metamorphosis (major CD)
        if sim.has_meta and sim:ready("metamorphosis") and not DH:IsSnoozed("metamorphosis") then
            return "metamorphosis"
        end

        -- Demonic Empowerment (pet buff, use on CD)
        if sim.has_demonic_emp and sim:ready("demonic_empowerment") then
            return "demonic_empowerment"
        end

        -- Immolation Aura (once per Metamorphosis, when off CD)
        if sim.meta_up and sim:ready("immolation_aura") then
            return "immolation_aura"
        end

        -- Corruption (instant, maintain)
        if not sim.corruption_up and sim.ttd > 6 then
            return "corruption"
        end

        -- Immolate (maintain for Molten Core procs... wait, MC procs from Corruption)
        -- Still good DPS to maintain Immolate
        if (not sim.immolate_up or sim.immolate_remains < 2) and sim.ttd > 8 then
            return "immolate"
        end

        -- Curse of Agony or Curse of Doom based on TTD
        if sim.ttd >= 60 and sim:ready("curse_of_doom") and not sim.coa_up then
            return "curse_of_doom"
        end
        if (not sim.coa_up or sim.coa_remains < 2) and sim.ttd > 8 then
            return "curse_of_agony"
        end

        -- Decimation proc: Soul Fire (reduced cast time)
        if sim.has_decimation and sim.decimation_up then
            return "soul_fire"
        end

        -- Molten Core proc: Incinerate (increased damage)
        if sim.has_molten_core and sim.molten_core_up then
            return "incinerate"
        end

        -- Filler: Shadow Bolt
        return "shadow_bolt"
    end,
    onCast = function(sim, key)
        if key == "corruption" then
            sim.corruption_up = true
            sim.corruption_remains = 18
        elseif key == "immolate" then
            sim.immolate_up = true
            sim.immolate_remains = 15
        elseif key == "curse_of_agony" then
            sim.coa_up = true
            sim.coa_remains = 24
        elseif key == "metamorphosis" then
            sim.meta_up = true
            sim.meta_remains = 30
        elseif key == "soul_fire" then
            sim.decimation_up = false
            sim.decimation_remains = 0
        elseif key == "incinerate" then
            sim.molten_core_stacks = sim.molten_core_stacks - 1
            if sim.molten_core_stacks <= 0 then
                sim.molten_core_up = false
                sim.molten_core_remains = 0
                sim.molten_core_stacks = 0
            end
        elseif key == "life_tap" then
            sim.mana_pct = math.min(100, sim.mana_pct + 20)
            if sim.has_life_tap_glyph then
                sim.life_tap_glyph_up = true
                sim.life_tap_glyph_remains = 40
            end
        end
    end,
    getAdvanceTime = function(sim, action)
        local h = sim.haste or 1
        if action == "shadow_bolt" then return math.max(sim.gcd, 2.5 / h) end
        if action == "soul_fire" then
            if sim.decimation_up then return math.max(sim.gcd, 2.0 / h) end
            return math.max(sim.gcd, 4.0 / h)
        end
        if action == "immolate" then return math.max(sim.gcd, 2.0 / h) end
        if action == "incinerate" then return math.max(sim.gcd, 2.0 / h) end
        return sim.gcd  -- instants: corruption, CoA, life tap, meta, DE, immo aura
    end,
}

local function GetDemonologyRecommendations(addon)
    return DH:RunSimulation(state, demonologyConfig)
end

-- ============================================================================
-- DESTRUCTION ROTATION
-- ============================================================================

local destructionConfig = {
    gcdType = "spell",
    maxRecs = 3,
    allowDupes = true,
    cds = {
        conflagrate = "conflagrate",
        chaos_bolt = "chaos_bolt",
        shadowfury = "shadowfury",
    },
    baseCDs = {
        conflagrate = 10,
        chaos_bolt = 12,
        shadowfury = 20,
    },
    auras = {
        { up = "immolate_up", remains = "immolate_remains" },
        { up = "corruption_up", remains = "corruption_remains" },
        { up = "life_tap_glyph_up", remains = "life_tap_glyph_remains" },
        { up = "backdraft_up", remains = "backdraft_remains" },
    },
    initState = function(sim, s)
        sim._spec = "destruction"
        -- DoTs
        sim.immolate_up = s.debuff.immolate.up
        sim.immolate_remains = s.debuff.immolate.remains
        sim.corruption_up = s.debuff.corruption.up
        sim.corruption_remains = s.debuff.corruption.remains

        -- Buffs
        sim.backdraft_up = s.buff.backdraft.up
        sim.backdraft_remains = s.buff.backdraft.remains
        sim.backdraft_stacks = s.buff.backdraft.stacks or 0
        sim.life_tap_glyph_up = s.buff.life_tap_glyph.up
        sim.life_tap_glyph_remains = s.buff.life_tap_glyph.remains
        sim.backlash_up = s.buff.backlash.up
        sim.molten_core_up = s.buff.molten_core.up

        -- Talents & glyphs
        sim.has_conflag = s.talent.conflagrate.rank > 0
        sim.has_chaos_bolt = s.talent.chaos_bolt.rank > 0
        sim.has_backdraft = s.talent.backdraft.rank > 0
        sim.has_life_tap_glyph = s.glyph.life_tap and s.glyph.life_tap.enabled
        sim.has_conflag_glyph = s.glyph.conflagrate and s.glyph.conflagrate.enabled
    end,
    getPriority = function(sim, recs)
        -- Life Tap when mana is low
        if NeedsLifeTap(sim) and sim.ttd > 5 then
            return "life_tap"
        end

        -- Glyph of Life Tap maintenance
        if NeedsLifeTapGlyph(sim) then
            return "life_tap"
        end

        -- Immolate (engine for Conflagrate - must be up first)
        if (not sim.immolate_up or sim.immolate_remains < 2) and sim.ttd > 8 then
            return "immolate"
        end

        -- Conflagrate (highest priority when Immolate is up)
        if sim.has_conflag and sim.immolate_up and sim:ready("conflagrate") then
            return "conflagrate"
        end

        -- Chaos Bolt
        if sim.has_chaos_bolt and sim:ready("chaos_bolt") then
            return "chaos_bolt"
        end

        -- Corruption (maintain for extra DPS, instant cast)
        if not sim.corruption_up and sim.ttd > 6 then
            return "corruption"
        end

        -- Filler: Incinerate (boosted by Immolate)
        return "incinerate"
    end,
    onCast = function(sim, key)
        if key == "immolate" then
            sim.immolate_up = true
            sim.immolate_remains = 15
        elseif key == "conflagrate" then
            -- Glyph of Conflagrate: does NOT consume Immolate
            if not sim.has_conflag_glyph then
                sim.immolate_up = false
                sim.immolate_remains = 0
            end
            -- Triggers Backdraft (3 charges)
            if sim.has_backdraft then
                sim.backdraft_up = true
                sim.backdraft_remains = 15
                sim.backdraft_stacks = 3
            end
        elseif key == "corruption" then
            sim.corruption_up = true
            sim.corruption_remains = 18
        elseif key == "life_tap" then
            sim.mana_pct = math.min(100, sim.mana_pct + 20)
            if sim.has_life_tap_glyph then
                sim.life_tap_glyph_up = true
                sim.life_tap_glyph_remains = 40
            end
        elseif key == "incinerate" or key == "shadow_bolt" or key == "chaos_bolt" or key == "soul_fire" then
            -- Consume a Backdraft stack
            if sim.backdraft_up and sim.backdraft_stacks > 0 then
                sim.backdraft_stacks = sim.backdraft_stacks - 1
                if sim.backdraft_stacks <= 0 then
                    sim.backdraft_up = false
                    sim.backdraft_remains = 0
                end
            end
        end
    end,
    getAdvanceTime = function(sim, action)
        local h = sim.haste or 1
        local backdraft_reduction = (sim.backdraft_up and sim.backdraft_stacks > 0) and 0.30 or 0
        if action == "incinerate" then
            local base = 2.0
            return math.max(sim.gcd, (base / h) * (1 - backdraft_reduction))
        end
        if action == "chaos_bolt" then
            local base = 2.5
            return math.max(sim.gcd, (base / h) * (1 - backdraft_reduction))
        end
        if action == "shadow_bolt" then
            local base = 2.5
            return math.max(sim.gcd, (base / h) * (1 - backdraft_reduction))
        end
        if action == "immolate" then
            local base = 2.0
            return math.max(sim.gcd, (base / h) * (1 - backdraft_reduction))
        end
        if action == "soul_fire" then
            local base = 4.0
            return math.max(sim.gcd, (base / h) * (1 - backdraft_reduction))
        end
        return sim.gcd  -- instants: corruption, life tap, conflagrate
    end,
}

local function GetDestructionRecommendations(addon)
    return DH:RunSimulation(state, destructionConfig)
end

-- ============================================================================
-- ROTATION MODES
-- ============================================================================

DH:RegisterMode("affliction", {
    name = "Affliction (DPS)",
    icon = select(3, GetSpellInfo(59164)) or "Interface\\Icons\\Spell_Shadow_Deathcoil",
    rotation = function(addon)
        return GetAfflictionRecommendations(addon)
    end,
})

DH:RegisterMode("demonology", {
    name = "Demonology (DPS)",
    icon = select(3, GetSpellInfo(47241)) or "Interface\\Icons\\Spell_Shadow_DemonForm",
    rotation = function(addon)
        return GetDemonologyRecommendations(addon)
    end,
})

DH:RegisterMode("destruction", {
    name = "Destruction (DPS)",
    icon = select(3, GetSpellInfo(17962)) or "Interface\\Icons\\Spell_Fire_Fireball",
    rotation = function(addon)
        return GetDestructionRecommendations(addon)
    end,
})
