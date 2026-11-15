local CS = select(2, ...)

---@class CampfireStokersOptions
CS.Options = CS.Options or {}

local ROW_HEIGHT = 26
local ROW_INDENT = 16
local CATEGORY_GAP = 8
local BUTTON_HEIGHT = 20
local BUTTON_WIDTH = 76
local WIDE_BUTTON_WIDTH = 100
local DESTRUCTIVE_GAP = 16 -- extra space before Delete, vs. 4px between safe actions

local canvas
local rowPool = {}
local activeRows = {}
local draggedContext
-- The node id whose row keeps its hover-only actions showing regardless of
-- the cursor, for the first-run editor tour (see PinRowActions).
local pinnedRowId

-- Pure: given the current top-to-bottom on-screen rects ({top=, bottom=},
-- in the same coordinate space as :GetTop()/:GetBottom()) of a row's
-- siblings, the 1-based index of the row being dragged within that list,
-- and the cursor's Y position at drop, returns the index CS.Tree.Reorder
-- should move it to. Kept pure and separate from the actual frames so the
-- drag math - the fiddly part - can be unit tested without a real client.
function CS.Options.FindDropIndex(rects, draggedIndex, dropY)
    local index = 1
    for i, rect in ipairs(rects) do
        if i ~= draggedIndex then
            local mid = (rect.top + rect.bottom) / 2
            if dropY < mid then
                index = index + 1
            end
        end
    end
    return index
end

-- Shows a row's hover-only widgets while the cursor is over the row or one
-- of its buttons, or while the row is pinned.
local function applyHoverState(row)
    local shown = (row.nodeId ~= nil and row.nodeId == pinnedRowId)
        or row:IsMouseOver()
        or row.button1:IsMouseOver()
        or row.button2:IsMouseOver()
        or row.button3:IsMouseOver()
    for _, widget in ipairs(row.hoverWidgets or {}) do
        widget:SetShown(shown)
    end
end

local function acquireRow()
    local row = table.remove(rowPool)
    if not row then
        row = CreateFrame("Frame", nil, canvas.rowContainer)
        row:SetHeight(ROW_HEIGHT)
        row:EnableMouse(true)
        row:RegisterForDrag("LeftButton")

        -- A fixed left-hand gutter for the drag cue, kept visually
        -- separate from the label text (rather than embedded as a text
        -- prefix) so it reads as a control, not part of the sentence.
        row.dragHandle = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.dragHandle:SetPoint("LEFT", row, "LEFT", 2, 0)
        row.dragHandle:SetText("::")
        row.dragHandle:SetTextColor(0.45, 0.55, 0.65)

        -- Standard Blizzard disclosure icon instead of a "+"/"-" text
        -- prefix, matching how the rest of the default UI shows
        -- collapsible sections.
        row.collapseIcon = CreateFrame("Button", nil, row)
        row.collapseIcon:SetSize(14, 14)
        row.collapseIcon:SetPoint("LEFT", row.dragHandle, "RIGHT", 4, 0)
        row.collapseIcon:SetHighlightTexture("Interface/Buttons/UI-PlusButton-Hilight", "ADD")

        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.label:SetJustifyH("LEFT")

        row.button1 = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.button1:SetHeight(BUTTON_HEIGHT)
        row.button2 = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.button2:SetHeight(BUTTON_HEIGHT)
        row.button3 = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.button3:SetHeight(BUTTON_HEIGHT)

        row:SetScript("OnDragStart", function()
            draggedContext = row.dragContext
        end)
        row:SetScript("OnDragStop", function()
            CS.Options.HandleDragStop()
        end)

        -- Action buttons and the drag handle stay hidden until the row is
        -- hovered - showing every row's full button set at once was an
        -- overwhelming wall of identical buttons; revealing them only for
        -- the row under the cursor keeps the list scannable while still
        -- making every control fully discoverable and reachable, not
        -- hidden behind a keyboard shortcut or menu.
        --
        -- Hooking the SAME update onto every button's own OnEnter/OnLeave
        -- (not just the row's) matters: once a button is shown, moving the
        -- cursor onto it makes it the topmost frame at that pixel, so the
        -- row itself fires OnLeave even though the cursor never actually
        -- left the row's area. Without this, that OnLeave hides the
        -- buttons, which puts the cursor back over the bare row, which
        -- fires OnEnter again, showing them again - a rapid show/hide
        -- flicker the instant you try to actually reach a button.
        -- :IsMouseOver() on the whole group is checked fresh each time
        -- instead of trusting which single widget's event just fired.
        local function updateHover()
            applyHoverState(row)
        end
        row:SetScript("OnEnter", updateHover)
        row:SetScript("OnLeave", updateHover)
        row.button1:HookScript("OnEnter", updateHover)
        row.button1:HookScript("OnLeave", updateHover)
        row.button2:HookScript("OnEnter", updateHover)
        row.button2:HookScript("OnLeave", updateHover)
        row.button3:HookScript("OnEnter", updateHover)
        row.button3:HookScript("OnLeave", updateHover)
    end

    row:ClearAllPoints()
    row.dragHandle:Hide()
    row.collapseIcon:Hide()
    row.collapseIcon:SetScript("OnClick", nil)
    row.label:ClearAllPoints()
    row.label:SetFontObject("GameFontHighlight")
    row.label:SetTextColor(1, 1, 1)
    row.button1:ClearAllPoints()
    row.button1:Hide()
    row.button1:SetScript("OnClick", nil)
    row.button2:ClearAllPoints()
    row.button2:Hide()
    row.button2:SetScript("OnClick", nil)
    row.button3:ClearAllPoints()
    row.button3:Hide()
    row.button3:SetScript("OnClick", nil)
    row.dragContext = nil
    row.nodeId = nil
    row.kind = nil
    row.hoverWidgets = {}
    row:SetScript("OnMouseUp", nil)
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

local function layoutCategoryRow(row, category, y)
    row:SetPoint("TOPLEFT", canvas.rowContainer, "TOPLEFT", 0, y)
    row:SetPoint("RIGHT", canvas.rowContainer, "RIGHT", 0, 0)

    row.button1:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.button1:SetWidth(BUTTON_WIDTH)
    row.button1:SetText(CS.Data.L.ui_delete)
    row.button1:SetScript("OnClick", function()
        StaticPopup_Show("CAMPFIRESTOKERS_DELETE_CATEGORY_CONFIRM", category.name, nil, {
            categoryId = category.id,
        })
    end)

    -- Extra gap before Delete (vs. the tight 4px between Rename/Add
    -- Phrase) so this destructive action isn't immediately adjacent to
    -- safe ones - reduces the cost of a misclick.
    row.button2:SetPoint("RIGHT", row.button1, "LEFT", -DESTRUCTIVE_GAP, 0)
    row.button2:SetWidth(BUTTON_WIDTH)
    row.button2:SetText(CS.Data.L.ui_rename)
    row.button2:SetScript("OnClick", function()
        CS.UI.PromptForText({
            title = CS.Data.L.ui_rename_category_prompt,
            initialText = category.name,
            onAccept = function(text)
                if text == "" then
                    return false, CS.Data.L.ui_error_empty
                end
                CS.Tree.RenameCategory(CampfireStokersDB, category.id, text)
                CS.Options.Refresh()
                CS.UI.Refresh()
                return true
            end,
        })
    end)

    row.button3:SetPoint("RIGHT", row.button2, "LEFT", -4, 0)
    row.button3:SetWidth(WIDE_BUTTON_WIDTH)
    row.button3:SetText(CS.Data.L.ui_add_phrase)
    row.button3:SetScript("OnClick", function()
        CS.UI.PromptForText({
            title = CS.Data.L.ui_new_phrase_prompt,
            initialText = "",
            charLimit = 255,
            onAccept = function(text)
                if text == "" then
                    return false, CS.Data.L.ui_error_empty
                end
                local phrase, err = CS.Tree.AddPhrase(CampfireStokersDB, category.id, text)
                if not phrase then
                    return false, err
                end
                CS.Options.Refresh()
                CS.UI.Refresh()
                return true
            end,
        })
    end)

    local collapsed = CampfireStokersDB.collapsedCategories[category.id] == true
    row.collapseIcon:Show()
    row.collapseIcon:SetNormalTexture(
        collapsed and "Interface/Buttons/UI-PlusButton-Up" or "Interface/Buttons/UI-MinusButton-Up"
    )
    row.collapseIcon:SetPushedTexture(
        collapsed and "Interface/Buttons/UI-PlusButton-Down" or "Interface/Buttons/UI-MinusButton-Down"
    )
    row.collapseIcon:SetScript("OnClick", function()
        if collapsed then
            CampfireStokersDB.collapsedCategories[category.id] = nil
        else
            CampfireStokersDB.collapsedCategories[category.id] = true
        end
        CS.Options.Refresh()
    end)

    row.label:SetPoint("LEFT", row.collapseIcon, "RIGHT", 4, 0)
    row.label:SetPoint("RIGHT", row.button3, "LEFT", -8, 0)
    row.label:SetFontObject("GameFontNormalLarge")
    row.label:SetTextColor(1, 0.82, 0) -- WoW's standard header gold
    row.label:SetText(category.name)
    row.hoverWidgets = { row.dragHandle, row.button1, row.button2, row.button3 }
    row.nodeId = category.id
    row.kind = "category"
    row:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then
            if collapsed then
                CampfireStokersDB.collapsedCategories[category.id] = nil
            else
                CampfireStokersDB.collapsedCategories[category.id] = true
            end
            CS.Options.Refresh()
        end
    end)
end

local function layoutPhraseRow(row, phrase, y)
    row:SetPoint("TOPLEFT", canvas.rowContainer, "TOPLEFT", ROW_INDENT, y)
    row:SetPoint("RIGHT", canvas.rowContainer, "RIGHT", 0, 0)

    row.button1:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.button1:SetWidth(BUTTON_WIDTH)
    row.button1:SetText(CS.Data.L.ui_delete)
    row.button1:SetScript("OnClick", function()
        CS.Tree.Delete(CampfireStokersDB, phrase.id)
        CS.Options.Refresh()
        CS.UI.Refresh()
    end)

    -- Same extra-gap treatment as the category row's Delete; an individual
    -- phrase is lower blast-radius than a whole category, so this gets
    -- spacing rather than a confirmation popup, to keep routine cleanup
    -- from requiring a dialog click every time.
    row.button2:SetPoint("RIGHT", row.button1, "LEFT", -DESTRUCTIVE_GAP, 0)
    row.button2:SetWidth(BUTTON_WIDTH)
    row.button2:SetText(CS.Data.L.ui_edit)
    row.button2:SetScript("OnClick", function()
        CS.UI.PromptForText({
            title = CS.Data.L.ui_edit_phrase_prompt,
            initialText = phrase.text,
            charLimit = 255,
            onAccept = function(text)
                if text == "" then
                    return false, CS.Data.L.ui_error_empty
                end
                local ok, err = CS.Tree.EditPhraseText(CampfireStokersDB, phrase.id, text)
                if not ok then
                    return false, err
                end
                CS.Options.Refresh()
                CS.UI.Refresh()
                return true
            end,
        })
    end)

    row.label:SetPoint("LEFT", row.dragHandle, "RIGHT", 4, 0)
    row.label:SetPoint("RIGHT", row.button2, "LEFT", -8, 0)
    row.label:SetText(phrase.text)
    local sendable = CS.Send.Classify(phrase.text, { sendMode = CampfireStokersDB.sendMode }).kind ~= "rejected"
    if not sendable then
        row.label:SetTextColor(0.7, 0.35, 0.35)
    end
    row.hoverWidgets = { row.dragHandle, row.button1, row.button2 }
    row.nodeId = phrase.id
    row.kind = "phrase"
end

function CS.Options.HandleDragStop()
    if not draggedContext then
        return
    end
    local siblings = draggedContext.siblings
    local rects = {}
    local draggedIndex
    for i, sibling in ipairs(siblings) do
        rects[i] = { top = sibling.row:GetTop(), bottom = sibling.row:GetBottom() }
        if sibling.id == draggedContext.id then
            draggedIndex = i
        end
    end
    draggedContext = nil
    if not draggedIndex then
        return
    end

    local _, cursorY = GetCursorPosition()
    cursorY = cursorY / UIParent:GetEffectiveScale()
    local newIndex = CS.Options.FindDropIndex(rects, draggedIndex, cursorY)

    CS.Tree.Reorder(CampfireStokersDB, siblings[draggedIndex].id, newIndex)
    CS.Options.Refresh()
    CS.UI.Refresh()
end

function CS.Options.Refresh()
    if not canvas then
        return
    end

    -- Re-synced every refresh rather than set once at creation: the
    -- Settings system may not have sized canvas.scrollFrame yet the first
    -- time CreateCanvas() runs, and SetWidth freezes a value rather than
    -- tracking it live, so a one-time set could permanently pin this to 0.
    canvas.rowContainer:SetWidth(canvas.scrollFrame:GetWidth())

    releaseRows()

    local categoryRows = {}
    local y = 0

    for categoryIndex, category in ipairs(CampfireStokersDB.tree) do
        if categoryIndex > 1 then
            y = y - CATEGORY_GAP
        end

        local headerRow = acquireRow()
        layoutCategoryRow(headerRow, category, y)
        table.insert(activeRows, headerRow)
        table.insert(categoryRows, { id = category.id, row = headerRow })
        y = y - ROW_HEIGHT

        if CampfireStokersDB.collapsedCategories[category.id] ~= true then
            local phraseRows = {}
            for _, phrase in ipairs(category.children) do
                local phraseRow = acquireRow()
                layoutPhraseRow(phraseRow, phrase, y)
                table.insert(activeRows, phraseRow)
                table.insert(phraseRows, { id = phrase.id, row = phraseRow })
                y = y - ROW_HEIGHT
            end
            for _, entry in ipairs(phraseRows) do
                entry.row.dragContext = { id = entry.id, siblings = phraseRows }
            end
        end
    end

    for _, entry in ipairs(categoryRows) do
        entry.row.dragContext = { id = entry.id, siblings = categoryRows }
    end

    canvas.rowContainer:SetHeight(math.max(-y, ROW_HEIGHT))

    for _, row in ipairs(activeRows) do
        applyHoverState(row)
    end
end

-- Keeps the row for node `rowId` showing its hover-only actions (Rename /
-- Add Phrase / Delete, or Edit / Delete, and the drag handle) while `on`,
-- so a tour step can point at them. One row at a time; survives Refresh.
function CS.Options.PinRowActions(rowId, on)
    if on then
        pinnedRowId = rowId
    elseif pinnedRowId == rowId then
        pinnedRowId = nil
    end
    for _, row in ipairs(activeRows) do
        applyHoverState(row)
    end
end

function CS.Options.IsShown()
    return canvas ~= nil and canvas:IsVisible()
end

local function firstRowOfKind(kind)
    for _, row in ipairs(activeRows) do
        if row.kind == kind and row:IsShown() then
            return row
        end
    end
end

local TOUR_ROW_ANCHORS = {
    categoryActions = { kind = "category", region = "button2" }, -- Rename, the middle action
    phraseActions = { kind = "phrase", region = "button2" }, -- Edit
    dragHandle = { kind = "phrase", region = "dragHandle" },
}

-- The editor regions the first-run tour points at (see Tutorial.lua), or
-- nil when the editor isn't showing or there's no such row. `name`:
-- addCategory, or one of TOUR_ROW_ANCHORS. With `pin`, the row is pinned
-- (PinRowActions) so its hover-only target is visible, and the second
-- return unpins it; without, nothing changes - for checking whether a
-- step applies.
function CS.Options.GetTourAnchor(name, pin)
    if not CS.Options.IsShown() then
        return nil
    end
    if name == "addCategory" then
        return canvas.addCategoryButton
    end
    local spec = TOUR_ROW_ANCHORS[name]
    local row = spec and firstRowOfKind(spec.kind)
    if not row then
        return nil
    end
    if not pin then
        return row
    end
    local rowId = row.nodeId
    CS.Options.PinRowActions(rowId, true)
    return row[spec.region], function()
        CS.Options.PinRowActions(rowId, false)
    end
end

-- Opens Settings at this add-on's editor. Returns whether it asked the
-- Settings panel to open. Not attempted in combat, where opening Blizzard's
-- Settings panel from add-on code isn't safe to assume.
function CS.Options.Open()
    if not (canvas and canvas.category) or InCombatLockdown() then
        return false
    end
    local ok, err = pcall(Settings.OpenToCategory, canvas.category:GetID())
    if not ok then
        CS.Debug("Settings.OpenToCategory failed: " .. tostring(err))
    end
    return ok
end

local function registerPopups()
    -- Restore Missing Defaults is effectively a gentler subtype of Reset
    -- (additive only, vs. replacing everything), so it lives as a third
    -- button on the same confirmation dialog rather than as its own
    -- separate top-level button. button3's handler is OnAlt - unconfirmed
    -- in-client on this build (see docs/decision-log.md): this dialog
    -- template already deviated from the classic one once (the EditBox
    -- field rename), so this 3-button wiring needs verifying too.
    StaticPopupDialogs["CAMPFIRESTOKERS_RESET_CONFIRM"] = {
        text = CS.Data.L.ui_reset_confirm,
        button1 = CS.Data.L.ui_confirm,
        button2 = CS.Data.L.ui_cancel,
        button3 = CS.Data.L.ui_restore_defaults,
        OnAccept = function()
            CS.Tree.ResetToDefaults(CampfireStokersDB)
            CS.Options.Refresh()
            CS.UI.Refresh()
        end,
        OnAlt = function()
            CS.Tree.RestoreMissingDefaults(CampfireStokersDB)
            CS.Options.Refresh()
            CS.UI.Refresh()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }

    StaticPopupDialogs["CAMPFIRESTOKERS_DELETE_CATEGORY_CONFIRM"] = {
        text = CS.Data.L.ui_delete_category_confirm,
        button1 = CS.Data.L.ui_delete,
        button2 = CS.Data.L.ui_cancel,
        OnAccept = function(_, data)
            CS.Tree.Delete(CampfireStokersDB, data.categoryId)
            CS.Options.Refresh()
            CS.UI.Refresh()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
end

-- Creates the custom canvas and registers it under Settings > AddOns.
-- Called once, from Core.lua's ADDON_LOADED handler. Every action here
-- mutates CampfireStokersDB immediately and calls Refresh in place - no
-- ReloadUI, no pending-changes/Okay-Cancel flow.
function CS.Options.CreateCanvas()
    registerPopups()

    canvas = CreateFrame("Frame", "CampfireStokersOptionsCanvas", UIParent)
    canvas.name = CS.Data.L.ui_options_title
    -- A freshly created frame starts shown. Without this, the Settings
    -- system's later :Show() when you navigate here is a no-op (it's
    -- already shown), so OnShow below never fires and Refresh() never
    -- runs - which is exactly why the row list rendered empty even though
    -- CampfireStokersDB.tree already had the default categories in it.
    canvas:Hide()

    local title = canvas:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", canvas, "TOPLEFT", 16, -16)
    title:SetText(CS.Data.L.ui_options_title)

    local styleLabel = canvas:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    styleLabel:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -16)
    styleLabel:SetText(CS.Data.L.ui_panel_style)

    -- The modern retail dropdown (Blizzard_Menu's WowStyle1DropdownTemplate
    -- and SetupMenu), which replaced UIDropDownMenu in retail. Not yet
    -- confirmed on Forever, so it's pcall-wrapped like the Settings
    -- registration below: a missing template throws from CreateFrame, and
    -- that shouldn't take down the rest of the options panel.
    local styleOk, styleErr = pcall(function()
        local styleDropdown = CreateFrame("DropdownButton", nil, canvas, "WowStyle1DropdownTemplate")
        styleDropdown:SetWidth(200)
        styleDropdown:SetPoint("LEFT", styleLabel, "RIGHT", 8, 0)
        styleDropdown:SetupMenu(function(_, rootDescription)
            for _, style in ipairs(CS.UI.STYLES) do
                rootDescription:CreateRadio(
                    CS.Data.L[style.labelKey],
                    function()
                        return CampfireStokersDB.panelStyle == style.id
                    end,
                    function()
                        CampfireStokersDB.panelStyle = style.id
                        CS.UI.Refresh()
                    end
                )
            end
        end)
    end)
    if not styleOk then
        print("Campfire Stokers: could not create the panel style dropdown (" .. tostring(styleErr) .. ").")
    end

    local addCategoryButton = CreateFrame("Button", nil, canvas, "UIPanelButtonTemplate")
    canvas.addCategoryButton = addCategoryButton
    addCategoryButton:SetSize(120, 22)
    addCategoryButton:SetPoint("TOPLEFT", styleLabel, "BOTTOMLEFT", 0, -20)
    addCategoryButton:SetText(CS.Data.L.ui_add_category)
    addCategoryButton:SetScript("OnClick", function()
        CS.UI.PromptForText({
            title = CS.Data.L.ui_new_category_prompt,
            initialText = "",
            onAccept = function(text)
                if text == "" then
                    return false, CS.Data.L.ui_error_empty
                end
                CS.Tree.AddCategory(CampfireStokersDB, text)
                CS.Options.Refresh()
                CS.UI.Refresh()
                return true
            end,
        })
    end)

    -- Low priority relative to everything above (it's a rare, destructive
    -- escape hatch, not a day-to-day action), so it lives at the bottom of
    -- the window rather than competing with Add Category up top.
    local resetButton = CreateFrame("Button", nil, canvas, "UIPanelButtonTemplate")
    resetButton:SetSize(140, 22)
    resetButton:SetPoint("BOTTOMLEFT", canvas, "BOTTOMLEFT", 16, 16)
    resetButton:SetText(CS.Data.L.ui_reset_defaults)
    resetButton:SetScript("OnClick", function()
        StaticPopup_Show("CAMPFIRESTOKERS_RESET_CONFIRM")
    end)
    resetButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(CS.Data.L.ui_reset_defaults)
        GameTooltip:AddLine(CS.Data.L.ui_reset_tooltip, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    resetButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local replayButton = CreateFrame("Button", nil, canvas, "UIPanelButtonTemplate")
    replayButton:SetSize(140, 22)
    replayButton:SetPoint("LEFT", resetButton, "RIGHT", 8, 0)
    replayButton:SetText(CS.Data.L.ui_replay_tutorial)
    replayButton:SetScript("OnClick", function()
        CS.Tutorial.Replay()
    end)

    canvas.scrollFrame = CreateFrame("ScrollFrame", nil, canvas, "UIPanelScrollFrameTemplate")
    canvas.scrollFrame:SetPoint("TOPLEFT", addCategoryButton, "BOTTOMLEFT", 0, -16)
    canvas.scrollFrame:SetPoint("RIGHT", canvas, "RIGHT", -32, 0)
    canvas.scrollFrame:SetPoint("BOTTOM", resetButton, "TOP", 0, 16)

    canvas.rowContainer = CreateFrame("Frame", nil, canvas.scrollFrame)
    canvas.rowContainer:SetSize(1, 1)
    canvas.scrollFrame:SetScrollChild(canvas.rowContainer)

    canvas:SetScript("OnShow", function()
        CS.Options.Refresh()
        -- A pending editor tour starts here, however the editor was
        -- opened ("Make it yours", the panel tour's offer, or by hand
        -- after either couldn't open Settings itself).
        CS.Tutorial.OnEditorShown()
    end)

    -- Settings.RegisterCanvasLayoutCategory is a newer retail API; Forever's
    -- exact signature isn't confirmed (see AGENTS.md's TOC gate/recency
    -- rule - this is exactly the kind of surface that needs in-client
    -- verification, not an assumption). pcall-wrapped so a mismatch here
    -- doesn't take down the rest of the add-on.
    local ok, err = pcall(function()
        -- The category keeps the numeric ID Blizzard assigns it: Forever's
        -- Settings.OpenToCategory passes it to C_SettingsUtil.
        -- OpenSettingsPanel, which accepts only a number (Gethe/wow-ui-source,
        -- forever branch, SettingsUtilDocumentation.lua). Overwriting it with
        -- a string, as this once did, made opening the editor from code throw.
        local category = Settings.RegisterCanvasLayoutCategory(canvas, canvas.name)
        Settings.RegisterAddOnCategory(category)
        canvas.category = category
    end)
    if not ok then
        print("Campfire Stokers: could not register the options panel (" .. tostring(err) .. ").")
    end

    -- Don't rely solely on OnShow to populate the row list the first time -
    -- matches UI.lua's CreatePanel, which does the same for the same
    -- reason: an eager Refresh() here means the content exists regardless
    -- of whether the Settings system's show/hide behavior for canvas
    -- categories works the way this code assumes.
    CS.Options.Refresh()

    return canvas
end
