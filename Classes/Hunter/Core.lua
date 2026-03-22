-- Classes/Hunter/Core.lua
-- Priority rotation logic for Hunter specs (3.3.5a compatible)
-- Uses core RunSimulation for CD-aware predictions

local DH = PriorityHelper
if not DH then return end

if select(2, UnitClass("player")) ~= "HUNTER" then
    return
end

local ns = DH.ns
local class = DH.Class
local state = DH.State

-- ============================================================================
-- BEAST MASTERY ROTATION
-- ============================================================================

local bmConfig = {
    gcdType = "spell",
    maxRecs = 3,
    allowDupes = true,
    cds = {
        kill_shot = "kill_shot",
        arcane_shot = "arcane_shot",
        aimed_shot = "aimed_shot",
        multi_shot = "multi_shot",
        kill_command = "kill_command",
        bestial_wrath = "bestial_wrath",
        rapid_fire = "rapid_fire",
    },
    baseCDs = {
        kill_shot = 15,
        arcane_shot = 6,
        aimed_shot = 10,
        multi_shot = 10,
        kill_command = 50,
        bestial_wrath = 120,
        rapid_fire = 300,
    },
    auras = {
        { up = "serpent_sting_up", remains = "serpent_sting_remains" },
    },
    initState = function(sim, s)
        -- DoTs
        sim.serpent_sting_up = s.debuff.serpent_sting.up
        sim.serpent_sting_remains = s.debuff.serpent_sting.remains

        -- Talents
        sim.has_bestial_wrath = s.talent.bestial_wrath.rank > 0
        sim.has_kill_command = true  -- all BM have this
        sim.has_aimed = s.talent.aimed_shot.rank > 0

        -- Glyph of Kill Shot
        sim.kill_shot_cd = (s.glyph.kill_shot and s.glyph.kill_shot.enabled) and 9 or 15
        -- Glyph of Bestial Wrath
        sim.bw_cd = (s.glyph.bestial_wrath and s.glyph.bestial_wrath.enabled) and 100 or 120
    end,
    getPriority = function(sim, recs)
        -- Kill Shot (execute phase)
        if sim.in_execute and sim:ready("kill_shot") then
            return "kill_shot"
        end

        -- Bestial Wrath (major CD)
        if sim.has_bestial_wrath and sim:ready("bestial_wrath") and not DH:IsSnoozed("bestial_wrath") then
            return "bestial_wrath"
        end

        -- Kill Command (pet CD)
        if sim:ready("kill_command") then
            return "kill_command"
        end

        -- Serpent Sting: maintain DoT
        if (not sim.serpent_sting_up or sim.serpent_sting_remains < 2) and sim.ttd > 6 then
            return "serpent_sting"
        end

        -- Multi-Shot
        if sim:ready("multi_shot") then
            return "multi_shot"
        end

        -- Aimed Shot
        if sim.has_aimed and sim:ready("aimed_shot") then
            return "aimed_shot"
        end

        -- Arcane Shot
        if sim:ready("arcane_shot") then
            return "arcane_shot"
        end

        -- Steady Shot filler
        return "steady_shot"
    end,
    onCast = function(sim, key)
        if key == "serpent_sting" then
            sim.serpent_sting_up = true
            sim.serpent_sting_remains = 15
        elseif key == "bestial_wrath" then
            sim.cd["bestial_wrath"] = sim.bw_cd
        elseif key == "kill_shot" then
            sim.cd["kill_shot"] = sim.kill_shot_cd
        end
    end,
    getAdvanceTime = function(sim, action)
        local h = sim.haste or 1
        if action == "steady_shot" then return math.max(sim.gcd, 2.0 / h) end
        return sim.gcd  -- all other shots are instant
    end,
}

local function GetBMRecommendations(addon)
    return DH:RunSimulation(state, bmConfig)
end

-- ============================================================================
-- MARKSMANSHIP ROTATION
-- ============================================================================

local mmConfig = {
    gcdType = "spell",
    maxRecs = 3,
    allowDupes = true,
    cds = {
        kill_shot = "kill_shot",
        chimera_shot = "chimera_shot",
        aimed_shot = "aimed_shot",
        arcane_shot = "arcane_shot",
        multi_shot = "multi_shot",
        rapid_fire = "rapid_fire",
        silencing_shot = "silencing_shot",
    },
    baseCDs = {
        kill_shot = 15,
        chimera_shot = 10,
        aimed_shot = 10,
        arcane_shot = 6,
        multi_shot = 10,
        rapid_fire = 300,
        silencing_shot = 20,
    },
    auras = {
        { up = "serpent_sting_up", remains = "serpent_sting_remains" },
    },
    initState = function(sim, s)
        -- DoTs
        sim.serpent_sting_up = s.debuff.serpent_sting.up
        sim.serpent_sting_remains = s.debuff.serpent_sting.remains

        -- Procs
        sim.iss_up = s.buff.improved_steady_shot.up  -- +15% damage buff

        -- Talents
        sim.has_chimera = s.talent.chimera_shot.rank > 0
        sim.has_aimed = s.talent.aimed_shot.rank > 0
        sim.has_silencing = s.talent.silencing_shot.rank > 0

        -- Glyph of Chimera Shot (-1s CD)
        sim.chimera_cd = (s.glyph.chimera_shot and s.glyph.chimera_shot.enabled) and 9 or 10
        -- Glyph of Kill Shot
        sim.kill_shot_cd = (s.glyph.kill_shot and s.glyph.kill_shot.enabled) and 9 or 15
    end,
    getPriority = function(sim, recs)
        -- Kill Shot (execute phase)
        if sim.in_execute and sim:ready("kill_shot") then
            return "kill_shot"
        end

        -- Serpent Sting: must be up for Chimera Shot synergy
        if (not sim.serpent_sting_up or sim.serpent_sting_remains < 2) and sim.ttd > 6 then
            return "serpent_sting"
        end

        -- Chimera Shot on CD (refreshes Serpent Sting + bonus damage)
        if sim.has_chimera and sim:ready("chimera_shot") then
            return "chimera_shot"
        end

        -- Aimed Shot
        if sim.has_aimed and sim:ready("aimed_shot") then
            return "aimed_shot"
        end

        -- Multi-Shot
        if sim:ready("multi_shot") then
            return "multi_shot"
        end

        -- Arcane Shot (when others on CD)
        if sim:ready("arcane_shot") then
            return "arcane_shot"
        end

        -- Steady Shot filler (also procs Improved Steady Shot)
        return "steady_shot"
    end,
    onCast = function(sim, key)
        if key == "serpent_sting" then
            sim.serpent_sting_up = true
            sim.serpent_sting_remains = 15
        elseif key == "chimera_shot" then
            -- Chimera refreshes Serpent Sting
            if sim.serpent_sting_up then
                sim.serpent_sting_remains = 15
            end
            sim.cd["chimera_shot"] = sim.chimera_cd
        elseif key == "kill_shot" then
            sim.cd["kill_shot"] = sim.kill_shot_cd
        end
    end,
    getAdvanceTime = function(sim, action)
        local h = sim.haste or 1
        if action == "steady_shot" then return math.max(sim.gcd, 2.0 / h) end
        return sim.gcd
    end,
}

local function GetMMRecommendations(addon)
    return DH:RunSimulation(state, mmConfig)
end

-- ============================================================================
-- SURVIVAL ROTATION
-- ============================================================================

local svConfig = {
    gcdType = "spell",
    maxRecs = 3,
    allowDupes = true,
    cds = {
        kill_shot = "kill_shot",
        explosive_shot = "explosive_shot",
        black_arrow = "black_arrow",
        arcane_shot = "arcane_shot",
        aimed_shot = "aimed_shot",
        multi_shot = "multi_shot",
        rapid_fire = "rapid_fire",
    },
    baseCDs = {
        kill_shot = 15,
        explosive_shot = 6,
        black_arrow = 30,
        arcane_shot = 6,
        aimed_shot = 10,
        multi_shot = 10,
        rapid_fire = 300,
    },
    auras = {
        { up = "serpent_sting_up", remains = "serpent_sting_remains" },
        { up = "black_arrow_up", remains = "black_arrow_remains" },
    },
    initState = function(sim, s)
        -- DoTs
        sim.serpent_sting_up = s.debuff.serpent_sting.up
        sim.serpent_sting_remains = s.debuff.serpent_sting.remains
        sim.black_arrow_up = s.debuff.black_arrow.up
        sim.black_arrow_remains = s.debuff.black_arrow.remains

        -- Procs
        sim.lock_and_load = s.buff.lock_and_load.up
        sim.lnl_stacks = s.buff.lock_and_load.stacks or 0

        -- Talents
        sim.has_explosive = s.talent.explosive_shot.rank > 0
        sim.has_black_arrow = s.talent.black_arrow.rank > 0
        sim.has_aimed = s.talent.aimed_shot.rank > 0
        sim.has_lock_and_load = s.talent.lock_and_load.rank > 0

        -- Glyph of Kill Shot
        sim.kill_shot_cd = (s.glyph.kill_shot and s.glyph.kill_shot.enabled) and 9 or 15
        -- Resourcefulness reduces Black Arrow CD
        local res_rank = s.talent.resourcefulness.rank or 0
        sim.ba_cd = 30 - (res_rank * 2)
    end,
    getPriority = function(sim, recs)
        -- Kill Shot (execute phase)
        if sim.in_execute and sim:ready("kill_shot") then
            return "kill_shot"
        end

        -- Lock and Load proc: free Explosive Shot (spam it)
        if sim.has_lock_and_load and sim.lock_and_load and sim.lnl_stacks > 0 then
            return "explosive_shot"
        end

        -- Serpent Sting: maintain DoT
        if (not sim.serpent_sting_up or sim.serpent_sting_remains < 2) and sim.ttd > 6 then
            return "serpent_sting"
        end

        -- Black Arrow on CD (triggers Lock and Load)
        if sim.has_black_arrow and sim:ready("black_arrow") and sim.ttd > 10 then
            return "black_arrow"
        end

        -- Explosive Shot on CD
        if sim.has_explosive and sim:ready("explosive_shot") then
            return "explosive_shot"
        end

        -- Multi-Shot
        if sim:ready("multi_shot") then
            return "multi_shot"
        end

        -- Aimed Shot
        if sim.has_aimed and sim:ready("aimed_shot") then
            return "aimed_shot"
        end

        -- Steady Shot filler
        return "steady_shot"
    end,
    onCast = function(sim, key)
        if key == "serpent_sting" then
            sim.serpent_sting_up = true
            sim.serpent_sting_remains = 15
        elseif key == "black_arrow" then
            sim.black_arrow_up = true
            sim.black_arrow_remains = 15
            sim.cd["black_arrow"] = sim.ba_cd
        elseif key == "explosive_shot" then
            if sim.lock_and_load and sim.lnl_stacks > 0 then
                sim.lnl_stacks = sim.lnl_stacks - 1
                if sim.lnl_stacks <= 0 then
                    sim.lock_and_load = false
                end
            end
            -- Explosive Shot and Arcane Shot share CD
            sim.cd["arcane_shot"] = 6
        elseif key == "arcane_shot" then
            -- Shares CD with Explosive Shot
            sim.cd["explosive_shot"] = 6
        elseif key == "kill_shot" then
            sim.cd["kill_shot"] = sim.kill_shot_cd
        end
    end,
    getAdvanceTime = function(sim, action)
        local h = sim.haste or 1
        if action == "steady_shot" then return math.max(sim.gcd, 2.0 / h) end
        return sim.gcd
    end,
}

local function GetSurvivalRecommendations(addon)
    return DH:RunSimulation(state, svConfig)
end

-- ============================================================================
-- ROTATION MODES
-- ============================================================================

DH:RegisterMode("beast_mastery", {
    name = "Beast Mastery (DPS)",
    icon = select(3, GetSpellInfo(19574)) or "Interface\\Icons\\Ability_Druid_FerociousBite",
    rotation = function(addon)
        return GetBMRecommendations(addon)
    end,
})

DH:RegisterMode("marksmanship", {
    name = "Marksmanship (DPS)",
    icon = select(3, GetSpellInfo(53209)) or "Interface\\Icons\\Ability_Hunter_ChimeraShot2",
    rotation = function(addon)
        return GetMMRecommendations(addon)
    end,
})

DH:RegisterMode("survival", {
    name = "Survival (DPS)",
    icon = select(3, GetSpellInfo(60053)) or "Interface\\Icons\\Ability_Hunter_ExplosiveShot",
    rotation = function(addon)
        return GetSurvivalRecommendations(addon)
    end,
})
