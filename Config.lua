-- Config.lua
-- Minimap button with rotation mode dropdown for DruidHelper (3.3.5a, no dependencies)

local DH = DruidHelper
if not DH then return end

local ns = DH.ns

-- ============================================================================
-- ROTATION MODE SYSTEM
-- Class modules register available modes via DH:RegisterMode() (defined in DruidHelper.lua)
-- ============================================================================

-- Get the active mode data
function DH:GetActiveMode()
    local modeKey = self.db and self.db.mode or nil
    for _, mode in ipairs(ns.registered.modes) do
        if mode.key == modeKey then
            return mode
        end
    end
    -- Fallback to first registered mode
    return ns.registered.modes[1]
end

-- ============================================================================
-- DROPDOWN MENU
-- ============================================================================

local dropdownFrame = CreateFrame("Frame", "DruidHelperDropdown", UIParent, "UIDropDownMenuTemplate")

local function BuildDropdown(self, level)
    level = level or 1
    if level ~= 1 then return end

    local info = UIDropDownMenu_CreateInfo()
    local currentMode = DH.db and DH.db.mode or nil

    -- Title
    info.text = "DruidHelper"
    info.isTitle = true
    info.notCheckable = true
    UIDropDownMenu_AddButton(info, level)

    -- Separator
    info = UIDropDownMenu_CreateInfo()
    info.text = ""
    info.disabled = true
    info.notCheckable = true
    UIDropDownMenu_AddButton(info, level)

    -- Rotation modes
    for _, mode in ipairs(ns.registered.modes) do
        info = UIDropDownMenu_CreateInfo()
        info.text = mode.name
        info.icon = mode.icon
        info.checked = (currentMode == mode.key)
        info.func = function()
            DH.db.mode = mode.key
            DH:Print("Mode: " .. mode.name)
            -- Update minimap button icon to match selected mode
            if ns.MinimapButton and mode.icon then
                ns.MinimapButton.icon:SetTexture(mode.icon)
            end
            DH:UpdateRecommendations()
        end
        UIDropDownMenu_AddButton(info, level)
    end

    -- Separator
    info = UIDropDownMenu_CreateInfo()
    info.text = ""
    info.disabled = true
    info.notCheckable = true
    UIDropDownMenu_AddButton(info, level)

    -- Toggle enable/disable
    info = UIDropDownMenu_CreateInfo()
    info.text = DH.db.enabled and "Disable" or "Enable"
    info.notCheckable = true
    info.func = function()
        DH.db.enabled = not DH.db.enabled
        DH:Print("DruidHelper " .. (DH.db.enabled and "enabled" or "disabled"))
        if not DH.db.enabled then DH:HideUI() end
    end
    UIDropDownMenu_AddButton(info, level)

    -- Lock display
    info = UIDropDownMenu_CreateInfo()
    info.text = DH.db.locked and "Unlock Display" or "Lock Display"
    info.notCheckable = true
    info.func = function()
        DH.db.locked = not DH.db.locked
        DH:Print("Display " .. (DH.db.locked and "locked" or "unlocked"))
        if ns.UI.MainFrame then
            ns.UI.MainFrame:EnableMouse(not DH.db.locked)
        end
    end
    UIDropDownMenu_AddButton(info, level)
end

-- ============================================================================
-- MINIMAP BUTTON
-- ============================================================================

local function CreateMinimapButton()
    local button = CreateFrame("Button", "DruidHelperMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    button:SetMovable(true)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    -- Border overlay
    local overlay = button:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(53, 53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT")

    -- Background
    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetPoint("CENTER")

    -- Icon (will be set to active mode's icon)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    icon:SetPoint("CENTER")
    button.icon = icon

    -- Set icon to current mode
    local activeMode = DH:GetActiveMode()
    if activeMode and activeMode.icon then
        icon:SetTexture(activeMode.icon)
    end

    -- Position around minimap
    local function UpdatePosition(angle)
        local rad = math.rad(angle or 225)
        local x = math.cos(rad) * 80
        local y = math.sin(rad) * 80
        button:ClearAllPoints()
        button:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end

    -- Dragging
    button:SetScript("OnDragStart", function(self)
        if DH.db and DH.db.minimap and DH.db.minimap.locked then return end
        self:SetScript("OnUpdate", function(self)
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale
            local angle = math.deg(math.atan2(cy - my, cx - mx))
            if DH.db and DH.db.minimap then
                DH.db.minimap.position = angle
            end
            UpdatePosition(angle)
        end)
    end)

    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    -- Click: open dropdown
    button:SetScript("OnClick", function(self, btn)
        GameTooltip:Hide()
        UIDropDownMenu_Initialize(dropdownFrame, BuildDropdown, "MENU")
        ToggleDropDownMenu(1, nil, dropdownFrame, self, 0, 0)
    end)

    -- Tooltip
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("DruidHelper v" .. DH.Version)
        local activeMode = DH:GetActiveMode()
        if activeMode then
            GameTooltip:AddLine("Mode: |cFF00FF00" .. activeMode.name .. "|r", 1, 1, 1)
        end
        GameTooltip:AddLine("|cFFFFFFFFClick|r to select rotation mode", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    ns.MinimapButton = button

    -- Apply saved position
    local pos = DH.db and DH.db.minimap and DH.db.minimap.position or 225
    UpdatePosition(pos)

    if DH.db and DH.db.minimap and DH.db.minimap.hide then
        button:Hide()
    end

    return button
end

-- ============================================================================
-- OVERRIDE ROTATION DISPATCH
-- Use the selected mode's rotation instead of spec-based dispatch
-- ============================================================================

function DH:UpdateRecommendations()
    if not self.db or not self.db.enabled then return end
    if not UnitExists("target") and not ns.inCombat then return end

    self:UpdateState()

    local mode = self:GetActiveMode()
    local recommendations = {}

    if mode and mode.rotation then
        recommendations = mode.rotation(self)
    end

    ns.recommendations = recommendations
    self:UpdateUI()

    if #recommendations > 0 then
        self:ShowUI()
    end
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

local origOnEnable = DH.OnEnable
function DH:OnEnable()
    origOnEnable(self)

    -- Auto-select first mode if none saved
    if not self.db.mode and #ns.registered.modes > 0 then
        self.db.mode = ns.registered.modes[1].key
    end

    CreateMinimapButton()
end

-- Inject minimap defaults before DB init
local origOnInit = DH.OnInitialize
function DH:OnInitialize()
    local configDefaults = {
        minimap = {
            hide = false,
            locked = false,
            position = 225,
        },
        mode = nil,  -- Will be set to first registered mode on first load
    }
    for k, v in pairs(configDefaults) do
        ns.registered.defaults[k] = ns.registered.defaults[k] or v
    end

    origOnInit(self)
end

-- Slash command to toggle minimap visibility
DH:RegisterSlashCommand("minimap", function(cmd)
    if DH.db.minimap then
        DH.db.minimap.hide = not DH.db.minimap.hide
        if ns.MinimapButton then
            if DH.db.minimap.hide then
                ns.MinimapButton:Hide()
            else
                ns.MinimapButton:Show()
            end
        end
        DH:Print("Minimap button: " .. (DH.db.minimap.hide and "hidden" or "shown"))
    end
end, "minimap - Toggle minimap button visibility")
