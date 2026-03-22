-- tests/test_druid_sim.lua
-- Realistic Druid rotation simulator
-- Simulates combat: player casts Rec1 every GCD, state updates per frame,
-- checks for jumping, duplicates, and missing recommendations.
-- Run: lua5.4 tests/test_druid_sim.lua

-- ============================================================================
-- MOCK WOW API
-- ============================================================================

_G._mockTime = 0
_G._mockForm = 3  -- 1=bear, 3=cat, 5=moonkin
function GetTime() return _G._mockTime end
function UnitClass(unit) return "Druid", "DRUID" end
function GetSpellInfo(id) return "Spell" .. id, nil, 135891 end
function GetShapeshiftForm() return _G._mockForm end
function GetNumTalentTabs() return 3 end
function GetTalentTabInfo(i)
    if i == 2 then return nil, nil, 51 end  -- Feral
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
            debuffMap = {}, externalDebuffMap = {}, slashCommands = {},
            formHandlers = {}, combatLogHandlers = {},
            debugFrameUpdater = nil,
        },
        manaCosts = {},
        abilityCDs = {},
        UI = { MainFrame = true },
        inCombat = true,
        snoozeable = {},
    },
    Class = { abilities = {}, abilityByName = {} },
    State = {},
    db = { enabled = true, feral_cat = { bearweave = true }, feral_bear = {} },
    _snoozed = {},
}

local DH = PriorityHelper
local ns = DH.ns

function DH:RegisterGCDSpell() end
function DH:RegisterMeleeAbilities() end
function DH:RegisterBuffs(b) for _, k in ipairs(b) do table.insert(ns.registered.buffs, k) end end
function DH:RegisterDebuffs(d) for _, k in ipairs(d) do table.insert(ns.registered.debuffs, k) end end
function DH:RegisterCooldowns(c) for k, v in pairs(c) do ns.registered.cooldowns[k] = v end end
function DH:RegisterTalents() end
function DH:RegisterGlyphs() end
function DH:RegisterBuffMap() end
function DH:RegisterDebuffMap() end
function DH:RegisterExternalDebuffMap() end
function DH:RegisterDebuffNamePatterns() end
function DH:RegisterExternalDebuffNamePatterns() end
function DH:RegisterSpecDetector() end
function DH:RegisterDefaults() end
function DH:RegisterSnoozeable(k, d) ns.snoozeable[k] = d or 60 end
function DH:RegisterSlashCommand() end
function DH:RegisterFormHandler() end
function DH:RegisterCombatLogHandler() end
function DH:RegisterMode(key, data) table.insert(ns.registered.modes, { key = key, data = data }) end
function DH:RegisterManaCosts(costs) for k, v in pairs(costs) do ns.manaCosts[k] = v end end
function DH:RegisterAbilityCooldowns(cds) for k, v in pairs(cds) do ns.abilityCDs[k] = v end end
function DH:Print(msg) end
function DH:IsSnoozed(key) return self._snoozed[key] or false end

-- Core sim helpers (copied from PriorityHelper.lua)
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

function DH:SimCastTime(simState, baseCastTime)
    return baseCastTime / (simState.haste or 1)
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
        self:SimGainMana(simState, simState.mana_max * 0.002 * seconds)
    end
    if simState.mp5 and simState.mp5 > 0 then
        self:SimGainMana(simState, simState.mp5 / 5 * seconds)
    end
end

function DH:SimInitEnergy(simState, s)
    simState.energy = s.energy.current
    simState.energy_max = s.energy.max or 100
    simState.energy_regen = 10
end

function DH:SimTickEnergy(simState, seconds)
    simState.energy = math.min(simState.energy_max, simState.energy + simState.energy_regen * seconds)
end

function DH:SimInitRage(simState, s)
    simState.rage = s.rage.current
    simState.rage_max = s.rage.max or 100
end

function DH:SimInitTarget(simState, s)
    simState.ttd = s.target.time_to_die
    simState.target_pct = s.target.health.pct
    simState.in_execute = s.target.health.pct < 20
end

function DH:SimInitCD(s, cdKey)
    local cd = s.cooldown[cdKey]
    if cd then return cd.ready, cd.remains end
    return true, 0
end

function DH:SimTickCD(simState, cdField, readyField, seconds)
    if simState[cdField] and simState[cdField] > 0 then
        simState[cdField] = simState[cdField] - seconds
        if simState[cdField] <= 0 then
            simState[readyField] = true
            simState[cdField] = 0
        end
    end
end

function DH:SimWaitTime(simState, cdList)
    local shortest = 999
    for _, cd in ipairs(cdList) do
        if cd > 0 and cd < shortest then shortest = cd end
    end
    return shortest
end

-- RunSimulation (full copy from PriorityHelper.lua)
local function AdvanceSimTime(DH, sim, config, seconds)
    if seconds <= 0 then return end
    for k, v in pairs(sim.cd) do sim.cd[k] = math.max(0, v - seconds) end
    if config.resources then
        for _, res in ipairs(config.resources) do
            if res.regen and res.regen > 0 then
                local cur = sim[res.field] or 0
                local cap = res.max and sim[res.max] or 999999
                sim[res.field] = math.min(cap, cur + res.regen * seconds)
            end
        end
    end
    if config.auras then
        for _, aura in ipairs(config.auras) do
            local rem = sim[aura.remains]
            if rem and rem > 0 then
                rem = rem - seconds
                if rem <= 0 then
                    sim[aura.up] = false
                    sim[aura.remains] = 0
                    if aura.stacks and aura.clearStacks then sim[aura.stacks] = 0 end
                else
                    sim[aura.remains] = rem
                end
            end
        end
    end
    DH:SimTickMana(sim, seconds)
    if config.tickTime then config.tickTime(sim, seconds) end
end

function DH:RunSimulation(s, config)
    local recommendations = {}
    local maxRecs = config.maxRecs or 3
    local allowDupes = config.allowDupes or false
    if not s.target.exists or not s.target.canAttack then return recommendations end

    local sim = {}
    self:SimInitGCD(sim, s, config.gcdType or "melee")
    self:SimInitMana(sim, s)
    self:SimInitTarget(sim, s)

    if config.resources then
        for _, res in ipairs(config.resources) do
            if res.initFrom then
                sim[res.field] = res.initFrom(s)
                if res.max and res.initMaxFrom then sim[res.max] = res.initMaxFrom(s) end
            end
        end
    end

    sim.cd = {}
    if config.cds then
        for simKey, stateKey in pairs(config.cds) do
            local cd = s.cooldown[stateKey]
            sim.cd[simKey] = cd and cd.remains or 0
        end
    end

    if config.initState then config.initState(sim, s) end

    if sim.gcd_remains > 0 then
        AdvanceSimTime(self, sim, config, sim.gcd_remains)
        sim.gcd_remains = 0
    end

    sim.ready = function(self, key) return (self.cd[key] or 0) <= 0 end
    sim.remains = function(self, key) return self.cd[key] or 0 end

    local iters = 0
    while #recommendations < maxRecs and iters < 12 do
        iters = iters + 1
        local action = config.getPriority(sim, recommendations)
        if not action then
            if config.getWaitTime then
                local wait = config.getWaitTime(sim)
                if wait and wait > 0 then
                    AdvanceSimTime(self, sim, config, wait)
                end
            else
                break
            end
        end
        if action then
            local cdRemaining = sim.cd[action] or 0
            if cdRemaining > 0 then AdvanceSimTime(self, sim, config, cdRemaining) end

            local dominated = false
            if not allowDupes then
                for _, rec in ipairs(recommendations) do
                    if rec.ability == action then dominated = true; break end
                end
            end
            if not dominated then
                local ability = self.Class.abilities[action]
                if ability then
                    table.insert(recommendations, { ability = action, texture = ability.texture, name = ability.name })
                end
            end

            if sim.cd[action] ~= nil and config.baseCDs and config.baseCDs[action] then
                sim.cd[action] = config.baseCDs[action]
            end
            if config.onCast then config.onCast(sim, action) end

            local advanceTime = sim.gcd
            if config.getAdvanceTime then advanceTime = config.getAdvanceTime(sim, action) end
            AdvanceSimTime(self, sim, config, advanceTime)
        end
    end
    return recommendations
end

-- ============================================================================
-- STATE FACTORY
-- ============================================================================

local function makeState(overrides)
    overrides = overrides or {}
    local base = {
        now = _G._mockTime,
        gcd_remains = overrides.gcd_remains or 0,
        inCombat = true,
        stat = { haste = 0, spell_haste = 1 },
        mana = { current = 20000, max = 20000, pct = 100 },
        energy = { current = overrides.energy or 100, max = 100 },
        rage = { current = overrides.rage or 0, max = 100 },
        combo_points = { current = overrides.combo_points or 0 },
        target = {
            exists = true, canAttack = true,
            health = { current = 100000, max = 100000, pct = overrides.target_pct or 80 },
            time_to_die = overrides.ttd or 300,
        },
        form = _G._mockForm,
        cat_form = _G._mockForm == 3,
        bear_form = _G._mockForm == 1,
        moonkin_form = _G._mockForm == 5,
        buff = setmetatable({}, { __index = function(t, k)
            return { up = false, remains = 0, stacks = 0, count = 0, last_applied = 0 }
        end }),
        debuff = setmetatable({}, { __index = function(t, k)
            return { up = false, remains = 0, stacks = 0, count = 0 }
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

    -- Apply talent overrides
    if overrides.talents then
        for k, v in pairs(overrides.talents) do
            rawset(base.talent, k, { rank = v })
        end
    end
    if overrides.glyphs then
        for k, v in pairs(overrides.glyphs) do
            rawset(base.glyph, k, { enabled = v })
        end
    end
    if overrides.buffs then
        for k, v in pairs(overrides.buffs) do
            if type(v) == "boolean" then
                rawset(base.buff, k, { up = v, remains = v and 999 or 0, stacks = 0, count = 0, last_applied = 0 })
            else
                rawset(base.buff, k, v)
            end
        end
    end
    if overrides.debuffs then
        for k, v in pairs(overrides.debuffs) do
            if type(v) == "boolean" then
                rawset(base.debuff, k, { up = v, remains = v and 999 or 0, stacks = v and 5 or 0, count = 0 })
            else
                rawset(base.debuff, k, v)
            end
        end
    end
    if overrides.cooldowns then
        for k, v in pairs(overrides.cooldowns) do
            rawset(base.cooldown, k, { ready = v <= 0.1, remains = v })
        end
    end

    return base
end

local function applyToDHState(s)
    for k in pairs(DH.State) do DH.State[k] = nil end
    for k, v in pairs(s) do DH.State[k] = v end
end

-- ============================================================================
-- SMOOTHING (exact copy from Config.lua)
-- ============================================================================

local function createSmoother()
    local smoothState = { prevSlots = {} }

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
            if result[i] then smoothState.prevSlots[result[i].ability] = i end
        end
        return result
    end
end

-- ============================================================================
-- LOAD DRUID
-- ============================================================================

DH.State = makeState({
    talents = {
        mangle = 1, berserk = 1, omen_of_clarity = 1, furor = 5,
        force_of_nature = 1, starfall = 1, insect_swarm = 1,
        natures_splendor = 1, improved_faerie_fire = 1,
    },
    glyphs = { omen_of_clarity = true },
})

dofile("Classes/Druid/Druid.lua")
dofile("Classes/Druid/Core.lua")

-- ============================================================================
-- COMBAT SIMULATOR
-- ============================================================================

local ABILITY_CDS = {
    tigers_fury = 30, berserk = 180, faerie_fire_feral = 6,
    mangle_bear = 6, force_of_nature = 180, starfall = 90,
}

local function simulateCombat(name, modeKey, opts)
    opts = opts or {}
    local FRAME_STEP = opts.frame_step or 0.005
    local DURATION = opts.duration or 300
    local smooth = createSmoother()

    local getRotation
    for _, mode in ipairs(ns.registered.modes) do
        if mode.key == modeKey then
            getRotation = mode.data.rotation
            break
        end
    end
    assert(getRotation, "mode " .. modeKey .. " not found")

    -- Mutable combat state
    local combat = {
        time = 0,
        gcd_expires = 0,
        energy = opts.energy or 100,
        rage = opts.rage or 0,
        combo_points = opts.combo_points or 0,
        buffs = {},    -- { [key] = expires_at }
        debuffs = {},  -- { [key] = { expires = t, stacks = n } }
        cds = {},      -- { [key] = expires_at }
        form = opts.form or 3,
    }

    -- Init CDs
    for k, v in pairs(opts.cds or {}) do
        combat.cds[k] = combat.time + v
    end
    -- Init buffs
    if opts.form == 3 or opts.form == nil then
        combat.buffs.savage_roar = combat.time + (opts.sr_remains or 0)
    end
    if opts.sr_remains and opts.sr_remains > 0 then
        combat.buffs.savage_roar = combat.time + opts.sr_remains
    end
    -- Init debuffs
    if opts.rip_remains and opts.rip_remains > 0 then
        combat.debuffs.rip = { expires = combat.time + opts.rip_remains, stacks = 0 }
    end
    if opts.rake_remains and opts.rake_remains > 0 then
        combat.debuffs.rake = { expires = combat.time + opts.rake_remains, stacks = 0 }
    end

    local violations = { duplicates = {}, jumps = {}, missing = {} }
    local prevDisplay = nil
    local prevCast = nil
    local totalFrames = 0
    local frames = {}

    local PROC_ABILITIES = {
        tigers_fury = true, berserk = true,
        cat_form = true, dire_bear_form = true, moonkin_form = true,
        force_of_nature = true, starfall = true,
    }

    while combat.time < DURATION do
        _G._mockTime = combat.time
        _G._mockForm = combat.form
        totalFrames = totalFrames + 1

        -- Build state
        local s = makeState({
            energy = combat.energy,
            rage = combat.rage,
            combo_points = combat.combo_points,
            gcd_remains = math.max(0, combat.gcd_expires - combat.time),
            talents = {
                mangle = 1, berserk = 1, omen_of_clarity = 1, furor = 5,
                force_of_nature = 1, starfall = 1, insect_swarm = 1,
                natures_splendor = 1, improved_faerie_fire = 1,
            },
            glyphs = { omen_of_clarity = true },
            ttd = math.max(0, DURATION - combat.time),
        })

        -- Apply form state
        s.form = combat.form
        s.cat_form = combat.form == 3
        s.bear_form = combat.form == 1
        s.moonkin_form = combat.form == 5

        -- Apply buff/debuff timers
        for k, exp in pairs(combat.buffs) do
            local rem = math.max(0, exp - combat.time)
            rawset(s.buff, k, { up = rem > 0, remains = rem, stacks = 0, count = 0, last_applied = 0 })
        end
        for k, data in pairs(combat.debuffs) do
            local rem = math.max(0, data.expires - combat.time)
            rawset(s.debuff, k, { up = rem > 0, remains = rem, stacks = data.stacks or 0, count = 0 })
        end

        -- Apply CD timers
        for k, exp in pairs(combat.cds) do
            local rem = math.max(0, exp - combat.time)
            rawset(s.cooldown, k, { ready = rem <= 0.1, remains = rem })
        end

        applyToDHState(s)
        local rawRecs = getRotation(DH)
        local display = smooth(rawRecs)

        local d = {}
        for i = 1, 3 do d[i] = display[i] and display[i].ability or nil end
        local r = {}
        for i = 1, 3 do r[i] = rawRecs[i] and rawRecs[i].ability or nil end

        -- CHECK 1: Missing recs is the only hard check for Druid.
        -- Duplicates in raw output are VALID (e.g., Wrath x2, Lacerate x2).
        -- Duplicates in display are checked but only as warnings.

        -- CHECK 3: Jumping
        if prevDisplay then
            local prevSlot = {}
            for pi = 1, 3 do
                if prevDisplay[pi] then prevSlot[prevDisplay[pi]] = pi end
            end
            for i = 1, 3 do
                if d[i] and prevSlot[d[i]] then
                    local from = prevSlot[d[i]]
                    local to = i
                    if from - to > 1 and not PROC_ABILITIES[d[i]] then
                        table.insert(violations.jumps, string.format(
                            "t=%.2fs: '%s' skipped Rec%d->Rec%d  prev=[%s|%s|%s] now=[%s|%s|%s]",
                            combat.time, d[i], from, to,
                            prevDisplay[1] or "-", prevDisplay[2] or "-", prevDisplay[3] or "-",
                            d[1] or "-", d[2] or "-", d[3] or "-"))
                    end
                    if to > from and d[i] ~= prevCast then
                        table.insert(violations.jumps, string.format(
                            "t=%.2fs: '%s' moved BACK Rec%d->Rec%d  prev=[%s|%s|%s] now=[%s|%s|%s]",
                            combat.time, d[i], from, to,
                            prevDisplay[1] or "-", prevDisplay[2] or "-", prevDisplay[3] or "-",
                            d[1] or "-", d[2] or "-", d[3] or "-"))
                    end
                end
            end
        end

        -- CHECK 4: Missing recs — at least 1 rec should always be produced
        local recCount = 0
        for i = 1, 3 do if r[i] then recCount = recCount + 1 end end
        if recCount < 1 then
            table.insert(violations.missing, string.format(
                "t=%.2fs: EMPTY recs raw=[%s|%s|%s]",
                combat.time, r[1] or "-", r[2] or "-", r[3] or "-"))
        end

        prevDisplay = { d[1], d[2], d[3] }
        prevCast = nil
        table.insert(frames, { t = combat.time, raw = { r[1], r[2], r[3] }, cast = nil })

        -- PLAYER ACTION: cast Rec1 when GCD is up
        if combat.time >= combat.gcd_expires and d[1] then
            local castAbility = d[1]
            frames[#frames].cast = castAbility
            prevCast = castAbility

            -- Set CD if applicable
            if ABILITY_CDS[castAbility] then
                combat.cds[castAbility] = combat.time + ABILITY_CDS[castAbility]
            end

            -- GCD
            combat.gcd_expires = combat.time + 1.5

            -- Simulate ability effects
            if castAbility == "shred" then
                combat.energy = math.max(0, combat.energy - 42)
                combat.combo_points = math.min(5, combat.combo_points + 1)
            elseif castAbility == "mangle_cat" then
                combat.energy = math.max(0, combat.energy - 35)
                combat.combo_points = math.min(5, combat.combo_points + 1)
                combat.debuffs.mangle = { expires = combat.time + 60, stacks = 0 }
            elseif castAbility == "rake" then
                combat.energy = math.max(0, combat.energy - 35)
                combat.combo_points = math.min(5, combat.combo_points + 1)
                combat.debuffs.rake = { expires = combat.time + 9, stacks = 0 }
            elseif castAbility == "rip" then
                combat.energy = math.max(0, combat.energy - 30)
                combat.debuffs.rip = { expires = combat.time + 12 + combat.combo_points * 2, stacks = 0 }
                combat.combo_points = 0
            elseif castAbility == "savage_roar" then
                combat.energy = math.max(0, combat.energy - 25)
                combat.buffs.savage_roar = combat.time + 14 + combat.combo_points * 5
                combat.combo_points = 0
            elseif castAbility == "ferocious_bite" then
                local cost = 35
                local extra = math.min(30, combat.energy - cost)
                combat.energy = math.max(0, combat.energy - cost - extra)
                combat.combo_points = 0
            elseif castAbility == "tigers_fury" then
                combat.energy = math.min(100, combat.energy + 60)
            elseif castAbility == "berserk" then
                combat.buffs.berserk = combat.time + 15
            elseif castAbility == "faerie_fire_feral" then
                -- No resource cost
            elseif castAbility == "lacerate" then
                combat.rage = math.max(0, combat.rage - 13)
                local lac = combat.debuffs.lacerate or { stacks = 0 }
                combat.debuffs.lacerate = { expires = combat.time + 15, stacks = math.min(5, (lac.stacks or 0) + 1) }
            elseif castAbility == "mangle_bear" then
                combat.rage = math.max(0, combat.rage - 15)
                combat.debuffs.mangle = { expires = combat.time + 60, stacks = 0 }
            elseif castAbility == "swipe_bear" then
                combat.rage = math.max(0, combat.rage - 15)
            elseif castAbility == "dire_bear_form" then
                combat.form = 1
                combat.rage = 10  -- Furor
            elseif castAbility == "cat_form" then
                combat.form = 3
                combat.energy = math.min(100, combat.energy + 40)  -- Furor
            elseif castAbility == "moonfire" then
                combat.debuffs.moonfire = { expires = combat.time + 15, stacks = 0 }
            elseif castAbility == "insect_swarm" then
                combat.debuffs.insect_swarm = { expires = combat.time + 14, stacks = 0 }
            elseif castAbility == "starfire" or castAbility == "wrath" then
                -- Nuke, no special state change
            elseif castAbility == "force_of_nature" or castAbility == "starfall" then
                -- CD already set above
            elseif castAbility == "faerie_fire" then
                combat.debuffs.faerie_fire = { expires = combat.time + 300, stacks = 0 }
            end
        end

        -- Tick energy regen (cat form)
        if combat.form == 3 then
            combat.energy = math.min(100, combat.energy + 10 * FRAME_STEP)
        end
        -- Tick rage decay (bear form, slight)
        if combat.form == 1 then
            combat.rage = math.min(100, combat.rage + 2 * FRAME_STEP)  -- Rage from being hit
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

local function printViolations(violations)
    local total = #violations.duplicates + #violations.jumps + #violations.missing
    if total == 0 then return 0 end
    if #violations.duplicates > 0 then
        print("    DUPLICATES (" .. #violations.duplicates .. "):")
        for i = 1, math.min(5, #violations.duplicates) do print("      " .. violations.duplicates[i]) end
    end
    if #violations.jumps > 0 then
        print("    JUMPS (" .. #violations.jumps .. "):")
        for i = 1, math.min(5, #violations.jumps) do print("      " .. violations.jumps[i]) end
    end
    if #violations.missing > 0 then
        print("    MISSING (" .. #violations.missing .. "):")
        for i = 1, math.min(5, #violations.missing) do print("      " .. violations.missing[i]) end
    end
    return total
end

-- ============================================================================
-- FERAL CAT TESTS
-- ============================================================================

print("\n=== FERAL CAT COMBAT SIMULATION ===\n")

test("Cat: 5min combat, fresh start", function()
    _G._mockForm = 3
    DH._snoozed.berserk = true  -- Don't clutter with long CD
    local frames, violations, count = simulateCombat("Cat fresh", "feral_cat", {
        form = 3, energy = 100, combo_points = 0,
        duration = 300, frame_step = 0.005,
    })
    print("    " .. count .. " frames simulated")
    local total = printViolations(violations)
    local total = printViolations(violations)
    -- Jumps are the main concern
    if #violations.jumps > 0 then
        print("    " .. #violations.jumps .. " jumps detected")
    end
end)

test("Cat: 5min combat, mid-fight (SR/Rip running)", function()
    _G._mockForm = 3
    DH._snoozed.berserk = true
    local frames, violations, count = simulateCombat("Cat mid", "feral_cat", {
        form = 3, energy = 60, combo_points = 3,
        sr_remains = 15, rip_remains = 10, rake_remains = 5,
        duration = 300, frame_step = 0.005,
    })
    print("    " .. count .. " frames simulated")
    local total = printViolations(violations)
    local total = printViolations(violations)
    -- Jumps are the main concern
    if #violations.jumps > 0 then
        print("    " .. #violations.jumps .. " jumps detected")
    end
end)

-- ============================================================================
-- FERAL BEAR TESTS
-- ============================================================================

print("\n=== FERAL BEAR COMBAT SIMULATION ===\n")

test("Bear: 5min combat, fresh start", function()
    _G._mockForm = 1
    local frames, violations, count = simulateCombat("Bear fresh", "feral_bear", {
        form = 1, rage = 50, combo_points = 0,
        duration = 300, frame_step = 0.005,
    })
    print("    " .. count .. " frames simulated")
    local total = printViolations(violations)
    local total = printViolations(violations)
    -- Jumps are the main concern
    if #violations.jumps > 0 then
        print("    " .. #violations.jumps .. " jumps detected")
    end
end)

-- ============================================================================
-- BALANCE TESTS
-- ============================================================================

print("\n=== BALANCE COMBAT SIMULATION ===\n")

test("Balance: 5min combat, fresh start", function()
    _G._mockForm = 5
    DH._snoozed.force_of_nature = true
    DH._snoozed.starfall = true
    local frames, violations, count = simulateCombat("Balance fresh", "balance", {
        form = 5, duration = 300, frame_step = 0.005,
    })
    print("    " .. count .. " frames simulated")
    local total = printViolations(violations)
    local total = printViolations(violations)
    -- Jumps are the main concern
    if #violations.jumps > 0 then
        print("    " .. #violations.jumps .. " jumps detected")
    end
end)

-- ============================================================================
-- REC FILL TESTS — must ALWAYS produce 3 recs (or 4 for bear)
-- ============================================================================

print("\n=== REC FILL TESTS ===\n")

test("Cat: 0 energy, 0 CP — must still fill 3 recs", function()
    _G._mockForm = 3
    DH._snoozed.berserk = true
    local frames, violations, count = simulateCombat("Cat empty", "feral_cat", {
        form = 3, energy = 0, combo_points = 0,
        duration = 30, frame_step = 0.005,
    })
    print("    " .. count .. " frames simulated")
    local missingCount = 0
    for _, f in ipairs(frames) do
        local c = 0
        for i = 1, 3 do if f.raw[i] then c = c + 1 end end
        if c < 3 then missingCount = missingCount + 1 end
    end
    print("    Frames with < 3 recs: " .. missingCount .. " / " .. count)
    if missingCount > 0 then
        -- Show first few
        local shown = 0
        for _, f in ipairs(frames) do
            local c = 0
            for i = 1, 3 do if f.raw[i] then c = c + 1 end end
            if c < 3 and shown < 5 then
                shown = shown + 1
                print(string.format("      t=%.2fs: [%s|%s|%s] (%d recs)",
                    f.t, f.raw[1] or "-", f.raw[2] or "-", f.raw[3] or "-", c))
            end
        end
        error(missingCount .. " frames with missing recs")
    end
end)

test("Cat: 5 CP, low energy, SR about to expire — must fill 3 recs", function()
    _G._mockForm = 3
    DH._snoozed.berserk = true
    local frames, violations, count = simulateCombat("Cat pressure", "feral_cat", {
        form = 3, energy = 10, combo_points = 5,
        sr_remains = 2, rip_remains = 4,
        duration = 30, frame_step = 0.005,
    })
    print("    " .. count .. " frames simulated")
    local missingCount = 0
    for _, f in ipairs(frames) do
        local c = 0
        for i = 1, 3 do if f.raw[i] then c = c + 1 end end
        if c < 3 then missingCount = missingCount + 1 end
    end
    print("    Frames with < 3 recs: " .. missingCount .. " / " .. count)
    if missingCount > 0 then
        local shown = 0
        for _, f in ipairs(frames) do
            local c = 0
            for i = 1, 3 do if f.raw[i] then c = c + 1 end end
            if c < 3 and shown < 5 then
                shown = shown + 1
                print(string.format("      t=%.2fs: [%s|%s|%s] (%d recs)",
                    f.t, f.raw[1] or "-", f.raw[2] or "-", f.raw[3] or "-", c))
            end
        end
        error(missingCount .. " frames with missing recs")
    end
end)

test("Cat: mid Berserk, high energy — must fill 3 recs", function()
    _G._mockForm = 3
    local frames, violations, count = simulateCombat("Cat berserk", "feral_cat", {
        form = 3, energy = 80, combo_points = 2,
        sr_remains = 20, rip_remains = 15, rake_remains = 7,
        duration = 30, frame_step = 0.005,
    })
    -- Manually set berserk buff
    print("    " .. count .. " frames simulated")
    local missingCount = 0
    for _, f in ipairs(frames) do
        local c = 0
        for i = 1, 3 do if f.raw[i] then c = c + 1 end end
        if c < 3 then missingCount = missingCount + 1 end
    end
    print("    Frames with < 3 recs: " .. missingCount .. " / " .. count)
    if missingCount > 0 then
        local shown = 0
        for _, f in ipairs(frames) do
            local c = 0
            for i = 1, 3 do if f.raw[i] then c = c + 1 end end
            if c < 3 and shown < 5 then
                shown = shown + 1
                print(string.format("      t=%.2fs: [%s|%s|%s] (%d recs)",
                    f.t, f.raw[1] or "-", f.raw[2] or "-", f.raw[3] or "-", c))
            end
        end
        error(missingCount .. " frames with missing recs")
    end
end)

test("Balance: fresh start — must fill 3 recs every frame", function()
    _G._mockForm = 5
    DH._snoozed.force_of_nature = true
    DH._snoozed.starfall = true
    local frames, violations, count = simulateCombat("Bal fill", "balance", {
        form = 5, duration = 30, frame_step = 0.005,
    })
    print("    " .. count .. " frames simulated")
    local missingCount = 0
    for _, f in ipairs(frames) do
        local c = 0
        for i = 1, 3 do if f.raw[i] then c = c + 1 end end
        if c < 3 then missingCount = missingCount + 1 end
    end
    print("    Frames with < 3 recs: " .. missingCount .. " / " .. count)
    if missingCount > 0 then
        local shown = 0
        for _, f in ipairs(frames) do
            local c = 0
            for i = 1, 3 do if f.raw[i] then c = c + 1 end end
            if c < 3 and shown < 5 then
                shown = shown + 1
                print(string.format("      t=%.2fs: [%s|%s|%s] (%d recs)",
                    f.t, f.raw[1] or "-", f.raw[2] or "-", f.raw[3] or "-", c))
            end
        end
        error(missingCount .. " frames with missing recs")
    end
end)

test("Bear: fresh start — must fill 4 recs every frame", function()
    _G._mockForm = 1
    local frames, violations, count = simulateCombat("Bear fill", "feral_bear", {
        form = 1, rage = 50, duration = 30, frame_step = 0.005,
    })
    print("    " .. count .. " frames simulated")
    local missingCount = 0
    for _, f in ipairs(frames) do
        local c = 0
        for i = 1, 4 do if f.raw[i] then c = c + 1 end end
        if c < 3 then missingCount = missingCount + 1 end  -- At least 3
    end
    print("    Frames with < 3 recs: " .. missingCount .. " / " .. count)
    if missingCount > 0 then
        error(missingCount .. " frames with missing recs")
    end
end)

test("Cat: Berserk + high energy = must show 3 Shreds", function()
    _G._mockForm = 3
    -- Berserk active, SR/Rip/Rake all healthy, 80 energy, 2 CP
    -- Shred costs 21 during Berserk. 80 energy = 3 Shreds (21+21+21=63)
    -- All 3 recs should be Shred
    local s = makeState({
        energy = 80, combo_points = 2,
        talents = {
            mangle = 1, berserk = 1, omen_of_clarity = 1, furor = 5,
        },
        glyphs = { omen_of_clarity = true },
        buffs = {
            berserk = { up = true, remains = 10, stacks = 0, count = 0, last_applied = 0 },
            savage_roar = { up = true, remains = 20, stacks = 0, count = 0, last_applied = 0 },
        },
        debuffs = {
            rip = { up = true, remains = 15, stacks = 0, count = 0 },
            rake = { up = true, remains = 7, stacks = 0, count = 0 },
            mangle = { up = true, remains = 50, stacks = 0, count = 0 },
        },
    })
    applyToDHState(s)

    -- Get rotation directly
    local getRotation
    for _, mode in ipairs(ns.registered.modes) do
        if mode.key == "feral_cat" then getRotation = mode.data.rotation; break end
    end
    local recs = getRotation(DH)

    print(string.format("    Got %d recs:", #recs))
    for i, r in ipairs(recs) do
        print(string.format("      Rec%d: %s", i, r.ability))
    end

    assert(#recs == 3, "Expected 3 recs, got " .. #recs)
    -- All 3 should be shred (nothing else to do, energy for 3 shreds)
    for i = 1, 3 do
        assert(recs[i].ability == "shred",
            "Rec" .. i .. " should be shred, got " .. tostring(recs[i].ability))
    end
end)

test("Cat: Low energy mid-rotation = must still fill 3 recs", function()
    _G._mockForm = 3
    -- 25 energy, 0 CP, SR down, everything needs refresh
    -- Should: wait for energy → SR or Shred → wait → next ability
    local s = makeState({
        energy = 25, combo_points = 0,
        talents = {
            mangle = 1, berserk = 1, omen_of_clarity = 1, furor = 5,
        },
        glyphs = { omen_of_clarity = true },
    })
    applyToDHState(s)

    local getRotation
    for _, mode in ipairs(ns.registered.modes) do
        if mode.key == "feral_cat" then getRotation = mode.data.rotation; break end
    end
    local recs = getRotation(DH)

    print(string.format("    Got %d recs:", #recs))
    for i, r in ipairs(recs) do
        print(string.format("      Rec%d: %s", i, r.ability))
    end

    assert(#recs >= 3, "Expected at least 3 recs, got " .. #recs)
end)

test("Cat: 0 energy, 0 CP, nothing up = must still fill 3 recs", function()
    _G._mockForm = 3
    DH._snoozed.berserk = true
    local s = makeState({
        energy = 0, combo_points = 0,
        talents = {
            mangle = 1, berserk = 1, omen_of_clarity = 1, furor = 5,
        },
        glyphs = { omen_of_clarity = true },
        cooldowns = { tigers_fury = 20 },  -- TF on CD
    })
    applyToDHState(s)

    local getRotation
    for _, mode in ipairs(ns.registered.modes) do
        if mode.key == "feral_cat" then getRotation = mode.data.rotation; break end
    end
    local recs = getRotation(DH)

    print(string.format("    Got %d recs:", #recs))
    for i, r in ipairs(recs) do
        print(string.format("      Rec%d: %s", i, r.ability))
    end

    assert(#recs >= 3, "Expected at least 3 recs, got " .. #recs)
end)

-- ============================================================================
-- SUMMARY
-- ============================================================================

print(string.format("\n=== RESULTS: %d passed, %d failed ===\n", passed, failed))
if failed > 0 then os.exit(1) end
