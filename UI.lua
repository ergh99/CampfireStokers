local CS = select(2, ...)

---@class CampfireStokersUI
CS.UI = CS.UI or {}

local AUTO_OPEN_DEFAULT_DELAY = 300 -- seconds; CampfireStokersDB.autoOpenDelay overrides
local ROW_HEIGHT = 20
local ROW_INDENT = 14
local CATEGORY_GAP = 6
local PANEL_WIDTH = 300
local TOP_CONTROLS_HEIGHT = 58
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

        -- Standard Blizzard disclosure icon instead of a "+"/"-" text
        -- prefix, matching how the rest of the default UI shows
        -- collapsible sections.
        row.collapseIcon = CreateFrame("Button", nil, row)
        row.collapseIcon:SetSize(14, 14)
        row.collapseIcon:SetPoint("LEFT", row, "LEFT", 2, 0)
        row.collapseIcon:SetHighlightTexture("Interface/Buttons/UI-PlusButton-Hilight", "ADD")

        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.text:SetJustifyH("LEFT")
    end

    row.collapseIcon:Hide()
    row.collapseIcon:SetScript("OnClick", nil)
    row.text:ClearAllPoints()
    row.text:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.text:SetFontObject("GameFontNormalSmall")
    row.text:SetTextColor(1, 1, 1)
    row.phrase = nil
    row.needsTarget = nil
    row.sendable = nil
    row.classifyReason = nil
    row.tooltipText = nil
    -- Deliberately not row:SetEnabled(false) anywhere: a disabled Button
    -- stops receiving OnEnter/OnLeave in WoW, which would silently kill
    -- the tooltip on exactly the rows that need to explain themselves.
    -- Clickability is controlled solely by whether OnClick is attached.
    row:SetEnabled(true)
    row:SetScript("OnClick", nil)
    row:SetScript("OnEnter", nil)
    row:SetScript("OnLeave", nil)
    row:Show()
    return row
end

local function releaseRows()
    for _, row in ipairs(activeRows) do
        row:Hide()
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

local function showRowTooltip(row)
    if not row.tooltipText then
        return
    end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(row.tooltipText, nil, nil, nil, nil, true)
    GameTooltip:Show()
end

local function hideRowTooltip()
    GameTooltip:Hide()
end

-- Applies enabled/disabled + color + tooltip to one phrase row from its
-- already-set .sendable/.needsTarget/.classifyReason, without recomputing
-- Classify. Shared by Refresh (which sets those) and the
-- PLAYER_TARGET_CHANGED handler (which only needs to react to target
-- state).
local function applyRowState(row)
    local hasTarget = UnitExists("target")
    local enabled = row.sendable and (not row.needsTarget or hasTarget)
    if not row.sendable then
        row.text:SetTextColor(0.7, 0.35, 0.35) -- flagged: never sendable
        row.tooltipText = row.classifyReason
    elseif not enabled then
        row.text:SetTextColor(0.6, 0.6, 0.6) -- needs a target first
        row.tooltipText = CS.Data.L.ui_needs_target_tooltip
    else
        row.text:SetTextColor(1, 1, 1)
        row.tooltipText = nil
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
    for categoryIndex, category in ipairs(CampfireStokersDB.tree) do
        if categoryIndex > 1 then
            y = y - CATEGORY_GAP
        end

        local headerRow = acquireRow()
        headerRow:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, y)
        headerRow:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
        local collapsed = isCategoryCollapsed(category.id)
        headerRow.collapseIcon:Show()
        headerRow.collapseIcon:SetNormalTexture(
            collapsed and "Interface/Buttons/UI-PlusButton-Up" or "Interface/Buttons/UI-MinusButton-Up"
        )
        headerRow.collapseIcon:SetPushedTexture(
            collapsed and "Interface/Buttons/UI-PlusButton-Down" or "Interface/Buttons/UI-MinusButton-Down"
        )
        headerRow.collapseIcon:SetScript("OnClick", function()
            onCategoryClick(category)
        end)
        headerRow.text:ClearAllPoints()
        headerRow.text:SetPoint("LEFT", headerRow.collapseIcon, "RIGHT", 4, 0)
        headerRow.text:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
        headerRow.text:SetFontObject("GameFontNormal")
        headerRow.text:SetTextColor(1, 0.82, 0) -- WoW's standard header gold
        headerRow.text:SetText(category.name)
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
                local action = CS.Send.Classify(phrase.text, sendOptions())
                phraseRow.sendable = action.kind ~= "rejected"
                phraseRow.classifyReason = action.reason
                phraseRow:SetScript("OnEnter", showRowTooltip)
                phraseRow:SetScript("OnLeave", hideRowTooltip)
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

local textPromptPopup

-- Builds the editable counterpart to ShowTextPopup: a multi-line, reviewable
-- text field with a live character counter and an inline error message,
-- rather than StaticPopupDialogs' single-line EditBox (too small to review
-- a 255-character phrase - see docs/decision-log.md) discarding what the
-- player typed the moment validation fails.
local function ensureTextPromptPopup()
    if textPromptPopup then
        return textPromptPopup
    end

    local popup = CreateFrame("Frame", "CampfireStokersTextPromptPopup", UIParent, "BackdropTemplate")
    popup:SetSize(420, 230)
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

    popup.label = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    popup.label:SetPoint("TOPLEFT", popup, "TOPLEFT", 20, -18)
    popup.label:SetPoint("RIGHT", popup, "RIGHT", -20, 0)
    popup.label:SetJustifyH("LEFT")

    local scrollFrame = CreateFrame("ScrollFrame", nil, popup, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", popup.label, "BOTTOMLEFT", 0, -10)
    scrollFrame:SetPoint("RIGHT", popup, "RIGHT", -34, 0)
    scrollFrame:SetHeight(110)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(true)
    editBox:SetFontObject("ChatFontNormal")
    editBox:SetWidth(scrollFrame:GetWidth())
    scrollFrame:SetScrollChild(editBox)
    popup.scrollFrame = scrollFrame
    popup.editBox = editBox

    popup.charCount = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    popup.charCount:SetPoint("TOPLEFT", scrollFrame, "BOTTOMLEFT", 0, -6)

    popup.errorText = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    popup.errorText:SetPoint("TOPLEFT", popup.charCount, "BOTTOMLEFT", 0, -4)
    popup.errorText:SetPoint("RIGHT", popup, "RIGHT", -20, 0)
    popup.errorText:SetJustifyH("LEFT")
    popup.errorText:SetTextColor(1, 0.3, 0.3)

    local function updateCharCount()
        if not popup.charLimit then
            popup.charCount:SetText("")
            return
        end
        local len = #popup.editBox:GetText()
        popup.charCount:SetText(len .. " / " .. popup.charLimit)
        popup.charCount:SetTextColor(len > popup.charLimit and 1 or 0.6, len > popup.charLimit and 0.3 or 0.6, 0.6)
    end
    popup.updateCharCount = updateCharCount

    editBox:SetScript("OnTextChanged", function()
        popup.errorText:SetText("")
        updateCharCount()
    end)
    editBox:SetScript("OnEscapePressed", function()
        popup:Hide()
    end)

    local function doAccept()
        -- Sanitize embedded newlines (a multi-line box lets the player
        -- press Enter) rather than trying to prevent them at input time;
        -- a phrase is always one logical line of chat text.
        local text = popup.editBox:GetText():gsub("[\r\n]+", " ")
        local ok, err = popup.onAccept(text)
        if ok == false then
            popup.errorText:SetText(err or "")
        else
            popup:Hide()
        end
    end

    local acceptButton = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
    acceptButton:SetSize(90, 22)
    acceptButton:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -20, 16)
    acceptButton:SetText(CS.Data.L.ui_accept)
    acceptButton:SetScript("OnClick", doAccept)

    local cancelButton = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
    cancelButton:SetSize(90, 22)
    cancelButton:SetPoint("RIGHT", acceptButton, "LEFT", -8, 0)
    cancelButton:SetText(CS.Data.L.ui_cancel)
    cancelButton:SetScript("OnClick", function()
        popup:Hide()
    end)

    popup:Hide()
    textPromptPopup = popup
    return popup
end

-- Shows an editable text prompt. `config`:
--   title       instructional label (e.g. "New phrase text:")
--   initialText text to pre-fill
--   charLimit   optional; shows a live counter against this limit when set
--   onAccept(text) -> true, or false, errorMessage
--     Returning false keeps the popup open with the entered text intact
--     and shows errorMessage, instead of silently discarding what the
--     player typed the way the old StaticPopupDialogs-based prompt did.
function CS.UI.PromptForText(config)
    local popup = ensureTextPromptPopup()
    popup.label:SetText(config.title)
    popup.editBox:SetText(config.initialText or "")
    popup.editBox:HighlightText()
    popup.editBox:SetFocus()
    popup.charLimit = config.charLimit
    popup.onAccept = config.onAccept
    popup.errorText:SetText("")
    popup.updateCharCount()
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

    -- Title bar: identifies the window (there's otherwise nothing showing
    -- what this floating, undecorated frame even is) and doubles as the
    -- expected place to grab it, since a title strip is the universal
    -- convention for "this is how you move this window."
    local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -10)
    titleText:SetText(CS.Data.L.ui_panel_title)

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    closeButton:SetScript("OnClick", CS.UI.Hide)

    -- Say/Yell as a two-state segmented control (both options always
    -- visible, the active one locked-highlighted) instead of one button
    -- whose own label mutates - a single toggle button is ambiguous about
    -- whether its current label names the active mode or the mode a click
    -- would switch to.
    local sayButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    sayButton:SetSize(44, 20)
    sayButton:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -10)
    sayButton:SetText(CS.Data.L.ui_say)

    local yellButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    yellButton:SetSize(44, 20)
    yellButton:SetPoint("LEFT", sayButton, "RIGHT", 4, 0)
    yellButton:SetText(CS.Data.L.ui_yell)

    local function refreshSendModeButtons()
        if CampfireStokersDB.sendMode == "YELL" then
            yellButton:LockHighlight()
            sayButton:UnlockHighlight()
        else
            sayButton:LockHighlight()
            yellButton:UnlockHighlight()
        end
    end

    sayButton:SetScript("OnClick", function()
        CampfireStokersDB.sendMode = "SAY"
        refreshSendModeButtons()
        CS.UI.Refresh()
    end)
    yellButton:SetScript("OnClick", function()
        CampfireStokersDB.sendMode = "YELL"
        refreshSendModeButtons()
        CS.UI.Refresh()
    end)
    refreshSendModeButtons()

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
