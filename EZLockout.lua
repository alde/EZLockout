local SIDEBAR_WIDTH = 250
local ROW_HEIGHT = 20
local PADDING = 8
local ROW_PADDING = 4
local TITLE_HEIGHT = 28
local TITLE_GAP = 8
local SCROLL_INSET_LEFT = 4
local SCROLL_INSET_RIGHT = 24
local CONTENT_WIDTH = SIDEBAR_WIDTH - SCROLL_INSET_LEFT - SCROLL_INSET_RIGHT
local ICON_SIZE = 16
local TOGGLE_OFFSET_X = -6
local TOGGLE_OFFSET_Y = -36

local TEXTURE_PREV = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage"
local TEXTURE_NEXT = "Interface\\Buttons\\UI-SpellbookIcon-NextPage"

local BACKDROP_INFO = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local state = {
    sidebar = nil,
    scrollFrame = nil,
    scrollChild = nil,
    emptyText = nil,
    toggleButton = nil,
    rows = {},
    initialized = false,
    visibleBeforeCombat = false,
}

local function CreateLockoutRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(CONTENT_WIDTH, ROW_HEIGHT)

    row.icon = row:CreateTexture(nil, "OVERLAY")
    row.icon:SetSize(ICON_SIZE, ICON_SIZE)
    row.icon:SetPoint("LEFT", ROW_PADDING, 0)

    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.label:SetPoint("LEFT", row.icon, "RIGHT", ROW_PADDING, 0)
    row.label:SetPoint("RIGHT", -ROW_PADDING, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)

    local separator = row:CreateTexture(nil, "ARTWORK")
    separator:SetHeight(1)
    separator:SetPoint("BOTTOMLEFT", 0, 0)
    separator:SetPoint("BOTTOMRIGHT", 0, 0)
    separator:SetColorTexture(0.4, 0.4, 0.4, 0.3)

    row:SetScript("OnEnter", function(self)
        if not self.lockoutInfo then return end
        local info = self.lockoutInfo
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(info.instanceName, 1, 1, 1)
        if info.difficultyName ~= "" then
            GameTooltip:AddLine(info.difficultyName, 0.8, 0.8, 0.8)
        end
        GameTooltip:AddLine(info.encounterProgress .. "/" .. info.numEncounters .. " bosses", 1, 0.82, 0)
        GameTooltip:AddLine("Resets in " .. SecondsToTime(info.reset), 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)

    return row
end

local function GetOrCreateRow(index)
    if not state.rows[index] then
        state.rows[index] = CreateLockoutRow(state.scrollChild)
    end
    return state.rows[index]
end

local function CollectActiveLockouts()
    local lockouts = {}
    local numInstances = GetNumSavedInstances()

    for i = 1, numInstances do
        local name, _, reset, _, locked, _, _, isRaid, _, difficultyName,
              numEncounters, encounterProgress = GetSavedInstanceInfo(i)
        if locked and reset > 0 then
            table.insert(lockouts, {
                instanceName = name or "Unknown",
                difficultyName = difficultyName or "",
                numEncounters = numEncounters or 0,
                encounterProgress = encounterProgress or 0,
                reset = reset,
                isRaid = isRaid == true,
            })
        end
    end

    table.sort(lockouts, function(a, b)
        if a.isRaid and not b.isRaid then return true end
        if not a.isRaid and b.isRaid then return false end
        return a.instanceName < b.instanceName
    end)

    return lockouts
end

local function UpdateRow(row, lockoutInfo, index)
    local displayName = lockoutInfo.instanceName
    if lockoutInfo.difficultyName ~= "" then
        displayName = displayName .. " (" .. lockoutInfo.difficultyName .. ")"
    end

    row.label:SetText(displayName)
    row.icon:SetAtlas(lockoutInfo.isRaid and "Raid" or "Dungeon")
    row.lockoutInfo = lockoutInfo

    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", PADDING, -(PADDING + (index - 1) * ROW_HEIGHT))
    row:Show()
end

local function RefreshLockouts()
    if not state.sidebar or not state.sidebar:IsShown() then
        return
    end

    local lockouts = CollectActiveLockouts()

    for i = 1, #lockouts do
        UpdateRow(GetOrCreateRow(i), lockouts[i], i)
    end

    for i = #lockouts + 1, #state.rows do
        state.rows[i]:Hide()
    end

    local totalHeight = #lockouts * ROW_HEIGHT + PADDING * 2
    state.scrollChild:SetHeight(math.max(totalHeight, 1))

    local scrollBar = state.scrollFrame.ScrollBar
    if scrollBar then
        local frameHeight = state.scrollFrame:GetHeight()
        if totalHeight > frameHeight then
            scrollBar:Show()
        else
            scrollBar:Hide()
        end
    end

    if #lockouts == 0 then
        state.emptyText:Show()
    else
        state.emptyText:Hide()
    end
end

local function SetCollapsed(collapsed)
    EZLockoutDB.collapsed = collapsed

    local texturePath = collapsed and TEXTURE_PREV or TEXTURE_NEXT
    state.toggleButton:SetNormalTexture(texturePath .. "-Up")
    state.toggleButton:SetPushedTexture(texturePath .. "-Down")

    if not PVEFrame:IsShown() then
        return
    end

    if collapsed then
        state.sidebar:Hide()
    else
        state.sidebar:Show()
        RequestRaidInfo()
    end
end

local function CreateToggleButton()
    local button = CreateFrame("Button", "EZLockoutToggle", PVEFrame)
    button:SetSize(24, 24)
    button:SetPoint("RIGHT", PVEFrame, "TOPRIGHT", TOGGLE_OFFSET_X, TOGGLE_OFFSET_Y)
    button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

    button:SetScript("OnClick", function()
        SetCollapsed(not EZLockoutDB.collapsed)
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Toggle EZLockout")
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)

    return button
end

local function CreateScrollContent(parent)
    local scrollFrame = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", SCROLL_INSET_LEFT, -(TITLE_HEIGHT + TITLE_GAP))
    scrollFrame:SetPoint("BOTTOMRIGHT", -SCROLL_INSET_RIGHT, 4)

    local child = CreateFrame("Frame", nil, scrollFrame)
    child:SetWidth(CONTENT_WIDTH)
    child:SetHeight(1)
    scrollFrame:SetScrollChild(child)

    state.scrollFrame = scrollFrame
    return child
end

local function CreateSidebar()
    local sidebarFrame = CreateFrame("Frame", "EZLockoutSidebar", PVEFrame, "BackdropTemplate")
    sidebarFrame:SetWidth(SIDEBAR_WIDTH)
    sidebarFrame:SetPoint("TOPLEFT", PVEFrame, "TOPRIGHT", -1, 0)
    sidebarFrame:SetPoint("BOTTOMLEFT", PVEFrame, "BOTTOMRIGHT", -1, 0)
    sidebarFrame:SetFrameLevel(PVEFrame:GetFrameLevel() + 1)

    sidebarFrame:SetBackdrop(BACKDROP_INFO)
    sidebarFrame:SetBackdropColor(0, 0, 0, 0.9)

    local titleBar = CreateFrame("Frame", nil, sidebarFrame)
    titleBar:SetHeight(TITLE_HEIGHT)
    titleBar:SetPoint("TOPLEFT", 4, -4)
    titleBar:SetPoint("TOPRIGHT", -4, -4)

    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", 4, 0)
    title:SetText("Lockouts")

    local separator = titleBar:CreateTexture(nil, "ARTWORK")
    separator:SetHeight(1)
    separator:SetPoint("BOTTOMLEFT", 0, 0)
    separator:SetPoint("BOTTOMRIGHT", 0, 0)
    separator:SetColorTexture(0.6, 0.6, 0.6, 0.4)

    state.scrollChild = CreateScrollContent(sidebarFrame)

    state.emptyText = sidebarFrame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    state.emptyText:SetPoint("CENTER", 0, 0)
    state.emptyText:SetText("No active lockouts")
    state.emptyText:Hide()

    state.sidebar = sidebarFrame
    state.toggleButton = CreateToggleButton()
end

local function HookPVEFrame()
    PVEFrame:HookScript("OnShow", function()
        if InCombatLockdown() then return end
        state.toggleButton:Show()
        if not EZLockoutDB.collapsed then
            state.sidebar:Show()
        end
        -- RequestRaidInfo is async; UPDATE_INSTANCE_INFO will trigger RefreshLockouts
        RequestRaidInfo()
    end)

    PVEFrame:HookScript("OnHide", function()
        state.sidebar:Hide()
        state.toggleButton:Hide()
    end)
end

local function Initialize()
    if state.initialized or not PVEFrame then
        return
    end
    state.initialized = true

    CreateSidebar()
    HookPVEFrame()
    SetCollapsed(EZLockoutDB.collapsed)
end

EZLockoutDB = EZLockoutDB or { collapsed = false }

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("UPDATE_INSTANCE_INFO")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "ADDON_LOADED" then
        if not state.initialized then
            Initialize()
        end
        if state.initialized then
            eventFrame:UnregisterEvent("ADDON_LOADED")
        end
    elseif event == "UPDATE_INSTANCE_INFO" then
        RefreshLockouts()
    elseif event == "PLAYER_REGEN_DISABLED" then
        if state.sidebar and state.sidebar:IsShown() then
            state.visibleBeforeCombat = true
            state.sidebar:Hide()
            state.toggleButton:Hide()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if state.visibleBeforeCombat and PVEFrame:IsShown() then
            state.visibleBeforeCombat = false
            state.toggleButton:Show()
            if not EZLockoutDB.collapsed then
                state.sidebar:Show()
            end
        end
    end
end)
