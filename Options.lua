local CS = select(2, ...)

---@class CampfireStokersOptions
CS.Options = CS.Options or {}

local ROW_HEIGHT = 24
local ROW_INDENT = 16
local BUTTON_HEIGHT = 20

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

        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
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
    end

    row:ClearAllPoints()
    row.label:ClearAllPoints()
    row.button1:ClearAllPoints()
    row.button1:Hide()
    row.button1:SetScript("OnClick", nil)
    row.button2:ClearAllPoints()
    row.button2:Hide()
    row.button2:SetScript("OnClick", nil)
    row.button3:ClearAllPoints()
    row.button3:Hide()
    row.button3:SetScript("OnClick", nil)
    row.label:SetTextColor(1, 1, 1)
    row.dragContext = nil
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

local function promptForText(promptText, initialText, onAccept)
    StaticPopup_Show("CAMPFIRESTOKERS_TEXT_INPUT", promptText, nil, {
        initialText = initialText,
        onAccept = onAccept,
    })
end

local function layoutCategoryRow(row, category, y)
    row:SetPoint("TOPLEFT", canvas.rowContainer, "TOPLEFT", 0, y)
    row:SetPoint("RIGHT", canvas.rowContainer, "RIGHT", 0, 0)

    row.button1:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.button1:SetWidth(70)
    row.button1:SetText(CS.Data.L.ui_delete)
    row.button1:Show()
    row.button1:SetScript("OnClick", function()
        CS.Tree.Delete(CampfireStokersDB, category.id)
        CS.Options.Refresh()
        CS.UI.Refresh()
    end)

    row.button2:SetPoint("RIGHT", row.button1, "LEFT", -4, 0)
    row.button2:SetWidth(70)
    row.button2:SetText(CS.Data.L.ui_rename)
    row.button2:Show()
    row.button2:SetScript("OnClick", function()
        promptForText(CS.Data.L.ui_rename_category_prompt, category.name, function(text)
            if text ~= "" then
                CS.Tree.RenameCategory(CampfireStokersDB, category.id, text)
                CS.Options.Refresh()
                CS.UI.Refresh()
            end
        end)
    end)

    row.button3:SetPoint("RIGHT", row.button2, "LEFT", -4, 0)
    row.button3:SetWidth(90)
    row.button3:SetText(CS.Data.L.ui_add_phrase)
    row.button3:Show()
    row.button3:SetScript("OnClick", function()
        promptForText(CS.Data.L.ui_new_phrase_prompt, "", function(text)
            if text == "" then
                return
            end
            local phrase, err = CS.Tree.AddPhrase(CampfireStokersDB, category.id, text)
            if not phrase then
                print("Campfire Stokers: " .. err)
                return
            end
            CS.Options.Refresh()
            CS.UI.Refresh()
        end)
    end)

    row.label:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.label:SetPoint("RIGHT", row.button3, "LEFT", -8, 0)
    local collapsed = CampfireStokersDB.collapsedCategories[category.id] == true
    row.label:SetText(":: " .. (collapsed and "+ " or "- ") .. category.name)
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
    row.button1:SetWidth(70)
    row.button1:SetText(CS.Data.L.ui_delete)
    row.button1:Show()
    row.button1:SetScript("OnClick", function()
        CS.Tree.Delete(CampfireStokersDB, phrase.id)
        CS.Options.Refresh()
        CS.UI.Refresh()
    end)

    row.button2:SetPoint("RIGHT", row.button1, "LEFT", -4, 0)
    row.button2:SetWidth(70)
    row.button2:SetText(CS.Data.L.ui_edit)
    row.button2:Show()
    row.button2:SetScript("OnClick", function()
        promptForText(CS.Data.L.ui_edit_phrase_prompt, phrase.text, function(text)
            if text == "" then
                return
            end
            local ok, err = CS.Tree.EditPhraseText(CampfireStokersDB, phrase.id, text)
            if not ok then
                print("Campfire Stokers: " .. err)
                return
            end
            CS.Options.Refresh()
            CS.UI.Refresh()
        end)
    end)

    row.label:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.label:SetPoint("RIGHT", row.button2, "LEFT", -8, 0)
    row.label:SetText(":: " .. phrase.text)
    local sendable = CS.Send.Classify(phrase.text, { sendMode = CampfireStokersDB.sendMode }).kind ~= "rejected"
    if not sendable then
        row.label:SetTextColor(0.7, 0.35, 0.35)
    end
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

    releaseRows()

    local categoryRows = {}
    local y = 0

    for _, category in ipairs(CampfireStokersDB.tree) do
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
    StaticPopupDialogs["CAMPFIRESTOKERS_TEXT_INPUT"] = {
        text = "%s",
        button1 = CS.Data.L.ui_accept,
        button2 = CS.Data.L.ui_cancel,
        hasEditBox = true,
        OnAccept = function(self, data)
            if data.onAccept then
                data.onAccept(self.editBox:GetText())
            end
        end,
        EditBoxOnEnterPressed = function(self)
            local parent = self:GetParent()
            if parent.data and parent.data.onAccept then
                parent.data.onAccept(parent.editBox:GetText())
            end
            parent:Hide()
        end,
        OnShow = function(self, data)
            self.editBox:SetText(data.initialText or "")
            self.editBox:HighlightText()
            self.editBox:SetFocus()
        end,
        EditBoxOnEscapePressed = function(self)
            self:GetParent():Hide()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }

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
end

-- Creates the custom canvas and registers it under Settings > AddOns.
-- Called once, from Core.lua's ADDON_LOADED handler. Every action here
-- mutates CampfireStokersDB immediately and calls Refresh in place - no
-- ReloadUI, no pending-changes/Okay-Cancel flow.
function CS.Options.CreateCanvas()
    registerPopups()

    canvas = CreateFrame("Frame", "CampfireStokersOptionsCanvas", UIParent)
    canvas.name = CS.Data.L.ui_options_title

    local title = canvas:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", canvas, "TOPLEFT", 16, -16)
    title:SetText(CS.Data.L.ui_options_title)

    local addCategoryButton = CreateFrame("Button", nil, canvas, "UIPanelButtonTemplate")
    addCategoryButton:SetSize(120, 22)
    addCategoryButton:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    addCategoryButton:SetText(CS.Data.L.ui_add_category)
    addCategoryButton:SetScript("OnClick", function()
        promptForText(CS.Data.L.ui_new_category_prompt, "", function(text)
            if text ~= "" then
                CS.Tree.AddCategory(CampfireStokersDB, text)
                CS.Options.Refresh()
                CS.UI.Refresh()
            end
        end)
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
    canvas.rowContainer:SetWidth(canvas.scrollFrame:GetWidth())

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

    return canvas
end
