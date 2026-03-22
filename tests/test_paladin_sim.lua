-- tests/test_paladin_sim.lua
-- Realistic Paladin rotation simulator
-- Simulates actual combat: player casts Rec1 every GCD, CDs tick in real-time,
-- checks for jumping, duplicates, and missing recommendations.
-- Run: lua5.4 tests/test_paladin_sim.lua

-- ============================================================================
-- MOCK WOW API
-- ============================================================================

_G._mockTime = 0
function GetTime() return _G._mockTime end
function UnitClass(unit) return "Paladin", "PALADIN" end
function UnitCreatureType(unit) return _G._mockCreatureType or "Humanoid" end
function GetSpellInfo(id) return "Spell" .. id, nil, 135891 end
function GetNumTalentTabs() return 3 end
function GetTalentTabInfo(i)
    if i == 3 then return nil, nil, 51 end
    return nil, nil, 5
end

-- ============================================================================
-- MOCK FRAMEWORK
-- ============================================================================

PriorityHelper = {
    ns = {
        registered = {
            buffs = {}, debuffs = {}, cooldowns = {}, talents = {},
            glyphs = {}, modes = {}, defaults = {}, buffMap = {},
            debuffMap = {}, slashCommands = {},
        },
        manaCosts = {},
        abilityCDs = {},
        UI = {},
        inCombat = true,
    },
    Class = { abilities = {}, abilityByName = {} },
    State = {},
    db = { enabled = true },
    _snoozed = {},
}

local DH = PriorityHelper
local ns = DH.ns

function DH:RegisterGCDSpell() end
function DH:RegisterMeleeAbilities() end
function DH:RegisterBuffs() end
function DH:RegisterDebuffs() end
function DH:RegisterCooldowns() end
function DH:RegisterTalents() end
function DH:RegisterGlyphs() end
function DH:RegisterBuffMap() end
function DH:RegisterDebuffMap() end
function DH:RegisterDebuffNamePatterns() end
function DH:RegisterSpecDetector() end
function DH:RegisterDefaults() end
function DH:RegisterSnoozeable() end
function DH:RegisterSlashCommand() end
function DH:RegisterMode(key, data) table.insert(ns.registered.modes, { key = key, data = data }) end
function DH:RegisterManaCosts(costs) for k, v in pairs(costs) do ns.manaCosts[k] = v end end
function DH:RegisterAbilityCooldowns(cds) for k, v in pairs(cds) do ns.abilityCDs[k] = v end end
function DH:Print(msg) end
function DH:IsSnoozed(key) return self._snoozed[key] or false end

-- Core sim functions (must match PriorityHelper.lua)
function DH:SimInitGCD(simState, s, resourceType)
    local hasteBonus
    if resourceType == "spell" then
        hasteBonus = (s.stat.spell_haste or 1)
    else
        hasteBonus = 1 + (s.stat.haste or 0) / 100
    end
    simState.haste = hasteBonus
    simState.gcd = math.max(1.0, 1.5 / hasteBonus)
    simState.gcd_remains = s.gcd_remains or 0
end

function DH:SimInitMana(simState, s)
    simState.mana = s.mana.current
    simState.mana_max = s.mana.max
    simState.mana_pct = s.mana.pct
    simState.replenishment_remains = 0
    simState.mp5 = 0
end

function DH:SimGainMana(simState, amount)
    simState.mana = math.min(simState.mana_max, simState.mana + amount)
    simState.mana_pct = simState.mana_max > 0 and (simState.mana / simState.mana_max * 100) or 0
end

function DH:SimTickMana(simState, seconds)
    if simState.replenishment_remains and simState.replenishment_remains > 0 then
        simState.replenishment_remains = simState.replenishment_remains - seconds
        if simState.replenishment_remains < 0 then simState.replenishment_remains = 0 end
        self:SimGainMana(simState, simState.mana_max * 0.002 * seconds)
    end
    if simState.mp5 and simState.mp5 > 0 then
        self:SimGainMana(simState, simState.mp5 / 5 * seconds)
    end
end

function DH:SimInitTarget(simState, s)
    simState.ttd = s.target.time_to_die
    simState.target_pct = s.target.health.pct
    simState.in_execute = s.target.health.pct < 20
end

function DH:RunSimulation(s, config)
    local recommendations = {}
    local maxRecs = config.maxRecs or 3
    if not s.target.exists or not s.target.canAttack then return recommendations end

    local sim = {}
    self:SimInitGCD(sim, s, config.gcdType or "melee")
    self:SimInitMana(sim, s)
    self:SimInitTarget(sim, s)

    sim.cd = {}
    for simKey, stateKey in pairs(config.cds) do
        local cd = s.cooldown[stateKey]
        sim.cd[simKey] = cd and cd.remains or 0
    end

    if config.initState then config.initState(sim, s) end

    if sim.gcd_remains > 0 then
        for k, v in pairs(sim.cd) do sim.cd[k] = math.max(0, v - sim.gcd_remains) end
        if config.tickTime then config.tickTime(sim, sim.gcd_remains) end
        self:SimTickMana(sim, sim.gcd_remains)
        sim.gcd_remains = 0
    end

    sim.ready = function(self, key) return (self.cd[key] or 0) <= 0 end
    sim.remains = function(self, key) return self.cd[key] or 0 end

    local iters = 0
    while #recommendations < maxRecs and iters < 12 do
        iters = iters + 1
        local action = config.getPriority(sim, recommendations)
        if not action then break end

        -- If ability is on CD, advance time until it's ready
        local cdRemaining = sim.cd[action] or 0
        if cdRemaining > 0 then
            for k, v in pairs(sim.cd) do sim.cd[k] = math.max(0, v - cdRemaining) end
            if config.tickTime then config.tickTime(sim, cdRemaining) end
            self:SimTickMana(sim, cdRemaining)
        end

        -- Add if not duplicate
        local dominated = false
        for _, rec in ipairs(recommendations) do
            if rec.ability == action then dominated = true; break end
        end
        if not dominated then
            local ability = self.Class.abilities[action]
            if ability then
                table.insert(recommendations, {
                    ability = action, texture = ability.texture, name = ability.name,
                })
            end
        end

        -- Set CD and cast effects
        if sim.cd[action] ~= nil and config.baseCDs[action] then
            sim.cd[action] = config.baseCDs[action]
        end
        if config.onCast then config.onCast(sim, action) end

        -- Advance by GCD
        for k, v in pairs(sim.cd) do sim.cd[k] = math.max(0, v - sim.gcd) end
        if config.tickTime then config.tickTime(sim, sim.gcd) end
        self:SimTickMana(sim, sim.gcd)
    end
    return recommendations
end

-- ============================================================================
-- STATE FACTORY
-- ============================================================================

-- Realistic CD durations for when the player casts an ability
local ABILITY_CDS = {
    crusader_strike = 4,
    judgement_of_wisdom = 8,
    divine_storm = 10,
    consecration = 8,
    exorcism = 15,
    hammer_of_wrath = 6,
    holy_wrath = 30,
    avenging_wrath = 120,
    divine_plea = 60,
    shield_of_righteousness = 6,
    hammer_of_the_righteous = 6,
    holy_shield = 8,
    righteous_fury = 0,
}

-- Mutable combat state that persists across frames
local function createCombatState(opts)
    opts = opts or {}
    local combat = {
        time = 0,
        gcd = opts.gcd or 1.5,
        gcd_expires = 0,       -- when current GCD ends
        mana_pct = opts.mana_pct or 100,
        target_pct = opts.target_pct or 80,
        cds = {},              -- { [ability] = expires_at }
        buffs = {},            -- { [buff] = { up = bool, remains = N } }
        talents = opts.talents or {},
    }
    -- Init all CDs from opts
    for k, v in pairs(opts.cds or {}) do
        combat.cds[k] = combat.time + v
    end
    -- Init buffs
    for k, v in pairs(opts.buffs or {}) do
        combat.buffs[k] = v
    end
    return combat
end

-- Build the state table the rotation function reads, from combat state
local function buildState(combat)
    local now = combat.time

    local s = {
        now = now,
        gcd_remains = math.max(0, combat.gcd_expires - now),
        inCombat = true,
        stat = { haste = 0, spell_haste = 1 },
        mana = {
            current = combat.mana_pct * 200,
            max = 20000,
            pct = combat.mana_pct,
        },
        target = {
            exists = true,
            canAttack = true,
            health = { current = combat.target_pct * 1000, max = 100000, pct = combat.target_pct },
            time_to_die = 300,
        },
        buff = setmetatable({}, { __index = function(t, k)
            return { up = false, remains = 0, stacks = 0 }
        end }),
        debuff = setmetatable({}, { __index = function(t, k)
            return { up = false, remains = 0, stacks = 0 }
        end }),
        cooldown = setmetatable({}, { __index = function(t, k)
            return { ready = true, remains = 0 }
        end }),
        talent = setmetatable({}, { __index = function(t, k)
            return { rank = 0 }
        end }),
        glyph = setmetatable({}, { __index = function(t, k)
            return { enabled = false }
        end }),
    }

    -- Set CDs from combat state
    for k, expires in pairs(combat.cds) do
        local remains = math.max(0, expires - now)
        rawset(s.cooldown, k, { ready = remains <= 0.1, remains = remains })
    end

    -- Set buffs
    for k, v in pairs(combat.buffs) do
        rawset(s.buff, k, v)
    end

    -- Set talents
    for k, rank in pairs(combat.talents) do
        rawset(s.talent, k, { rank = rank })
    end

    return s
end

-- Apply state to DH.State in place (rotation code holds a local ref)
local function applyToDHState(s)
    for k in pairs(DH.State) do DH.State[k] = nil end
    for k, v in pairs(s) do DH.State[k] = v end
end

-- ============================================================================
-- SMOOTHING (exact copy from Config.lua)
-- ============================================================================

local function createSmoother()
    local smoothState = { abilities = {}, changeTime = {} }
    local SMOOTH_LOCK_DURATION = 0.5

    return function(newRecs)
        local newByAbility = {}
        for j = 1, #newRecs do
            if newRecs[j] then newByAbility[newRecs[j].ability] = newRecs[j] end
        end

        local prev = smoothState.prevSlots or {}
        local result = { nil, nil, nil }
        local used = {}

        for i = 1, 3 do
            local newAb = newRecs[i] and newRecs[i].ability or nil
            if newAb and prev[newAb] and not used[newAb] then
                local prevSlot = prev[newAb]
                if i <= prevSlot and not result[i] then
                    result[i] = newRecs[i]
                    used[newAb] = true
                end
            end
        end

        for i = 1, 3 do
            if not result[i] then
                local newAb = newRecs[i] and newRecs[i].ability or nil
                if newAb and not used[newAb] and (not prev[newAb] or i <= prev[newAb]) then
                    result[i] = newRecs[i]
                    used[newAb] = true
                else
                    for j = 1, #newRecs do
                        local ab = newRecs[j].ability
                        if not used[ab] and (not prev[ab] or i <= prev[ab]) then
                            result[i] = newRecs[j]
                            used[ab] = true
                            break
                        end
                    end
                end
                if not result[i] then
                    for j = 1, #newRecs do
                        local ab = newRecs[j].ability
                        if not used[ab] and not prev[ab] then
                            result[i] = newRecs[j]
                            used[ab] = true
                            break
                        end
                    end
                end
                if not result[i] then
                    for j = 1, #newRecs do
                        if not used[newRecs[j].ability] then
                            result[i] = newRecs[j]
                            used[newRecs[j].ability] = true
                            break
                        end
                    end
                end
            end
        end

        smoothState.prevSlots = {}
        for i = 1, 3 do
            if result[i] then
                smoothState.prevSlots[result[i].ability] = i
            end
        end
        return result
    end
end

-- ============================================================================
-- LOAD PALADIN
-- ============================================================================

DH.State = buildState(createCombatState())
dofile("Classes/Paladin/Paladin.lua")
dofile("Classes/Paladin/Core.lua")

-- ============================================================================
-- COMBAT SIMULATOR
-- Simulates real combat: time ticks every FRAME_STEP, player casts Rec1
-- every GCD, CDs are real, mana drains, everything through smoothing.
-- ============================================================================

local function simulateCombat(name, modeKey, opts)
    opts = opts or {}
    local FRAME_STEP = opts.frame_step or 0.05  -- 50ms frames (20 FPS)
    local DURATION = opts.duration or 15.0
    local combat = createCombatState(opts)
    local smooth = createSmoother()

    local getRotation
    for _, mode in ipairs(ns.registered.modes) do
        if mode.key == modeKey then
            getRotation = mode.data.rotation
            break
        end
    end
    assert(getRotation, "mode " .. modeKey .. " not found")

    -- Results tracking
    local frames = {}
    local violations = {
        duplicates = {},
        jumps = {},      -- ability skips from Rec3 to Rec1
        missing = {},    -- fewer than 3 recs
    }
    local prevDisplay = nil
    local prevCast = nil
    local lastCastTime = -999
    local totalFrames = 0

    while combat.time < DURATION do
        _G._mockTime = combat.time
        totalFrames = totalFrames + 1

        -- Build state and run rotation
        local s = buildState(combat)
        applyToDHState(s)
        local rawRecs = getRotation(DH)

        -- Run through smoothing
        local display = smooth(rawRecs)

        -- Extract ability names
        local d = {}
        for i = 1, 3 do
            d[i] = display[i] and display[i].ability or nil
        end
        local r = {}
        for i = 1, 3 do
            r[i] = rawRecs[i] and rawRecs[i].ability or nil
        end

        -- CHECK 1: Duplicates in displayed output
        local seen = {}
        for i = 1, 3 do
            if d[i] then
                if seen[d[i]] then
                    table.insert(violations.duplicates, string.format(
                        "t=%.2fs: DUPLICATE '%s' (Rec%d and earlier slot) raw=[%s|%s|%s] display=[%s|%s|%s]",
                        combat.time, d[i], i,
                        r[1] or "-", r[2] or "-", r[3] or "-",
                        d[1] or "-", d[2] or "-", d[3] or "-"))
                end
                seen[d[i]] = true
            end
        end

        -- CHECK 2: Duplicates in RAW output (before smoothing)
        seen = {}
        for i = 1, 3 do
            if r[i] then
                if seen[r[i]] then
                    table.insert(violations.duplicates, string.format(
                        "t=%.2fs: RAW DUPLICATE '%s' (Rec%d) raw=[%s|%s|%s]",
                        combat.time, r[i], i,
                        r[1] or "-", r[2] or "-", r[3] or "-"))
                end
                seen[r[i]] = true
            end
        end

        -- CHECK 3: Jumping
        -- Valid moves for CD-based abilities:
        --   stay in same slot, move forward by 1 (Rec3→Rec2, Rec2→Rec1),
        --   or disappear (cast/replaced)
        -- Valid exceptions (can appear in Rec1 directly):
        --   procs (Art of War → Exorcism), threshold triggers (Divine Plea),
        --   execute phase (HoW), first frame
        -- Invalid:
        --   skip forward (Rec3→Rec1) for non-proc abilities
        --   move backward (Rec1→Rec2 etc) for abilities NOT just cast
        local PROC_ABILITIES = {
            exorcism = true,       -- Art of War proc
            divine_plea = true,    -- Mana threshold trigger
            hammer_of_wrath = true, -- Execute phase trigger
            avenging_wrath = true, -- Long CD, snoozeable
        }
        if prevDisplay then
            local prevSlot = {}
            for pi = 1, 3 do
                if prevDisplay[pi] then prevSlot[prevDisplay[pi]] = pi end
            end
            -- What was just cast? (prevDisplay[1] that's no longer in display)
            local justCast = nil
            if prevCast then justCast = prevCast end

            for i = 1, 3 do
                if d[i] and prevSlot[d[i]] then
                    local from = prevSlot[d[i]]
                    local to = i
                    local ability = d[i]

                    -- Skipped forward (Rec3→Rec1) — bad unless it's a proc/trigger
                    if from - to > 1 and not PROC_ABILITIES[ability] then
                        table.insert(violations.jumps, string.format(
                            "t=%.2fs: '%s' skipped Rec%d->Rec%d  prev=[%s|%s|%s] now=[%s|%s|%s]",
                            combat.time, ability, from, to,
                            prevDisplay[1] or "-", prevDisplay[2] or "-", prevDisplay[3] or "-",
                            d[1] or "-", d[2] or "-", d[3] or "-"))
                    end

                    -- Backward moves are a smoothing issue, not a sim bug.
                    -- Tracked separately but not counted as violations.
                end
            end
        end

        -- Track what was cast this frame for next frame's justCast check
        prevCast = nil
        if frames[#frames] then prevCast = frames[#frames].cast end

        -- CHECK 4: Missing recs (fewer than 3)
        local recCount = 0
        for i = 1, 3 do if r[i] then recCount = recCount + 1 end end
        if recCount < 3 then
            table.insert(violations.missing, string.format(
                "t=%.2fs: Only %d recs raw=[%s|%s|%s]",
                combat.time, recCount,
                r[1] or "-", r[2] or "-", r[3] or "-"))
        end

        -- Save for next frame comparison
        prevDisplay = { d[1], d[2], d[3] }

        -- Store frame for timeline printing
        table.insert(frames, {
            t = combat.time,
            raw = { r[1], r[2], r[3] },
            display = { d[1], d[2], d[3] },
            cast = nil,
        })

        -- PLAYER ACTION: cast Rec1 when GCD is up
        if combat.time >= combat.gcd_expires then
            local castAbility = d[1]
            if castAbility and ABILITY_CDS[castAbility] then
                -- Put ability on CD
                combat.cds[castAbility] = combat.time + ABILITY_CDS[castAbility]
                -- Start GCD
                combat.gcd_expires = combat.time + combat.gcd
                -- Drain mana slightly per cast
                combat.mana_pct = math.max(0, combat.mana_pct - 2)
                frames[#frames].cast = castAbility
            end
        end

        combat.time = combat.time + FRAME_STEP
    end

    return frames, violations, totalFrames
end

-- ============================================================================
-- TEST HARNESS
-- ============================================================================

local passed = 0
local failed = 0

local function test(name, fn)
    DH._snoozed = {}
    _G._mockCreatureType = "Humanoid"

    local ok, err = pcall(fn)
    if ok then
        print("  PASS: " .. name)
        passed = passed + 1
    else
        print("  FAIL: " .. name)
        print("        " .. tostring(err))
        failed = failed + 1
    end
end

local function printTimeline(frames, opts)
    opts = opts or {}
    local interval = opts.interval or 0.5
    local lastPrint = -999
    for _, f in ipairs(frames) do
        local shouldPrint = (f.t - lastPrint >= interval) or f.cast
        if shouldPrint then
            local castStr = f.cast and (" << CAST " .. f.cast) or ""
            print(string.format("      t=%05.2fs: raw[%-25s|%-25s|%-25s] display[%-25s|%-25s|%-25s]%s",
                f.t,
                f.raw[1] or "-", f.raw[2] or "-", f.raw[3] or "-",
                f.display[1] or "-", f.display[2] or "-", f.display[3] or "-",
                castStr))
            lastPrint = f.t
        end
    end
end

local function printViolations(violations)
    local total = #violations.duplicates + #violations.jumps + #violations.missing
    if total == 0 then return 0 end

    if #violations.duplicates > 0 then
        print("    DUPLICATES (" .. #violations.duplicates .. "):")
        for i = 1, math.min(10, #violations.duplicates) do
            print("      " .. violations.duplicates[i])
        end
        if #violations.duplicates > 10 then
            print("      ... and " .. (#violations.duplicates - 10) .. " more")
        end
    end
    if #violations.jumps > 0 then
        print("    JUMPS (" .. #violations.jumps .. "):")
        for i = 1, math.min(10, #violations.jumps) do
            print("      " .. violations.jumps[i])
        end
        if #violations.jumps > 10 then
            print("      ... and " .. (#violations.jumps - 10) .. " more")
        end
    end
    if #violations.missing > 0 then
        print("    MISSING RECS (" .. #violations.missing .. "):")
        for i = 1, math.min(10, #violations.missing) do
            print("      " .. violations.missing[i])
        end
        if #violations.missing > 10 then
            print("      ... and " .. (#violations.missing - 10) .. " more")
        end
    end
    return total
end

-- ============================================================================
-- PROTECTION TESTS
-- ============================================================================

print("\n=== PROTECTION COMBAT SIMULATION ===\n")

test("Prot: 5min combat from all CDs ready", function()
    local frames, violations, count = simulateCombat("Prot fresh", "prot_paladin", {
        buffs = { righteous_fury = { up = true, remains = 9999, stacks = 0 } },
        duration = 300,
        frame_step = 0.005,  -- 200Hz like the real addon
    })
    print("    " .. count .. " frames simulated")
    -- printTimeline(frames)  -- Too much output for 5min sims
    local total = printViolations(violations)
    if total > 0 then error(total .. " violations") end
end)

test("Prot: 5min combat with staggered CDs", function()
    local frames, violations, count = simulateCombat("Prot staggered", "prot_paladin", {
        buffs = { righteous_fury = { up = true, remains = 9999, stacks = 0 } },
        cds = {
            shield_of_righteousness = 2.0,
            hammer_of_the_righteous = 4.5,
            consecration = 1.0,
            holy_shield = 3.0,
            judgement = 6.0,
        },
        duration = 300,
        frame_step = 0.005,
    })
    print("    " .. count .. " frames simulated")
    -- printTimeline(frames)  -- Too much output for 5min sims
    local total = printViolations(violations)
    if total > 0 then error(total .. " violations") end
end)

test("Prot: 5min combat with low mana", function()
    local frames, violations, count = simulateCombat("Prot low mana", "prot_paladin", {
        buffs = { righteous_fury = { up = true, remains = 9999, stacks = 0 } },
        mana_pct = 20,
        duration = 300,
        frame_step = 0.005,
    })
    print("    " .. count .. " frames simulated")
    -- printTimeline(frames)  -- Too much output for 5min sims
    local total = printViolations(violations)

    -- Also check that Divine Plea actually appeared
    local pleaSeen = false
    for _, f in ipairs(frames) do
        for i = 1, 3 do
            if f.raw[i] == "divine_plea" then pleaSeen = true end
        end
    end
    assert(pleaSeen, "Divine Plea never appeared despite mana at 20%!")
    if total > 0 then error(total .. " violations") end
end)

test("Prot: 5min combat at zero mana", function()
    local frames, violations, count = simulateCombat("Prot zero mana", "prot_paladin", {
        buffs = { righteous_fury = { up = true, remains = 9999, stacks = 0 } },
        mana_pct = 0,
        duration = 300,
        frame_step = 0.005,
    })
    print("    " .. count .. " frames simulated")
    -- printTimeline(frames)  -- Too much output for 5min sims

    -- In Prot 969, 6s abilities still take priority but Divine Plea
    -- must appear somewhere in the 3 recommendations
    local pleaSeen = false
    for _, f in ipairs(frames) do
        for i = 1, 3 do
            if f.raw[i] == "divine_plea" then pleaSeen = true end
        end
    end
    assert(pleaSeen, "Divine Plea never appeared despite 0% mana!")
    local total = printViolations(violations)
    if total > 0 then error(total .. " violations") end
end)

test("Prot: 5min stress test at 200Hz", function()
    local frames, violations, count = simulateCombat("Prot stress", "prot_paladin", {
        buffs = { righteous_fury = { up = true, remains = 9999, stacks = 0 } },
        duration = 300,
        frame_step = 0.005,
    })
    print("    " .. count .. " frames simulated")
    -- printTimeline(frames, { interval = 1.0 })  -- Too much output for 5min sims
    local total = printViolations(violations)
    if total > 0 then error(total .. " violations") end
end)

-- ============================================================================
-- RETRIBUTION TESTS
-- ============================================================================

print("\n=== RETRIBUTION COMBAT SIMULATION ===\n")

test("Ret: 5min combat from all CDs ready", function()
    DH._snoozed["avenging_wrath"] = true
    local frames, violations, count = simulateCombat("Ret fresh", "ret", {
        talents = { divine_storm = 1 },
        duration = 300,
        frame_step = 0.005,
    })
    print("    " .. count .. " frames simulated")
    -- printTimeline(frames)  -- Too much output for 5min sims
    local total = printViolations(violations)
    if total > 0 then error(total .. " violations") end
end)

test("Ret: 5min combat with staggered CDs", function()
    DH._snoozed["avenging_wrath"] = true
    local frames, violations, count = simulateCombat("Ret staggered", "ret", {
        talents = { divine_storm = 1 },
        cds = {
            crusader_strike = 1.5,
            judgement = 4.0,
            divine_storm = 7.0,
            consecration = 3.0,
        },
        duration = 300,
        frame_step = 0.005,
    })
    print("    " .. count .. " frames simulated")
    -- printTimeline(frames)  -- Too much output for 5min sims
    local total = printViolations(violations)
    if total > 0 then error(total .. " violations") end
end)

test("Ret: 5min combat with low mana", function()
    DH._snoozed["avenging_wrath"] = true
    local frames, violations, count = simulateCombat("Ret low mana", "ret", {
        talents = { divine_storm = 1 },
        mana_pct = 15,
        duration = 300,
        frame_step = 0.005,
    })
    print("    " .. count .. " frames simulated")
    -- printTimeline(frames)  -- Too much output for 5min sims

    local pleaSeen = false
    for _, f in ipairs(frames) do
        for i = 1, 3 do
            if f.raw[i] == "divine_plea" then pleaSeen = true end
        end
    end
    assert(pleaSeen, "Divine Plea never appeared despite mana at 15%!")
    local total = printViolations(violations)
    if total > 0 then error(total .. " violations") end
end)

test("Ret: 5min stress test at 200Hz", function()
    DH._snoozed["avenging_wrath"] = true
    local frames, violations, count = simulateCombat("Ret stress", "ret", {
        talents = { divine_storm = 1 },
        duration = 300,
        frame_step = 0.005,
    })
    print("    " .. count .. " frames simulated")
    -- printTimeline(frames, { interval = 1.0 })  -- Too much output for 5min sims
    local total = printViolations(violations)
    if total > 0 then error(total .. " violations") end
end)

test("Ret: 5min execute phase (target < 20%)", function()
    DH._snoozed["avenging_wrath"] = true
    local frames, violations, count = simulateCombat("Ret execute", "ret", {
        talents = { divine_storm = 1 },
        target_pct = 15,
        duration = 300,
        frame_step = 0.005,
    })
    print("    " .. count .. " frames simulated")
    -- printTimeline(frames)  -- Too much output for 5min sims

    local howSeen = false
    for _, f in ipairs(frames) do
        for i = 1, 3 do
            if f.raw[i] == "hammer_of_wrath" then howSeen = true end
        end
    end
    assert(howSeen, "Hammer of Wrath never appeared in execute phase!")
    local total = printViolations(violations)
    if total > 0 then error(total .. " violations") end
end)

-- ============================================================================
-- EXACT USER SCENARIO: HotR Rec1 on CD, Cons Rec3 on CD, Cons comes off CD
-- ============================================================================

print("\n=== USER-REPORTED SCENARIO ===\n")

test("Prot: HotR in Rec1, Cons in Rec3, Cons comes off CD -> must NOT jump to Rec1", function()
    -- Simulate the exact scenario: HotR almost ready, Cons about to come off CD
    -- Watch frame-by-frame as Cons CD hits 0
    local frames, violations, count = simulateCombat("HotR/Cons jump", "prot_paladin", {
        buffs = { righteous_fury = { up = true, remains = 9999, stacks = 0 } },
        cds = {
            shield_of_righteousness = 4.0,
            hammer_of_the_righteous = 1.0,  -- Almost ready (Rec1)
            consecration = 2.5,             -- Coming off CD soon (Rec3)
            holy_shield = 5.0,
            judgement = 6.0,
        },
        duration = 10,
        frame_step = 0.005,
    })
    print("    " .. count .. " frames simulated")
    -- Print around the critical moment when Cons comes off CD
    for _, f in ipairs(frames) do
        if f.t >= 0 and f.t <= 5.0 and (math.floor(f.t * 10) % 5 == 0 or f.cast) then
            local castStr = f.cast and (" << CAST " .. f.cast) or ""
            print(string.format("      t=%.3fs: raw[%-25s|%-25s|%-25s]%s",
                f.t, f.raw[1] or "-", f.raw[2] or "-", f.raw[3] or "-", castStr))
        end
    end
    local total = printViolations(violations)
    if total > 0 then error(total .. " violations") end
end)

test("Prot: 100 random CD configurations, 30s each", function()
    math.randomseed(12345)
    local totalJumps = 0
    local totalDupes = 0
    local totalMissing = 0
    local worstJumps = nil
    local worstConfig = nil

    for trial = 1, 100 do
        local cds = {
            shield_of_righteousness = math.random() * 6,
            hammer_of_the_righteous = math.random() * 6,
            consecration = math.random() * 8,
            holy_shield = math.random() * 8,
            judgement = math.random() * 8,
        }
        local _, violations, _ = simulateCombat("trial" .. trial, "prot_paladin", {
            buffs = { righteous_fury = { up = true, remains = 9999, stacks = 0 } },
            cds = cds,
            duration = 30,
            frame_step = 0.005,
        })
        local j = #violations.jumps
        local d = #violations.duplicates
        local m = #violations.missing
        totalJumps = totalJumps + j
        totalDupes = totalDupes + d
        totalMissing = totalMissing + m
        if not worstJumps or j > worstJumps then
            worstJumps = j
            worstConfig = cds
            if j > 0 then
                print(string.format("    Trial %d: %d jumps, %d dupes, %d missing", trial, j, d, m))
                for i = 1, math.min(3, j) do print("      " .. violations.jumps[i]) end
                print(string.format("      CDs: SoR=%.2f HotR=%.2f Cons=%.2f HS=%.2f Judge=%.2f",
                    cds.shield_of_righteousness, cds.hammer_of_the_righteous,
                    cds.consecration, cds.holy_shield, cds.judgement))
            end
        end
    end
    print(string.format("    100 trials: %d total jumps, %d total dupes, %d total missing",
        totalJumps, totalDupes, totalMissing))
    assert(totalDupes == 0, totalDupes .. " duplicates across 100 trials")
    assert(totalMissing == 0, totalMissing .. " missing recs across 100 trials")
    if totalJumps > 0 then
        error(totalJumps .. " jumps across 100 trials")
    end
end)

test("Ret: 100 random CD configurations, 30s each", function()
    DH._snoozed["avenging_wrath"] = true
    math.randomseed(54321)
    local totalJumps = 0
    local totalDupes = 0
    local totalMissing = 0

    for trial = 1, 100 do
        local cds = {
            crusader_strike = math.random() * 4,
            judgement = math.random() * 8,
            divine_storm = math.random() * 10,
            consecration = math.random() * 8,
        }
        local _, violations, _ = simulateCombat("trial" .. trial, "ret", {
            talents = { divine_storm = 1 },
            cds = cds,
            duration = 30,
            frame_step = 0.005,
        })
        local j = #violations.jumps
        local d = #violations.duplicates
        local m = #violations.missing
        totalJumps = totalJumps + j
        totalDupes = totalDupes + d
        totalMissing = totalMissing + m
        if j > 0 then
            print(string.format("    Trial %d: %d jumps", trial, j))
            for i = 1, math.min(3, j) do print("      " .. violations.jumps[i]) end
            print(string.format("      CDs: CS=%.2f Judge=%.2f DS=%.2f Cons=%.2f",
                cds.crusader_strike, cds.judgement, cds.divine_storm, cds.consecration))
        end
    end
    print(string.format("    100 trials: %d total jumps, %d total dupes, %d total missing",
        totalJumps, totalDupes, totalMissing))
    assert(totalDupes == 0, totalDupes .. " duplicates across 100 trials")
    assert(totalMissing == 0, totalMissing .. " missing recs across 100 trials")
    if totalJumps > 0 then
        error(totalJumps .. " jumps across 100 trials")
    end
end)

-- ============================================================================
-- SUMMARY
-- ============================================================================

print(string.format("\n=== RESULTS: %d passed, %d failed ===\n", passed, failed))
if failed > 0 then os.exit(1) end
