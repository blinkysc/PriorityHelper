-- State.lua
-- Generic game state tracking for DruidHelper (3.3.5a compatible)
-- Class modules register buffs, debuffs, cooldowns, talents, glyphs via the registration API.

local DH = DruidHelper
if not DH then return end

local ns = DH.ns
local class = DH.Class
local state = DH.State

-- State variables
state.now = 0
state.offset = 0
state.gcd = 0
state.gcd_remains = 0
state.latency = 0.05

state.inCombat = false
state.GUID = nil
state.level = 1

-- Resources (using power type numbers for 3.3.5a)
-- 0 = Mana, 1 = Rage, 2 = Focus, 3 = Energy, 4 = Happiness, 5 = Runes, 6 = Runic Power
state.health = { current = 0, max = 0, pct = 0 }
state.mana = { current = 0, max = 0, pct = 0, regen = 0 }
state.energy = { current = 0, max = 100, regen = 10 }
state.rage = { current = 0, max = 100 }
state.combo_points = { current = 0, max = 5 }
state.runic_power = { current = 0, max = 100 }

-- Target info
state.target = {
    exists = false,
    guid = nil,
    health = { current = 0, max = 0, pct = 0 },
    time_to_die = 300,
    distance = 0,
    inRange = false,
    canAttack = false,
}

-- Buffs and debuffs
state.buff = {}
state.debuff = {}

-- Cooldowns
state.cooldown = {}

-- Talent tracking
state.talent = {}

-- Glyph tracking
state.glyph = {}

-- Set bonuses
state.set_bonus = {}

-- Equipped items
state.equipped = {}

-- Swing timer
state.swings = {
    mainhand = 0,
    mainhand_speed = 2.5,
}

-- Form tracking (Druid forms, stances, etc.)
state.form = 0
state.cat_form = false
state.bear_form = false
state.moonkin_form = false

-- Active enemies tracking
state.active_enemies = 1

-- Stat tracking
state.stat = {
    attack_power = 0,
    spell_power = 0,
    crit = 0,
    haste = 0,
    armor_pen_rating = 0,
    spell_haste = 1,
}

-- Settings shortcut
state.settings = {}

-- ============================================================================
-- METATABLES
-- ============================================================================

-- Metatable for buff tracking
local buffMT = {
    __index = function(t, k)
        if k == "up" then
            return t.remains > 0
        elseif k == "down" then
            return t.remains <= 0
        elseif k == "remains" then
            return t.expires and math.max(0, t.expires - GetTime()) or 0
        elseif k == "stack" or k == "stacks" then
            return t.count or 0
        elseif k == "duration" then
            return t._duration or 0
        end
        return rawget(t, k)
    end
}

local function CreateAuraTable()
    return setmetatable({
        expires = 0,
        count = 0,
        _duration = 0,
        applied = 0,
        last_applied = 0,
    }, buffMT)
end

-- Metatable for cooldown tracking
local cooldownMT = {
    __index = function(t, k)
        if k == "up" or k == "ready" then
            return t.remains <= 0.1
        elseif k == "down" then
            return t.remains > 0.1
        elseif k == "remains" then
            local start, duration = t.start or 0, t.duration or 0
            if start == 0 then return 0 end
            local now = state.now or GetTime()
            return math.max(0, start + duration - now)
        end
        return rawget(t, k)
    end
}

local function CreateCooldownTable()
    return setmetatable({
        start = 0,
        duration = 0,
    }, cooldownMT)
end

-- Metatable for talents
local talentMT = {
    __index = function(t, k)
        local data = rawget(t, k)
        if data then return data end
        return { rank = 0 }
    end
}

-- Metatable for glyphs
local glyphMT = {
    __index = function(t, k)
        return { enabled = false }
    end
}

-- Export CreateAuraTable for class modules that need custom aura tracking
ns.CreateAuraTable = CreateAuraTable
ns.CreateCooldownTable = CreateCooldownTable

-- ============================================================================
-- INITIALIZATION (uses registered data)
-- ============================================================================

function state:Init()
    self.GUID = UnitGUID("player")
    self.level = UnitLevel("player")

    -- Initialize buff tables from registered data
    for _, buff in ipairs(ns.registered.buffs) do
        self.buff[buff] = CreateAuraTable()
    end

    -- Initialize debuff tables from registered data
    for _, debuff in ipairs(ns.registered.debuffs) do
        self.debuff[debuff] = CreateAuraTable()
    end

    -- Initialize cooldown tables from registered data
    for key, _ in pairs(ns.registered.cooldowns) do
        self.cooldown[key] = CreateCooldownTable()
    end

    -- Set metatables
    setmetatable(self.talent, talentMT)
    setmetatable(self.glyph, glyphMT)
end

-- ============================================================================
-- STATE RESET (called each update cycle)
-- ============================================================================

function state:Reset()
    self.now = GetTime()
    self.GUID = UnitGUID("player")
    self.level = UnitLevel("player")

    -- Update combat state
    self.inCombat = UnitAffectingCombat("player")
    ns.inCombat = self.inCombat

    -- Update GCD using registered spell
    local gcdSpellId = ns.registered.gcdSpellId
    if gcdSpellId then
        local gcdStart, gcdDuration = GetSpellCooldown(gcdSpellId)
        if gcdStart and gcdStart > 0 then
            self.gcd = gcdDuration
            self.gcd_remains = math.max(0, gcdStart + gcdDuration - self.now)
        else
            self.gcd = 1.5
            self.gcd_remains = 0
        end
    else
        self.gcd = 1.5
        self.gcd_remains = 0
    end

    -- Update resources
    self:UpdateResources()

    -- Update target
    self:UpdateTarget()

    -- Update active enemy count
    self:UpdateActiveEnemies()

    -- Update form
    self:UpdateForm()

    -- Update buffs
    self:UpdateBuffs()

    -- Update debuffs
    self:UpdateDebuffs()

    -- Update cooldowns
    self:UpdateCooldowns()

    -- Update stats
    self:UpdateStats()

    -- Update talents
    self:UpdateTalents()

    -- Update glyphs
    self:UpdateGlyphs()

    -- Update settings reference
    if DH.db then
        self.settings = DH.db
    end
end

-- ============================================================================
-- RESOURCE UPDATES
-- ============================================================================

function state:UpdateResources()
    -- Health
    self.health.current = UnitHealth("player")
    self.health.max = UnitHealthMax("player")
    self.health.pct = self.health.max > 0 and (self.health.current / self.health.max * 100) or 0

    -- Mana (power type 0)
    self.mana.current = UnitPower("player", 0)
    self.mana.max = UnitPowerMax("player", 0)
    self.mana.pct = self.mana.max > 0 and (self.mana.current / self.mana.max * 100) or 0

    -- Energy (power type 3)
    self.energy.current = UnitPower("player", 3)
    self.energy.max = UnitPowerMax("player", 3)
    if self.energy.max == 0 then self.energy.max = 100 end

    -- Rage (power type 1)
    self.rage.current = UnitPower("player", 1)
    self.rage.max = 100

    -- Combo Points
    self.combo_points.current = GetComboPoints("player", "target")

    -- Runic Power (power type 6)
    self.runic_power.current = UnitPower("player", 6)
    self.runic_power.max = UnitPowerMax("player", 6)
    if self.runic_power.max == 0 then self.runic_power.max = 100 end
end

function state:UpdateActiveEnemies()
    if UnitExists("target") and UnitCanAttack("player", "target") then
        self.active_enemies = 1
    else
        self.active_enemies = 0
    end
end

function state:UpdateTarget()
    self.target.exists = UnitExists("target")
    self.target.guid = UnitGUID("target")

    if self.target.exists then
        self.target.health.current = UnitHealth("target")
        self.target.health.max = UnitHealthMax("target")
        self.target.health.pct = self.target.health.max > 0 and (self.target.health.current / self.target.health.max * 100) or 0

        -- Estimate time to die
        if self.target.health.pct < 20 then
            self.target.time_to_die = 10
        elseif self.target.health.pct < 35 then
            self.target.time_to_die = 30
        else
            self.target.time_to_die = 300
        end

        -- Check if target is a training dummy
        local name = UnitName("target")
        if name and name:find("Dummy") then
            self.target.time_to_die = DH.db and DH.db.common and DH.db.common.dummy_ttd or 300
            if self.debuff.training_dummy then
                self.debuff.training_dummy.expires = self.now + 3600
            end
        else
            if self.debuff.training_dummy then
                self.debuff.training_dummy.expires = 0
            end
        end

        -- Range check using CheckInteractDistance (3.3.5a compatible)
        if CheckInteractDistance("target", 3) then
            self.target.distance = 5
            self.target.inRange = true
        elseif CheckInteractDistance("target", 4) then
            self.target.distance = 20
            self.target.inRange = false
        else
            self.target.distance = 40
            self.target.inRange = false
        end

        self.target.canAttack = UnitCanAttack("player", "target")
    else
        self.target.health.current = 0
        self.target.health.max = 0
        self.target.health.pct = 0
        self.target.time_to_die = 0
        self.target.distance = 40
        self.target.inRange = false
        self.target.canAttack = false
    end
end

-- ============================================================================
-- FORM / STANCE
-- ============================================================================

function state:UpdateForm()
    self.form = GetShapeshiftForm()

    -- Reset form booleans (class modules set these via form handlers)
    self.cat_form = false
    self.bear_form = false
    self.moonkin_form = false

    -- Dispatch to registered form handlers
    for formId, handler in pairs(ns.registered.formHandlers) do
        if self.form == formId then
            handler(self)
        end
    end
end

-- ============================================================================
-- BUFF / DEBUFF UPDATES (using registered maps)
-- ============================================================================

function state:UpdateBuffs()
    -- Track which buff keys are form-related (set by form handlers)
    local formBuffKeys = {}
    for formId, _ in pairs(ns.registered.formHandlers) do
        -- Form handlers manage their own buff state, skip those
    end

    -- Reset non-form buff expires
    for key, buff in pairs(self.buff) do
        if type(buff) == "table" and buff.expires then
            -- Don't reset form buffs (handled by UpdateForm via form handlers)
            if not buff._isForm then
                buff.expires = 0
                buff.count = 0
            end
        end
    end

    -- Scan player buffs
    for i = 1, 40 do
        local name, _, icon, count, debuffType, duration, expirationTime, source, _, _, spellId = UnitBuff("player", i)
        if not name then break end

        local key = ns.registered.buffMap[spellId]
        if key and self.buff[key] then
            self.buff[key].expires = expirationTime or (self.now + 3600)
            self.buff[key].count = count or 1
            self.buff[key]._duration = duration or 0
            self.buff[key].applied = expirationTime and (expirationTime - duration) or self.now
        end
    end
end

function state:UpdateDebuffs()
    if not self.target.exists then return end

    -- Reset debuff expires
    for key, debuff in pairs(self.debuff) do
        if type(debuff) == "table" and debuff.expires and key ~= "training_dummy" then
            debuff.expires = 0
            debuff.count = 0
        end
    end

    -- Scan target debuffs
    for i = 1, 40 do
        local name, _, icon, count, debuffType, duration, expirationTime, source, _, _, spellId = UnitDebuff("target", i)
        if not name then break end

        if source == "player" then
            -- Try spell ID map first
            local key = ns.registered.debuffMap[spellId]

            -- Fallback to name patterns
            if not key and name then
                local lowerName = name:lower()
                for _, pattern in ipairs(ns.registered.debuffNamePatterns) do
                    if lowerName:find(pattern[1]) then
                        key = pattern[2]
                        break
                    end
                end
            end

            if key and self.debuff[key] then
                self.debuff[key].expires = expirationTime or (self.now + 3600)
                self.debuff[key].count = count or 1
                self.debuff[key]._duration = duration or 0
            end
        end

        -- Track external debuffs (from other players)
        if source ~= "player" then
            local key = ns.registered.externalDebuffMap[spellId]

            if not key and name then
                local lowerName = name:lower()
                for _, pattern in ipairs(ns.registered.externalDebuffNamePatterns) do
                    if lowerName:find(pattern[1]) then
                        key = pattern[2]
                        break
                    end
                end
            end

            if key and self.debuff[key] then
                self.debuff[key].expires = expirationTime or (self.now + 3600)
            end
        end
    end
end

-- ============================================================================
-- COOLDOWN UPDATES (using registered data)
-- ============================================================================

function state:UpdateCooldowns()
    for key, spellId in pairs(ns.registered.cooldowns) do
        local start, duration, enabled = GetSpellCooldown(spellId)
        if self.cooldown[key] then
            -- Filter out GCD
            if duration and duration > 1.5 then
                self.cooldown[key].start = start or 0
                self.cooldown[key].duration = duration or 0
            else
                self.cooldown[key].start = 0
                self.cooldown[key].duration = 0
            end
        end
    end
end

-- ============================================================================
-- STAT UPDATES
-- ============================================================================

function state:UpdateStats()
    local base, posBuff, negBuff = UnitAttackPower("player")
    self.stat.attack_power = base + posBuff + negBuff

    self.stat.spell_power = GetSpellBonusDamage(4) -- Nature damage

    self.stat.crit = GetCritChance()
    self.stat.haste = GetCombatRatingBonus(18) -- CR_HASTE_MELEE
    self.stat.armor_pen_rating = GetCombatRating(25) -- CR_ARMOR_PENETRATION

    local spellHaste = GetCombatRatingBonus(20) -- CR_HASTE_SPELL
    self.stat.spell_haste = 1 + (spellHaste / 100)
end

-- ============================================================================
-- TALENT / GLYPH UPDATES (using registered data)
-- ============================================================================

function state:UpdateTalents()
    for _, data in ipairs(ns.registered.talents) do
        local tab, index, key = data[1], data[2], data[3]
        local _, _, _, _, rank = GetTalentInfo(tab, index)
        self.talent[key] = { rank = rank or 0 }
    end
end

function state:UpdateGlyphs()
    -- Reset all registered glyph keys
    local glyphKeys = {}
    for _, key in pairs(ns.registered.glyphs) do
        glyphKeys[key] = true
    end
    for key in pairs(glyphKeys) do
        self.glyph[key] = { enabled = false }
    end

    -- Scan equipped glyphs (3.3.5a has 6 glyph slots)
    for i = 1, 6 do
        local enabled, glyphType, glyphTooltipIndex, glyphSpell, icon = GetGlyphSocketInfo(i)
        if enabled and glyphSpell then
            local key = ns.registered.glyphs[glyphSpell]
            if key then
                self.glyph[key] = { enabled = true }
            end
        end
    end
end

-- ============================================================================
-- CONVENIENCE ACCESSORS
-- ============================================================================

setmetatable(state, {
    __index = function(t, k)
        if k == "ttd" then
            return t.target.time_to_die
        elseif k == "time" then
            return t.now
        elseif k == "query_time" then
            return t.now + t.offset
        elseif k == "haste" then
            return 1 / (1 + t.stat.haste / 100)
        elseif k == "mainhand_speed" then
            local speed = UnitAttackSpeed("player")
            return speed or 2.5
        end
        return rawget(t, k)
    end
})

-- Initialize on load
state:Init()
