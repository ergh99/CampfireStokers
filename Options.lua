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
            local hovered = row:IsMouseOver()
                or row.button1:IsMouseOver()
                or row.button2:IsMouseOver()
                or row.button3:IsMouseOver()
            for _, widget in ipairs(row.hoverWidgets or {}) do
                if hovered then
                    widget:Show()
                else
                    widget:Hide()
                end
            end
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
end

local function registerPopups()
    StaticPopupDialogs["CAMPFIRESTOKERS_RESET_CONFIRM"] = {
        text = CS.Data.L.ui_reset_confirm,
        button1 = CS.Data.L.ui_reset_defaults,
        button2 = CS.Data.L.ui_cancel,
        OnAccept = function()
            CS.Tree.ResetToDefaults(CampfireStokersDB)
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

    local addCategoryButton = CreateFrame("Button", nil, canvas, "UIPanelButtonTemplate")
    addCategoryButton:SetSize(120, 22)
    addCategoryButton:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
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

    local resetButton = CreateFrame("Button", nil, canvas, "UIPanelButtonTemplate")
    resetButton:SetSize(140, 22)
    resetButton:SetPoint("LEFT", addCategoryButton, "RIGHT", 8, 0)
    resetButton:SetText(CS.Data.L.ui_reset_defaults)
    resetButton:SetScript("OnClick", function()
        StaticPopup_Show("CAMPFIRESTOKERS_RESET_CONFIRM")
    end)

    local restoreButton = CreateFrame("Button", nil, canvas, "UIPanelButtonTemplate")
    restoreButton:SetSize(170, 22)
    restoreButton:SetPoint("LEFT", resetButton, "RIGHT", 8, 0)
    restoreButton:SetText(CS.Data.L.ui_restore_defaults)
    restoreButton:SetScript("OnClick", function()
        CS.Tree.RestoreMissingDefaults(CampfireStokersDB)
        CS.Options.Refresh()
        CS.UI.Refresh()
    end)

    local delayLabel = canvas:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    delayLabel:SetPoint("TOPLEFT", addCategoryButton, "BOTTOMLEFT", 0, -16)
    delayLabel:SetText(CS.Data.L.ui_auto_open_delay_label)

    local delayEditBox = CreateFrame("EditBox", nil, canvas, "InputBoxTemplate")
    delayEditBox:SetSize(60, 20)
    delayEditBox:SetPoint("LEFT", delayLabel, "RIGHT", 8, 0)
    delayEditBox:SetAutoFocus(false)
    delayEditBox:SetNumeric(true)
    local function commitDelay()
        local value = tonumber(delayEditBox:GetText())
        if value and value >= 0 then
            CampfireStokersDB.autoOpenDelay = math.floor(value)
        end
        delayEditBox:SetText(tostring(CampfireStokersDB.autoOpenDelay))
        delayEditBox:ClearFocus()
    end
    delayEditBox:SetScript("OnEnterPressed", commitDelay)
    delayEditBox:SetScript("OnEditFocusLost", commitDelay)
    canvas.delayEditBox = delayEditBox

    canvas.scrollFrame = CreateFrame("ScrollFrame", nil, canvas, "UIPanelScrollFrameTemplate")
    canvas.scrollFrame:SetPoint("TOPLEFT", delayLabel, "BOTTOMLEFT", 0, -16)
    canvas.scrollFrame:SetPoint("BOTTOMRIGHT", canvas, "BOTTOMRIGHT", -32, 16)

    canvas.rowContainer = CreateFrame("Frame", nil, canvas.scrollFrame)
    canvas.rowContainer:SetSize(1, 1)
    canvas.scrollFrame:SetScrollChild(canvas.rowContainer)

    canvas:SetScript("OnShow", function()
        canvas.delayEditBox:SetText(tostring(CampfireStokersDB.autoOpenDelay))
        CS.Options.Refresh()
    end)

    -- Settings.RegisterCanvasLayoutCategory is a newer retail API; Forever's
    -- exact signature isn't confirmed (see AGENTS.md's TOC gate/recency
    -- rule - this is exactly the kind of surface that needs in-client
    -- verification, not an assumption). pcall-wrapped so a mismatch here
    -- doesn't take down the rest of the add-on.
    local ok, err = pcall(function()
        local category = Settings.RegisterCanvasLayoutCategory(canvas, canvas.name)
        category.ID = "CampfireStokers"
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
