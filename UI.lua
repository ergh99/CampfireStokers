local CS = select(2, ...)

---@class CampfireStokersUI
CS.UI = CS.UI or {}

-- The campfire aura can drop and reapply repeatedly while the player sits
-- at the fire without moving (see docs/decision-log.md), so losing it
-- doesn't close the panel immediately - it starts this grace-period
-- countdown instead, cancelled if the aura comes back before it elapses.
local AUTO_CLOSE_GRACE_SECONDS = 10
local ROW_HEIGHT = 22
local ROW_INDENT = 28
local CATEGORY_GAP = 6
local PANEL_WIDTH = 460
local HIGHLIGHT_DURATION = 0.15
local PROFESSION_ICON_SIZE = 64
local PROFESSION_ICON_GAP = 8
local PROFESSION_BLOCK_SIDE_PADDING = 8
local PROFESSION_BLOCK_TOP_GAP = 8
local PROFESSION_BLOCK_BOTTOM_GAP = 8
-- Title area, then the profession button block (if any), THEN Say/Yell,
-- then the phrase tree - profession goods always yell regardless of the
-- Say/Yell toggle, so they sit above it, not sandwiched between it and
-- the phrases it actually controls (reported as confusing placement
-- during in-client testing).
local TITLE_AREA_HEIGHT = 34
local SAY_YELL_HEIGHT = 20
local SAY_YELL_BOTTOM_GAP = 10
local CONTROLS_MIN_HEIGHT = TITLE_AREA_HEIGHT + SAY_YELL_HEIGHT + SAY_YELL_BOTTOM_GAP

local frame
local sayButton
local yellButton
local rowPool = {}
local activeRows = {}
local pendingHideTimer
local professionButtons = {}
local previousProfessionBlockHeight = 0
local combatFlushFrame
local professionBlockDirty = false

CS.UI.isAutoOpened = false

local function cancelPendingHide()
    if pendingHideTimer then
        pendingHideTimer:Cancel()
        pendingHideTimer = nil
    end
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
        row.collapseIcon:SetSize(16, 16)
        row.collapseIcon:SetPoint("LEFT", row, "LEFT", 6, 0)
        row.collapseIcon:SetHighlightTexture("Interface/Buttons/UI-PlusButton-Hilight", "ADD")

        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.text:SetJustifyH("LEFT")
    end

    row.collapseIcon:Hide()
    row.collapseIcon:SetScript("OnClick", nil)
    row.text:ClearAllPoints()
    row.text:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.text:SetFontObject("GameFontHighlight")
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
    GameTooltip:SetOwner(row, "ANCHOR_CURSOR_RIGHT")
    GameTooltip:SetText(row.tooltipText, nil, nil, nil, nil, true)
    GameTooltip:Show()
end

local function hideRowTooltip()
    GameTooltip:Hide()
end

local function professionBorderColor(action)
    if action == "use" then
        return 0.3, 0.9, 0.3
    elseif action == "craft" then
        return 0.4, 0.6, 1
    end
    return 0.8, 0.55, 0.2
end

-- Creates one of the 11 fixed profession-good buttons, permanently bound
-- to its own item - unlike acquireRow's pool, these are never recycled
-- (a SecureActionButtonTemplate button's identity can't be reassigned
-- the way a pooled row's label can). RegisterForClicks deliberately
-- requests only "AnyUp": requesting "AnyDown" too was confirmed
-- in-client to double-fire PreClick per physical click, which would
-- double-craft or double-yell - see docs/decision-log.md.
local function createProfessionButton(entry)
    local button = CreateFrame("Button", "CampfireStokersProfessionButton" .. entry.id, frame,
        "SecureActionButtonTemplate, BackdropTemplate")
    button:SetSize(PROFESSION_ICON_SIZE, PROFESSION_ICON_SIZE)
    button:RegisterForClicks("AnyUp")
    button:SetBackdrop({
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 10,
    })

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
    button.icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)

    button:SetScript("OnEnter", showRowTooltip)
    button:SetScript("OnLeave", hideRowTooltip)

    -- PreClick, not OnClick, so this coexists with the secure click path:
    -- when type/item are set (action == "use"), the secure click-through
    -- handles the item use and pendingAction is nil, so this is a no-op;
    -- when they're cleared (craft/request), this is the only logic that
    -- runs. Confirmed in-client 2026-10-04 that both cases work with no
    -- taint - see docs/decision-log.md.
    button:SetScript("PreClick", function(self)
        if self.pendingAction == "craft" then
            CS.Professions.Craft(self.pendingRecipeSpellId)
        elseif self.pendingAction == "request" then
            local message = CS.Professions.BuildRequestMessage(
                self.pendingEntry, self.pendingItemId, self.pendingMissing
            )
            if message then
                CS.Send.Send(message, { sendMode = "YELL", report = print })
            else
                -- BuildRequestMessage returns nil rather than a message
                -- with a raw item id in it when a reagent's name isn't
                -- cached yet - never send that, just tell the player
                -- locally and let them try again once it's warmed.
                print("Campfire Stokers: " .. CS.Data.L.pg_request_not_ready)
            end
        end
    end)

    button:Hide()
    return button
end

local function applyProfessionButtonState(button, result)
    button.icon:SetTexture(result.icon)
    button:SetBackdropBorderColor(professionBorderColor(result.action))

    button.pendingAction = result.action
    button.pendingRecipeSpellId = result.recipeSpellId
    button.pendingItemId = result.itemId
    button.pendingMissing = result.missing
    button.pendingEntry = result.entry

    if result.action == "use" then
        button:SetAttribute("type", "item")
        button:SetAttribute("item", result.itemName)
        button.tooltipText = result.itemName
    else
        button:SetAttribute("type", nil)
        if result.action == "craft" then
            button.tooltipText = result.entry.itemName .. " - " .. CS.Data.L.pg_tooltip_craft
        else
            button.tooltipText = result.entry.itemName .. " - " .. CS.Data.L.pg_tooltip_request
        end
    end
end

-- All attribute/position/visibility changes for these buttons are
-- protected on a secure-templated frame, so this whole step is skipped
-- during combat (leaving the prior layout untouched, always safe) and
-- queued for one flush on PLAYER_REGEN_ENABLED - the standard pattern
-- real action-bar addons use.
local function queueCombatFlush()
    professionBlockDirty = true
    if not combatFlushFrame then
        combatFlushFrame = CreateFrame("Frame")
        combatFlushFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        combatFlushFrame:SetScript("OnEvent", function()
            if professionBlockDirty then
                professionBlockDirty = false
                CS.UI.Refresh()
            end
        end)
    end
end

-- Lays out the visible subset of professionButtons as a wrapped icon
-- grid starting at `startY`, and returns the block's total height (0 if
-- nothing's visible). Label-less icon buttons with a tooltip, not a
-- vertical list of text rows like the phrase tree - see the plan's
-- "UI.lua integration" section.
-- Evaluating one entry calls out to several real C_TradeSkillUI/C_Item
-- APIs we don't fully control (and some, like IsRecipeProfessionLearned,
-- were only ever tested against a stable state - not against rapid
-- aura drop/reapply while the panel refreshes repeatedly). pcall-wrapped
-- so one entry throwing doesn't abort the whole block and leave every
-- button after it stuck in whatever Show/Hide state it had before the
-- throw - reported from in-client testing: profession buttons could
-- vanish and never come back after some number of aura flaps, which is
-- exactly that failure mode. A caught error is reported (not silently
-- swallowed) and treated as "not visible" for that entry.
local function evaluateGoodSafely(entry)
    if not CS.Detection.atFire then
        return { visible = false }
    end
    local ok, result = pcall(CS.Professions.EvaluateGood, entry)
    if not ok then
        print("Campfire Stokers: profession good '" .. entry.id .. "' failed to evaluate: " .. tostring(result))
        return { visible = false }
    end
    return result
end

local function layoutProfessionBlock(startY)
    if InCombatLockdown() then
        queueCombatFlush()
        return previousProfessionBlockHeight
    end

    local availableWidth = PANEL_WIDTH - (2 * PROFESSION_BLOCK_SIDE_PADDING)
    local columns = math.max(1, math.floor(availableWidth / (PROFESSION_ICON_SIZE + PROFESSION_ICON_GAP)))
    local topY = startY - PROFESSION_BLOCK_TOP_GAP
    local column, row = 0, 0

    for _, entry in ipairs(CS.Professions.GOODS) do
        local button = professionButtons[entry.id]
        local result = evaluateGoodSafely(entry)

        if result.visible then
            local x = PROFESSION_BLOCK_SIDE_PADDING + column * (PROFESSION_ICON_SIZE + PROFESSION_ICON_GAP)
            local y = topY - row * (PROFESSION_ICON_SIZE + PROFESSION_ICON_GAP)
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
            applyProfessionButtonState(button, result)
            button:Show()

            column = column + 1
            if column >= columns then
                column = 0
                row = row + 1
            end
        else
            button:Hide()
            button:SetAttribute("type", nil)
            button.pendingAction = nil
        end
    end

    local rowsUsed = row + (column > 0 and 1 or 0)
    if rowsUsed > 0 then
        previousProfessionBlockHeight = PROFESSION_BLOCK_TOP_GAP
            + (rowsUsed * PROFESSION_ICON_SIZE) + ((rowsUsed - 1) * PROFESSION_ICON_GAP)
            + PROFESSION_BLOCK_BOTTOM_GAP
    else
        previousProfessionBlockHeight = 0
    end
    return previousProfessionBlockHeight
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

    local y = -TITLE_AREA_HEIGHT
    y = y - layoutProfessionBlock(y)

    sayButton:ClearAllPoints()
    sayButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, y)
    yellButton:ClearAllPoints()
    yellButton:SetPoint("LEFT", sayButton, "RIGHT", 4, 0)
    y = y - SAY_YELL_HEIGHT - SAY_YELL_BOTTOM_GAP

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
        headerRow.text:SetPoint("LEFT", headerRow.collapseIcon, "RIGHT", 6, 0)
        headerRow.text:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
        headerRow.text:SetFontObject("GameFontNormalLarge")
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

    frame:SetHeight(math.max(-y + 8, CONTROLS_MIN_HEIGHT + ROW_HEIGHT))
end

function CS.UI.Show()
    if not frame then
        return
    end
    cancelPendingHide()
    CS.UI.isAutoOpened = false
    frame:Show()
end

function CS.UI.Hide()
    if not frame then
        return
    end
    cancelPendingHide()
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

-- Lets CS.Professions's live-refresh event frame skip rebuilding the
-- panel while it's hidden.
function CS.UI.IsPanelShown()
    return frame ~= nil and frame:IsShown()
end

-- Registered with CS.Detection as the state-changed callback. Auto-open
-- mirrors aura detection directly, with no delay or cooldown. Leaving the
-- fire (which also covers "auras just became restricted," since Detection
-- reports that as not-at-fire too) doesn't close the panel immediately -
-- it starts the grace-period countdown instead, cancelled if the aura
-- comes back before it elapses. Only a panel this add-on auto-opened is
-- ever auto-closed; a manually opened one stays up regardless.
function CS.UI.OnCampfireStateChanged(atFire)
    if not frame then
        return
    end
    CS.UI.Refresh() -- the profession block's visibility is gated on atFire too
    if atFire then
        cancelPendingHide()
        if not frame:IsShown() then
            CS.UI.isAutoOpened = true
            frame:Show()
        end
    elseif CS.UI.isAutoOpened then
        cancelPendingHide()
        pendingHideTimer = C_Timer.NewTimer(AUTO_CLOSE_GRACE_SECONDS, function()
            pendingHideTimer = nil
            frame:Hide()
            CS.UI.isAutoOpened = false
        end)
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
-- handler, after CampfireStokersDB has been bootstrapped. Every phrase
-- row calls an ordinary Lua function (CS.Send.Send / CS.Tree
-- operations), nothing protected - the 11 profession-good buttons are
-- the one exception, built with SecureActionButtonTemplate (see
-- createProfessionButton above and docs/decision-log.md).
function CS.UI.CreatePanel()
    CampfireStokersDB.collapsedCategories = CampfireStokersDB.collapsedCategories or {}
    CampfireStokersDB.sendMode = CampfireStokersDB.sendMode or "SAY"

    frame = CreateFrame("Frame", "CampfireStokersPanel", UIParent, "BackdropTemplate")
    frame:SetSize(PANEL_WIDTH, CONTROLS_MIN_HEIGHT + ROW_HEIGHT)
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
    local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -10)
    titleText:SetText(CS.Data.L.ui_panel_title)

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)
    closeButton:SetScript("OnClick", CS.UI.Hide)

    -- Say/Yell as a two-state segmented control (both options always
    -- visible, the active one locked-highlighted) instead of one button
    -- whose own label mutates - a single toggle button is ambiguous about
    -- whether its current label names the active mode or the mode a click
    -- would switch to.
    -- Position is set dynamically in Refresh() (below the profession
    -- block, which can be zero height), not fixed here.
    sayButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    sayButton:SetSize(44, SAY_YELL_HEIGHT)
    sayButton:SetText(CS.Data.L.ui_say)

    yellButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    yellButton:SetSize(44, SAY_YELL_HEIGHT)
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

    for _, entry in ipairs(CS.Professions.GOODS) do
        professionButtons[entry.id] = createProfessionButton(entry)
    end

    frame:Hide()
    CS.UI.Refresh()

    return frame
end
