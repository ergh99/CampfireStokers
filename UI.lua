local CS = select(2, ...)

---@class CampfireStokersUI
CS.UI = CS.UI or {}

local AUTO_OPEN_DEFAULT_DELAY = 300 -- seconds; CampfireStokersDB.autoOpenDelay overrides
local ROW_HEIGHT = 20
local ROW_INDENT = 14
local PANEL_WIDTH = 260
local TOP_CONTROLS_HEIGHT = 26
local HIGHLIGHT_DURATION = 0.15

local frame
local rowPool = {}
local activeRows = {}
local lastAutoOpenTime -- session-only (GetTime() seconds); never saved

CS.UI.isAutoOpened = false

-- Pure: whether enough time has passed since the last auto-open to allow
-- another one. lastTime == nil means "never auto-opened this session," so
-- the very first campfire of a session always opens the panel immediately.
function CS.UI.ShouldAutoOpen(lastTime, now, delaySeconds)
    if lastTime == nil then
        return true
    end
    return (now - lastTime) >= delaySeconds
end

local function acquireRow()
    local row = table.remove(rowPool)
    if not row then
        row = CreateFrame("Button", nil, frame)
        row:SetHeight(ROW_HEIGHT)
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.text:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.text:SetJustifyH("LEFT")
    end
    row.phrase = nil
    row.needsTarget = nil
    row.sendable = nil
    row:SetScript("OnClick", nil)
    row:SetEnabled(true)
    row.text:SetTextColor(1, 1, 1)
    row:Show()
    return row
end

local function releaseRows()
    for _, row in ipairs(activeRows) do
        row:Hide()
        row:SetScript("OnClick", nil)
        table.insert(rowPool, row)
    end
    activeRows = {}
end

local function isCategoryCollapsed(categoryId)
    return CampfireStokersDB.collapsedCategories[categoryId] == true
end

local function setCategoryCollapsed(categoryId, collapsed)
    if collapsed then
        CampfireStokersDB.collapsedCategories[categoryId] = true
    else
        CampfireStokersDB.collapsedCategories[categoryId] = nil
    end
end

local function sendOptions()
    return {
        sendMode = CampfireStokersDB.sendMode,
        report = print,
    }
end

local function flashRow(row)
    row:LockHighlight()
    C_Timer.After(HIGHLIGHT_DURATION, function()
        row:UnlockHighlight()
    end)
end

local function onPhraseClick(row, phrase)
    flashRow(row)
    CS.Send.Send(phrase.text, sendOptions())
end

local function onCategoryClick(category)
    setCategoryCollapsed(category.id, not isCategoryCollapsed(category.id))
    CS.UI.Refresh()
end

-- Applies enabled/disabled + color to one phrase row from its already-set
-- .sendable/.needsTarget flags, without recomputing Classify. Shared by
-- Refresh (which sets those flags) and the PLAYER_TARGET_CHANGED handler
-- (which only needs to react to target state, not reclassify anything).
local function applyRowState(row)
    local hasTarget = UnitExists("target")
    local enabled = row.sendable and (not row.needsTarget or hasTarget)
    row:SetEnabled(enabled)
    if not row.sendable then
        row.text:SetTextColor(0.7, 0.35, 0.35) -- flagged: never sendable
    elseif not enabled then
        row.text:SetTextColor(0.6, 0.6, 0.6) -- needs a target first
    else
        row.text:SetTextColor(1, 1, 1)
    end
    if enabled then
        row:SetScript("OnClick", function()
            onPhraseClick(row, row.phrase)
        end)
    else
        row:SetScript("OnClick", nil)
    end
end

local function refreshTargetGating()
    for _, row in ipairs(activeRows) do
        if row.phrase and row.needsTarget then
            applyRowState(row)
        end
    end
end

function CS.UI.Refresh()
    if not frame then
        return
    end

    releaseRows()

    local y = -TOP_CONTROLS_HEIGHT
    for _, category in ipairs(CampfireStokersDB.tree) do
        local headerRow = acquireRow()
        headerRow:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, y)
        headerRow:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
        local collapsed = isCategoryCollapsed(category.id)
        headerRow.text:SetText((collapsed and "+ " or "- ") .. category.name)
        headerRow:SetScript("OnClick", function()
            onCategoryClick(category)
        end)
        table.insert(activeRows, headerRow)
        y = y - ROW_HEIGHT

        if not collapsed then
            for _, phrase in ipairs(category.children) do
                local phraseRow = acquireRow()
                phraseRow:SetPoint("TOPLEFT", frame, "TOPLEFT", 4 + ROW_INDENT, y)
                phraseRow:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
                phraseRow.text:SetText(phrase.text)
                phraseRow.phrase = phrase
                phraseRow.needsTarget = CS.Send.ContainsTargetToken(phrase.text)
                phraseRow.sendable = CS.Send.Classify(phrase.text, sendOptions()).kind ~= "rejected"
                applyRowState(phraseRow)

                table.insert(activeRows, phraseRow)
                y = y - ROW_HEIGHT
            end
        end
    end

    frame:SetHeight(math.max(-y + 8, TOP_CONTROLS_HEIGHT + ROW_HEIGHT))
end

function CS.UI.Show()
    if not frame then
        return
    end
    CS.UI.isAutoOpened = false
    frame:Show()
end

function CS.UI.Hide()
    if not frame then
        return
    end
    CS.UI.isAutoOpened = false
    frame:Hide()
end

function CS.UI.Toggle()
    if not frame then
        return
    end
    if frame:IsShown() then
        CS.UI.Hide()
    else
        CS.UI.Show()
    end
end

local function autoOpen()
    CS.UI.isAutoOpened = true
    lastAutoOpenTime = GetTime()
    frame:Show()
end

-- Registered with CS.Detection as the state-changed callback. Auto-open is
-- rate-limited and only for entering a campfire; leaving one (which also
-- covers "auras just became restricted," since Detection reports that as
-- not-at-fire too) hides the panel only if this add-on is the one that
-- opened it - a manually opened panel stays open when you stand up.
function CS.UI.OnCampfireStateChanged(atFire)
    if not frame then
        return
    end
    if atFire then
        local delay = CampfireStokersDB.autoOpenDelay or AUTO_OPEN_DEFAULT_DELAY
        if CS.UI.ShouldAutoOpen(lastAutoOpenTime, GetTime(), delay) then
            autoOpen()
        end
    elseif CS.UI.isAutoOpened then
        frame:Hide()
        CS.UI.isAutoOpened = false
    end
end

local textPopup

-- Same technique simc-addon uses to show exportable text: a DialogBox-style
-- backdrop frame holding a ScrollFrame whose scroll child is a multi-line
-- EditBox. HighlightText() selects everything on show, so Ctrl+C copies
-- immediately with no custom clipboard handling. Built lazily and reused,
-- since nothing needs more than one of these open at a time.
local function ensureTextPopup()
    if textPopup then
        return textPopup
    end

    local popup = CreateFrame("Frame", "CampfireStokersTextPopup", UIParent, "BackdropTemplate")
    popup:SetSize(420, 320)
    popup:SetPoint("CENTER")
    popup:SetFrameStrata("DIALOG")
    popup:SetBackdrop({
        bgFile = "Interface/DialogFrame/UI-DialogBox-Background",
        edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    popup:SetMovable(true)
    popup:EnableMouse(true)
    popup:SetClampedToScreen(true)

    popup.title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    popup.title:SetPoint("TOP", popup, "TOP", 0, -16)

    local closeButton = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -4, -4)
    closeButton:SetScript("OnClick", function()
        popup:Hide()
    end)

    local scrollFrame = CreateFrame("ScrollFrame", nil, popup, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", popup, "TOPLEFT", 16, -40)
    scrollFrame:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -32, 16)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(true)
    editBox:SetFontObject("ChatFontNormal")
    editBox:SetWidth(scrollFrame:GetWidth())
    editBox:SetScript("OnEscapePressed", function()
        popup:Hide()
    end)
    scrollFrame:SetScrollChild(editBox)
    popup.editBox = editBox

    popup:Hide()
    textPopup = popup
    return popup
end

-- Shows `text` in a scrollable, selectable popup instead of dumping it into
-- chat - used for T6's selftest report, which is too long and multi-line
-- for chat to display legibly.
function CS.UI.ShowTextPopup(title, text)
    local popup = ensureTextPopup()
    popup.title:SetText(title)
    popup.editBox:SetText(text)
    popup.editBox:HighlightText()
    popup:Show()
end

-- Creates the panel frame. Called once, from Core.lua's ADDON_LOADED
-- handler, after CampfireStokersDB has been bootstrapped. Uses no secure
-- templates: every click just calls an ordinary Lua function
-- (CS.Send.Send / CS.Tree operations), nothing protected.
function CS.UI.CreatePanel()
    CampfireStokersDB.collapsedCategories = CampfireStokersDB.collapsedCategories or {}
    CampfireStokersDB.autoOpenDelay = CampfireStokersDB.autoOpenDelay or AUTO_OPEN_DEFAULT_DELAY
    CampfireStokersDB.sendMode = CampfireStokersDB.sendMode or "SAY"

    frame = CreateFrame("Frame", "CampfireStokersPanel", UIParent, "BackdropTemplate")
    frame:SetSize(PANEL_WIDTH, TOP_CONTROLS_HEIGHT + ROW_HEIGHT)
    frame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.8)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")

    local savedPosition = CampfireStokersDB.position
    if savedPosition then
        frame:SetPoint(savedPosition.point, UIParent, savedPosition.point, savedPosition.x, savedPosition.y)
    else
        frame:SetPoint("BOTTOMLEFT", DEFAULT_CHAT_FRAME, "TOPLEFT", 0, 20)
    end

    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        CampfireStokersDB.position = { point = point, x = x, y = y }
    end)

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 2, 2)
    closeButton:SetScript("OnClick", CS.UI.Hide)

    local sendModeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    sendModeButton:SetSize(56, 20)
    sendModeButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
    local function refreshSendModeLabel()
        sendModeButton:SetText(CampfireStokersDB.sendMode == "YELL" and CS.Data.L.ui_yell or CS.Data.L.ui_say)
    end
    sendModeButton:SetScript("OnClick", function()
        CampfireStokersDB.sendMode = (CampfireStokersDB.sendMode == "YELL") and "SAY" or "YELL"
        refreshSendModeLabel()
        CS.UI.Refresh()
    end)
    refreshSendModeLabel()

    frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    frame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_TARGET_CHANGED" then
            refreshTargetGating()
        end
    end)

    frame:Hide()
    CS.UI.Refresh()

    return frame
end
