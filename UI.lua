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
-- The glow texture has wide transparent padding; 110 puts its visible
-- ring on a 64px button's edge (confirmed in-client, Round 7 of
-- docs/profession-button-appearance-findings.md).
local PROFESSION_GLOW_SIZE = 110
local PROFESSION_ICON_GAP = 8
-- How long after a Use click to read the cooldown back, so the client has
-- had time to start it.
local USE_COOLDOWN_CHECK_DELAY_SECONDS = 1
local PROFESSION_BLOCK_SIDE_PADDING = 8
local SAY_YELL_HEIGHT = 20
local SAY_YELL_BOTTOM_GAP = 10
-- The campfire style's title area (see LOOKS for each style's own).
local CAMPFIRE_TITLE_AREA_HEIGHT = 46
local TITLE_ICON_SIZE = 28
local TITLE_ICON_TEXT_GAP = 10
-- Same glow texture and padding ratio as PROFESSION_GLOW_SIZE (110/64).
local TITLE_GLOW_SIZE = 48
-- Each flicker step fades to a random brightness over a random short time.
local FLICKER_MIN_ALPHA = 0.35
local FLICKER_MIN_SECONDS = 0.06
local FLICKER_MAX_SECONDS = 0.28
local DIVIDER_INSET = 10
-- Blizzard's own achievement-frame border (BACKDROP_ACHIEVEMENTS_0_64 in
-- Blizzard_SharedXML/Backdrop.lua), confirmed rendering in-client via the
-- since-removed `/campfire try border`. At edge size 64 its visible wood
-- is ~22 units thick (measured from an in-client capture; Blizzard's
-- achievement frame likewise insets its content 21), so the border frame
-- sits that far outside the panel: the wood surrounds the content where
-- the old thin border was, instead of covering it.
local WOOD_BORDER = {
    edgeFile = "Interface/AchievementFrame/UI-Achievement-WoodBorder",
    edgeSize = 64,
    tileEdge = true,
}
local WOOD_OUTSET = 22
-- The texture itself has a thin gray metal rim around the wood's outer
-- edge (~4 units, measured from an in-client capture). It's trimmed off
-- by clipping the border to this much less than WOOD_OUTSET.
local WOOD_RIM = 4
local WOOD_VISIBLE_OUTSET = WOOD_OUTSET - WOOD_RIM
-- The rim bevels diagonally across each corner, so a sliver of it (~2.5
-- units, measured in-client) survives the straight clip there. A small
-- square matching the near-black corner wood covers it.
local WOOD_CORNER_CAP = 3
-- The background reaches this far under the wood so no gap shows at its
-- inner edge.
local WOOD_UNDERLAP = 4
local CLOSE_BUTTON_EXTRA_PADDING = 2

-- Warm "campfire" theme on stock Blizzard textures, tinted rather than
-- replaced so the panel still sits comfortably beside the default UI.
-- Each style's look: its colors, plus the few layout values that differ
-- between styles. `look` (below) is whichever one is active.
local LOOKS = {
    campfire = {
        -- Title area, then the profession button block (if any), THEN
        -- Say/Yell, then the phrase tree - campfire feature requests always yell
        -- regardless of the Say/Yell toggle, so they sit above it, not
        -- sandwiched between it and the phrases it actually controls
        -- (reported as confusing placement during in-client testing).
        titleAreaHeight = CAMPFIRE_TITLE_AREA_HEIGHT,
        -- Space above and below the profession button block.
        professionBlockGap = 8,
        background = { 0.165, 0.102, 0.063, 1 }, -- warm charcoal-brown #2A1A10
        -- Multiplies the parchment (mean color ~155,110,46 measured from an
        -- in-client capture) down to ~52,34,20, keeping its grain and stains.
        backgroundTexture = { 0.34, 0.31, 0.43 },
        divider = { 0.549, 0.376, 0.224, 0.6 }, -- worn leather #8C6039
        woodCorner = { 0.03, 0.02, 0.01, 1 }, -- the wood border's dark corners
        header = { 0.910, 0.514, 0.227 }, -- ember orange #E8833A
        text = { 0.902, 0.835, 0.690 }, -- parchment #E6D5B0
        textNeedsTarget = { 0.55, 0.50, 0.42 }, -- dimmed parchment
        textFlagged = { 0.7, 0.35, 0.35 },
        rowHover = { 0.910, 0.514, 0.227, 0.35 },
        rowFlash = { 0.910, 0.514, 0.227, 0.8 },
    },
    -- Matches the default UI's own frames (the Auction House and profession
    -- windows): Blizzard's portrait frame for the border, title bar, round
    -- portrait and close button, standard gold headers on a dark bar with
    -- the collapse control on the right like the profession list's section
    -- headers, and white entries with a plain white hover.
    forever = {
        -- Just below the template's title bar, so the profession icons sit
        -- evenly between it and the divider below them.
        titleAreaHeight = 22,
        professionBlockGap = 12,
        -- The round portrait hangs below the title bar at the left edge.
        -- The icons are centered and clear it, but Say/Yell sits at the
        -- left, so it never starts higher than this.
        portraitClearance = 60,
        divider = { 1, 0.82, 0, 0.25 },
        header = { 1, 0.82, 0 }, -- the default UI's header gold
        headerBar = { 0.17, 0.11, 0.04, 0.9 },
        headerLine = { 0.55, 0.42, 0.12, 1 },
        collapseOnRight = true,
        text = { 1, 1, 1 },
        textNeedsTarget = { 0.5, 0.5, 0.5 },
        textFlagged = { 0.7, 0.35, 0.35 },
        rowHover = { 1, 1, 1, 0.3 },
        rowFlash = { 1, 1, 1, 0.7 },
    },
}
local look = LOOKS.campfire

-- The panel styles offered in the options panel, in display order. A
-- style marked `placeholder = true` is listed but shown disabled, so it
-- can't be selected yet.
CS.UI.STYLES = {
    { id = "campfire", labelKey = "style_campfire" },
    { id = "forever", labelKey = "style_forever" },
}
CS.UI.DEFAULT_STYLE = "forever"

-- How far the portrait frame's border sits outside the panel's content on
-- the left, right and bottom; its title bar is inside the title area.
-- The portrait itself overhangs the frame's top-left corner.
local FOREVER_FRAME_OUTSET = 6
local FOREVER_PORTRAIT_OVERHANG = 8

-- Confirmed present and rendering in this client via `/campfire textures`
-- (file 130661); every earlier background path was assumed, never seen.
local BACKGROUND_TEXTURE = "Interface/AchievementFrame/UI-Achievement-Parchment-Horizontal"
-- The default UI's menu/list highlight, which fades at its left and right
-- ends; createSoftBand fades its top and bottom too.
local ROW_HIGHLIGHT_TEXTURE = "Interface/QuestFrame/UI-QuestTitleHighlight"

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
local professionDivider
-- Built in CreatePanel: every region and frame making up the campfire
-- style's look, the Forever style's portrait frame (nil if it couldn't be
-- built), and the title glow's flicker controls.
local campfireChrome = {}
local foreverChrome
local startFlicker
local stopFlicker

CS.UI.isAutoOpened = false

local function cancelPendingHide()
    if pendingHideTimer then
        pendingHideTimer:Cancel()
        pendingHideTimer = nil
    end
end

-- The highlight texture already fades at its ends but has hard top and
-- bottom edges, so it's drawn as two halves, each with a vertex-color
-- gradient fading to transparent at its outer edge. Colored separately
-- (colorSoftBand) so a pooled row picks up a style change.
local function createSoftBand(row, layer)
    local top = row:CreateTexture(nil, layer)
    top:SetPoint("TOPLEFT")
    top:SetPoint("TOPRIGHT")
    top:SetPoint("BOTTOM", row, "CENTER")
    top:SetTexture(ROW_HIGHLIGHT_TEXTURE)
    top:SetTexCoord(0, 1, 0, 0.5)
    top:SetBlendMode("ADD")

    local bottom = row:CreateTexture(nil, layer)
    bottom:SetPoint("BOTTOMLEFT")
    bottom:SetPoint("BOTTOMRIGHT")
    bottom:SetPoint("TOP", row, "CENTER")
    bottom:SetTexture(ROW_HIGHLIGHT_TEXTURE)
    bottom:SetTexCoord(0, 1, 0.5, 1)
    bottom:SetBlendMode("ADD")

    return { top, bottom }
end

local function colorSoftBand(band, color)
    local r, g, b, a = unpack(color)
    local solid = CreateColor(r, g, b, a)
    local clear = CreateColor(r, g, b, 0)
    band[1]:SetGradient("VERTICAL", solid, clear) -- bottom color, then top
    band[2]:SetGradient("VERTICAL", clear, solid)
end

local function setBandAlpha(band, alpha)
    for _, texture in ipairs(band) do
        texture:SetAlpha(alpha)
    end
end

local function setBandShown(band, shown)
    for _, texture in ipairs(band) do
        texture:SetShown(shown)
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
        row.collapseIcon:SetHighlightTexture("Interface/Buttons/UI-PlusButton-Hilight", "ADD")

        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.text:SetJustifyH("LEFT")

        -- A soft wash on hover. Rows never had a highlight texture, so
        -- the old LockHighlight() click feedback had nothing to show.
        row.hover = createSoftBand(row, "HIGHLIGHT")
        row.flash = createSoftBand(row, "BACKGROUND")

        -- The Forever style's category header bar: a dark fill with a
        -- gold rule along its bottom, like the profession list's section
        -- headers. Shown only on header rows of a style with a headerBar.
        row.headerBar = row:CreateTexture(nil, "BACKGROUND", nil, -1)
        row.headerBar:SetAllPoints()
        row.headerLine = row:CreateTexture(nil, "BORDER")
        row.headerLine:SetHeight(1)
        row.headerLine:SetPoint("BOTTOMLEFT")
        row.headerLine:SetPoint("BOTTOMRIGHT")
    end

    colorSoftBand(row.hover, look.rowHover)
    colorSoftBand(row.flash, look.rowFlash)
    setBandAlpha(row.hover, 1)
    setBandShown(row.flash, false)
    row.headerBar:Hide()
    row.headerLine:Hide()
    row.collapseIcon:ClearAllPoints()
    row.collapseIcon:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.collapseIcon:Hide()
    row.collapseIcon:SetScript("OnClick", nil)
    row.text:ClearAllPoints()
    row.text:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.text:SetFontObject("GameFontHighlight")
    row.text:SetTextColor(unpack(look.text))
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
    setBandShown(row.flash, true)
    C_Timer.After(HIGHLIGHT_DURATION, function()
        setBandShown(row.flash, false)
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

-- Chosen in-client, see docs/profession-button-appearance-findings.md
-- Rounds 8-10. Request is red-orange to match the red of yell messages.
-- On cooldown is the gray of poor-quality items (#9D9D9D).
local function professionGlowColor(state)
    if state == "cooldown" then
        return 0.616, 0.616, 0.616
    elseif state == "use" then
        return 0.1, 0.9, 0.1
    elseif state == "craft" then
        return 0.1, 0.3, 1
    end
    return 1, 0.2, 0
end

-- A "use" button whose shared cooldown is running is shown as its own
-- "cooldown" state; craft and request still work during it.
local function featureState(button)
    if button.onCooldown then
        return "cooldown"
    end
    return button.pendingAction
end

-- Status text color: white tinted a quarter of the way toward the
-- button's glow color, so it reads as white with a hint of the state.
local FEATURE_STATUS_TINT = 0.25

-- The feature's name as the title, then its status line. Anchored off
-- the button's upper-right corner instead of following the cursor.
local function showFeatureTooltip(button)
    -- No state means the button was just hidden.
    local state = featureState(button)
    if not (button.tooltipTitle and state) then
        return
    end
    GameTooltip:SetOwner(button, "ANCHOR_NONE")
    GameTooltip:SetPoint("BOTTOMLEFT", button, "TOPRIGHT")
    GameTooltip:SetText(button.tooltipTitle)
    local r, g, b = professionGlowColor(state)
    local keep = 1 - FEATURE_STATUS_TINT
    GameTooltip:AddLine(CS.Data.L["feature_status_" .. state],
        keep + FEATURE_STATUS_TINT * r, keep + FEATURE_STATUS_TINT * g, keep + FEATURE_STATUS_TINT * b, true)
    GameTooltip:Show()
end

-- Sets the glow from the button's state, and redraws its tooltip if
-- it's showing so the status line changes while hovered.
local function applyFeatureVisuals(button)
    button.glow:SetVertexColor(professionGlowColor(featureState(button)))
    if GameTooltip:IsOwned(button) then
        showFeatureTooltip(button)
    end
end

-- Defined below createProfessionButton; declared here so its PostClick
-- can call it.
local updateProfessionCooldowns

-- Creates one of the 11 fixed campfire feature buttons, permanently bound
-- to its own item - unlike acquireRow's pool, these are never recycled
-- (a SecureActionButtonTemplate button's identity can't be reassigned
-- the way a pooled row's label can). RegisterForClicks requests both
-- "AnyUp" and "AnyDown": with the ActionButtonUseKeyDown CVar on, the
-- secure item use only happens on the press, so an "AnyUp"-only button
-- never placed anything (docs/profession-use-findings.md Rounds 1-2).
-- Registering both fires PreClick twice per physical click, so PreClick
-- below ignores the press - otherwise it would double-craft or
-- double-yell.
local function createProfessionButton(entry)
    local button = CreateFrame("Button", "CampfireStokersProfessionButton" .. entry.id, frame,
        "SecureActionButtonTemplate")
    button:SetSize(PROFESSION_ICON_SIZE, PROFESSION_ICON_SIZE)
    button:RegisterForClicks("AnyUp", "AnyDown")

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()

    -- State glow instead of a backdrop border: the old 10px tooltip
    -- border was almost entirely covered by the icon, and thin/solid/
    -- stacked alternatives all read poorly in-client (see
    -- docs/profession-button-appearance-findings.md Rounds 1-7). ADD
    -- blend keeps the icon visible; BLEND covered it (Round 8).
    button.glow = button:CreateTexture(nil, "OVERLAY")
    button.glow:SetTexture("Interface/Buttons/UI-ActionButton-Border")
    button.glow:SetBlendMode("ADD")
    button.glow:SetSize(PROFESSION_GLOW_SIZE, PROFESSION_GLOW_SIZE)
    button.glow:SetPoint("CENTER")

    -- The standard action-button cooldown swipe, so a placed campfire
    -- feature's shared cooldown shows on every campfire feature the
    -- player holds.
    -- Countdown numbers forced on so the time left is visible regardless
    -- of the player's own cooldown-text setting.
    button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.cooldown:SetAllPoints()
    if button.cooldown.SetHideCountdownNumbers then
        button.cooldown:SetHideCountdownNumbers(false)
    end
    -- Turns the glow back from gray when the cooldown runs out, without
    -- relying on BAG_UPDATE_COOLDOWN firing for the end too.
    button.cooldown:SetScript("OnCooldownDone", function()
        button.onCooldown = false
        applyFeatureVisuals(button)
    end)

    button:SetScript("OnEnter", showFeatureTooltip)
    button:SetScript("OnLeave", hideRowTooltip)

    -- PreClick, not OnClick, so this coexists with the secure click path:
    -- when type/item are set (action == "use"), the secure click-through
    -- handles the item use and pendingAction is nil, so this is a no-op;
    -- when they're cleared (craft/request), this is the only logic that
    -- runs. Confirmed in-client 2026-10-04 that both cases work with no
    -- taint - see docs/decision-log.md.
    -- Acts on the release only (see RegisterForClicks above); craft was
    -- verified in-client on the release (craft ledger Rounds 15-17).
    button:SetScript("PreClick", function(self, _, down)
        if down then
            return
        end
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
                print("Campfire Stokers: " .. CS.Data.L.feature_request_not_ready)
            end
        end
    end)

    -- After a Use click (the secure click-through has already run by
    -- PostClick), read the shared cooldown back once the client has had a
    -- moment to start it; CheckCooldownAfterUse reports it in debug mode
    -- and forces an hour-long one if none is readable. Release only, like
    -- PreClick. A click while already on cooldown can't have used
    -- anything, so it's ignored rather than restarting the forced timer.
    button:SetScript("PostClick", function(self, _, down)
        if down or self.pendingAction ~= "use" then
            return
        end
        local itemId = self.pendingItemId
        if self.onCooldown then
            CS.Debug("Use of item " .. tostring(itemId) .. " clicked while already on cooldown; ignored.")
            return
        end
        C_Timer.After(USE_COOLDOWN_CHECK_DELAY_SECONDS, function()
            CS.Professions.CheckCooldownAfterUse(itemId)
            updateProfessionCooldowns()
        end)
    end)

    button:Hide()
    return button
end

-- Only a "use" button shows the cooldown: it's the item's Use that's
-- blocked, while crafting or requesting another one still works.
-- Not protected (the cooldown frame isn't secure), so this is safe in
-- combat too.
local function updateProfessionCooldown(button)
    local start, duration
    if button.pendingAction == "use" then
        start, duration = CS.Professions.GetFeatureCooldown(button.pendingItemId)
    end
    if start then
        button.cooldown:SetCooldown(start, duration)
    else
        button.cooldown:Clear()
    end
    -- A global-cooldown-length sweep still draws, like on action bars,
    -- but doesn't turn the button gray.
    button.onCooldown = start ~= nil and duration > CS.Professions.GLOBAL_COOLDOWN_MAX_SECONDS
    applyFeatureVisuals(button)
end

function updateProfessionCooldowns()
    for _, button in pairs(professionButtons) do
        updateProfessionCooldown(button)
    end
end

local function applyProfessionButtonState(button, result)
    button.icon:SetTexture(result.icon)

    button.pendingAction = result.action
    button.pendingRecipeSpellId = result.recipeSpellId
    button.pendingItemId = result.itemId
    button.pendingMissing = result.missing
    button.pendingEntry = result.entry

    if result.action == "use" then
        button:SetAttribute("type", "item")
        button:SetAttribute("item", result.itemName)
    else
        button:SetAttribute("type", nil)
    end
    button.tooltipTitle = result.entry.itemName
    updateProfessionCooldown(button)
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
-- Deliberately not gated on CS.Detection.atFire: the buttons show
-- whenever the panel does, including a manual open away from a fire and
-- the auto-close grace period after the aura drops (see docs/tasks.md's
-- "Profession button visibility").
local function evaluateFeatureSafely(entry)
    local ok, result = pcall(CS.Professions.EvaluateFeature, entry)
    if not ok then
        print("Campfire Stokers: campfire feature '" .. entry.id .. "' failed to evaluate: " .. tostring(result))
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
    local topY = startY - look.professionBlockGap
    local step = PROFESSION_ICON_SIZE + PROFESSION_ICON_GAP

    -- Evaluate everything first: centering a row needs to know how many
    -- buttons end up in it.
    local visibleButtons = {}
    for _, entry in ipairs(CS.Professions.FEATURES) do
        local button = professionButtons[entry.id]
        local result = evaluateFeatureSafely(entry)

        if result.visible then
            applyProfessionButtonState(button, result)
            table.insert(visibleButtons, button)
        else
            button:Hide()
            button:SetAttribute("type", nil)
            button.pendingAction = nil
            updateProfessionCooldown(button)
        end
    end

    local count = #visibleButtons
    for index, button in ipairs(visibleButtons) do
        local row = math.floor((index - 1) / columns)
        local column = (index - 1) % columns
        local inRow = math.min(columns, count - row * columns)
        local rowWidth = inRow * PROFESSION_ICON_SIZE + (inRow - 1) * PROFESSION_ICON_GAP
        local x = (PANEL_WIDTH - rowWidth) / 2 + column * step
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", frame, "TOPLEFT", x, topY - row * step)
        button:Show()
    end

    local rowsUsed = math.ceil(count / columns)
    if rowsUsed > 0 then
        previousProfessionBlockHeight = look.professionBlockGap
            + (rowsUsed * PROFESSION_ICON_SIZE) + ((rowsUsed - 1) * PROFESSION_ICON_GAP)
            + look.professionBlockGap
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
        row.text:SetTextColor(unpack(look.textFlagged)) -- never sendable
        row.tooltipText = row.classifyReason
    elseif not enabled then
        row.text:SetTextColor(unpack(look.textNeedsTarget))
        row.tooltipText = CS.Data.L.ui_needs_target_tooltip
    else
        row.text:SetTextColor(unpack(look.text))
        row.tooltipText = nil
    end
    -- No hover wash on a row a click won't send, so it doesn't look live.
    setBandAlpha(row.hover, enabled and 1 or 0)
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

-- Shows the chrome for the selected style and hides the other's, and
-- points `look` at its colors. Both styles' chrome is built once in
-- CreatePanel, so switching in the options panel is live, no reload.
-- Falls back to the campfire style if the Forever style's frame couldn't
-- be built (see CreatePanel).
local function applyStyle()
    local useForever = CampfireStokersDB.panelStyle == "forever" and foreverChrome ~= nil
    look = useForever and LOOKS.forever or LOOKS.campfire

    for _, piece in ipairs(campfireChrome) do
        piece:SetShown(not useForever)
    end
    if foreverChrome then
        foreverChrome:SetShown(useForever)
    end

    if useForever then
        stopFlicker()
        frame:SetClampRectInsets(-FOREVER_FRAME_OUTSET, FOREVER_FRAME_OUTSET, FOREVER_PORTRAIT_OVERHANG,
            -FOREVER_FRAME_OUTSET)
    else
        if frame:IsShown() then
            startFlicker()
        end
        -- Clamp the wood, not just the panel inside it, to the screen.
        frame:SetClampRectInsets(-WOOD_VISIBLE_OUTSET, WOOD_VISIBLE_OUTSET, WOOD_VISIBLE_OUTSET,
            -WOOD_VISIBLE_OUTSET)
    end

    professionDivider:SetColorTexture(unpack(look.divider))
end

local function minPanelHeight()
    local controlsTop = math.max(look.titleAreaHeight, look.portraitClearance or 0)
    return controlsTop + SAY_YELL_HEIGHT + SAY_YELL_BOTTOM_GAP + ROW_HEIGHT
end

function CS.UI.Refresh()
    if not frame then
        return
    end

    applyStyle()
    releaseRows()

    local y = -look.titleAreaHeight
    local professionBlockHeight = layoutProfessionBlock(y)
    y = y - professionBlockHeight

    -- Separates the campfire features (whose requests always yell) from the
    -- Say/Yell toggle and the phrases it controls.
    if professionBlockHeight > 0 then
        professionDivider:ClearAllPoints()
        professionDivider:SetPoint("TOPLEFT", frame, "TOPLEFT", DIVIDER_INSET, y + 1)
        professionDivider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -DIVIDER_INSET, y + 1)
        professionDivider:Show()
        y = y - 6
    else
        professionDivider:Hide()
    end
    if look.portraitClearance then
        y = math.min(y, -look.portraitClearance)
    end

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
        if look.collapseOnRight then
            headerRow.collapseIcon:ClearAllPoints()
            headerRow.collapseIcon:SetPoint("RIGHT", headerRow, "RIGHT", -6, 0)
            headerRow.text:SetPoint("LEFT", headerRow, "LEFT", 8, 0)
            headerRow.text:SetPoint("RIGHT", headerRow.collapseIcon, "LEFT", -6, 0)
        else
            headerRow.text:SetPoint("LEFT", headerRow.collapseIcon, "RIGHT", 6, 0)
            headerRow.text:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
        end
        if look.headerBar then
            headerRow.headerBar:SetColorTexture(unpack(look.headerBar))
            headerRow.headerBar:Show()
            headerRow.headerLine:SetColorTexture(unpack(look.headerLine))
            headerRow.headerLine:Show()
        end
        headerRow.text:SetFontObject("GameFontNormalLarge")
        headerRow.text:SetTextColor(unpack(look.header))
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

    frame:SetHeight(math.max(-y + 8, minPanelHeight()))
end

function CS.UI.Show()
    if not frame then
        return
    end
    cancelPendingHide()
    CS.UI.isAutoOpened = false
    -- Evaluate before showing, same as the auto-open path - otherwise a
    -- manual open shows whatever the last refresh (possibly long ago)
    -- laid out.
    CS.UI.Refresh()
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
    CS.UI.Refresh() -- evaluate the profession buttons before any auto-open below
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

-- The DialogBox background texture is partly transparent, so whatever is
-- behind a popup shows through it (reported in-client over the options
-- rows), and a backdrop tint can only lower its alpha, not raise it. A
-- solid black layer inside the border makes the popup fully opaque;
-- tried in-client, the dark texture over it looks the same as flat black.
local function addOpaqueUnderlay(popup)
    local underlay = popup:CreateTexture(nil, "BACKGROUND", nil, -8)
    underlay:SetPoint("TOPLEFT", popup, "TOPLEFT", 11, -12)
    underlay:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -12, 11)
    underlay:SetColorTexture(0, 0, 0, 1)
end

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
    addOpaqueUnderlay(popup)
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
    addOpaqueUnderlay(popup)
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
-- operations), nothing protected - the 11 campfire feature buttons are
-- the one exception, built with SecureActionButtonTemplate (see
-- createProfessionButton above and docs/decision-log.md).
function CS.UI.CreatePanel()
    CampfireStokersDB.collapsedCategories = CampfireStokersDB.collapsedCategories or {}
    CampfireStokersDB.sendMode = CampfireStokersDB.sendMode or "SAY"
    -- "default" was this style's id before it was renamed Forever.
    if CampfireStokersDB.panelStyle == "default" then
        CampfireStokersDB.panelStyle = "forever"
    end
    CampfireStokersDB.panelStyle = CampfireStokersDB.panelStyle or CS.UI.DEFAULT_STYLE

    frame = CreateFrame("Frame", "CampfireStokersPanel", UIParent)
    frame:SetSize(PANEL_WIDTH, minPanelHeight())

    -- Not a backdrop background: a backdrop's background color multiplies
    -- its texture, so it can lower opacity but never raise it - the cause
    -- of the once see-through panel and of the text popups' old
    -- transparency (see addOpaqueUnderlay). Drawn as its own layers
    -- instead: an opaque solid color, then the darkened parchment over it.
    local backgroundFill = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    backgroundFill:SetPoint("TOPLEFT", frame, "TOPLEFT", -WOOD_UNDERLAP, WOOD_UNDERLAP)
    backgroundFill:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", WOOD_UNDERLAP, -WOOD_UNDERLAP)
    backgroundFill:SetColorTexture(unpack(LOOKS.campfire.background))

    local backgroundParchment = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    backgroundParchment:SetAllPoints(backgroundFill)
    backgroundParchment:SetTexture(BACKGROUND_TEXTURE)
    backgroundParchment:SetVertexColor(unpack(LOOKS.campfire.backgroundTexture))

    -- The wood sits in a clipping frame inset by WOOD_RIM, which trims the
    -- texture's metal rim off its outer edge. Both are above the panel's
    -- rows so their edges tuck under the wood, and neither is
    -- mouse-enabled, so they never block a click. Clipping is feature-
    -- tested rather than assumed: without it the panel still works, just
    -- with the rim showing.
    local woodClip = CreateFrame("Frame", nil, frame)
    woodClip:SetPoint("TOPLEFT", frame, "TOPLEFT", -WOOD_VISIBLE_OUTSET, WOOD_VISIBLE_OUTSET)
    woodClip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", WOOD_VISIBLE_OUTSET, -WOOD_VISIBLE_OUTSET)
    woodClip:SetFrameLevel(frame:GetFrameLevel() + 10)
    if woodClip.SetClipsChildren then
        woodClip:SetClipsChildren(true)
    end

    local woodBorder = CreateFrame("Frame", nil, woodClip, "BackdropTemplate")
    woodBorder:SetPoint("TOPLEFT", frame, "TOPLEFT", -WOOD_OUTSET, WOOD_OUTSET)
    woodBorder:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", WOOD_OUTSET, -WOOD_OUTSET)
    woodBorder:SetBackdrop(WOOD_BORDER)

    for _, corner in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
        local cap = woodBorder:CreateTexture(nil, "OVERLAY")
        cap:SetSize(WOOD_CORNER_CAP, WOOD_CORNER_CAP)
        cap:SetPoint(corner, woodClip, corner)
        cap:SetColorTexture(unpack(LOOKS.campfire.woodCorner))
    end

    -- The clamp insets depend on the style's border; applyStyle sets them.
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")

    local savedPosition = CampfireStokersDB.position
    if savedPosition then
        frame:SetPoint(savedPosition.point, UIParent, savedPosition.point, savedPosition.x, savedPosition.y)
    else
        -- Centered in the right half of the screen, a fifth of the way
        -- down: the profession window opens anchored to the left when a
        -- campfire recipe is crafted from the panel, and covered the panel at its
        -- old default spot above the chat window. Top-anchored so the
        -- panel grows downward as categories expand.
        frame:SetPoint("TOP", UIParent, "TOP", UIParent:GetWidth() / 4, -UIParent:GetHeight() / 5)
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
    -- The add-on's own TOC icon, trimmed of its built-in icon border.
    local titleIcon = frame:CreateTexture(nil, "ARTWORK")
    titleIcon:SetSize(TITLE_ICON_SIZE, TITLE_ICON_SIZE)
    titleIcon:SetTexture("Interface/Icons/Spell_Fire_Fire")
    titleIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- An ember glow flickering around the icon, on the same glow texture
    -- as the profession buttons. Fire flickers rather than pulses, so each
    -- step fades to a random brightness over a random short time, then
    -- picks the next when it finishes. An animation group, not an OnUpdate
    -- handler, and only running while the panel is shown.
    local titleGlow = frame:CreateTexture(nil, "OVERLAY")
    titleGlow:SetTexture("Interface/Buttons/UI-ActionButton-Border")
    titleGlow:SetBlendMode("ADD")
    titleGlow:SetSize(TITLE_GLOW_SIZE, TITLE_GLOW_SIZE)
    titleGlow:SetPoint("CENTER", titleIcon, "CENTER")
    titleGlow:SetVertexColor(unpack(LOOKS.campfire.header))

    local emberFlicker = titleGlow:CreateAnimationGroup()
    emberFlicker:SetToFinalAlpha(true)
    local fade = emberFlicker:CreateAnimation("Alpha")
    local glowAlpha = 1
    local function nextFlicker()
        local target = FLICKER_MIN_ALPHA + math.random() * (1 - FLICKER_MIN_ALPHA)
        fade:SetFromAlpha(glowAlpha)
        fade:SetToAlpha(target)
        fade:SetDuration(FLICKER_MIN_SECONDS + math.random() * (FLICKER_MAX_SECONDS - FLICKER_MIN_SECONDS))
        glowAlpha = target
        emberFlicker:Play()
    end
    emberFlicker:SetScript("OnFinished", nextFlicker)
    startFlicker = function()
        if not emberFlicker:IsPlaying() then
            nextFlicker()
        end
    end
    stopFlicker = function()
        emberFlicker:Stop()
    end
    frame:SetScript("OnShow", function()
        if look == LOOKS.campfire then
            startFlicker()
        end
    end)
    frame:SetScript("OnHide", stopFlicker)

    -- Icon and title centered as one unit: the text is offset right by
    -- half the icon's width plus gap, and the icon hangs off its left.
    local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("CENTER", frame, "TOP", (TITLE_ICON_SIZE + TITLE_ICON_TEXT_GAP) / 2,
        -(CAMPFIRE_TITLE_AREA_HEIGHT / 2))
    titleText:SetText(CS.Data.L.ui_panel_title)
    titleText:SetTextColor(unpack(LOOKS.campfire.header))
    titleIcon:SetPoint("RIGHT", titleText, "LEFT", -TITLE_ICON_TEXT_GAP, 0)

    local titleDivider = frame:CreateTexture(nil, "ARTWORK")
    titleDivider:SetHeight(1)
    titleDivider:SetPoint("TOPLEFT", frame, "TOPLEFT", DIVIDER_INSET, -CAMPFIRE_TITLE_AREA_HEIGHT + 2)
    titleDivider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -DIVIDER_INSET, -CAMPFIRE_TITLE_AREA_HEIGHT + 2)
    titleDivider:SetColorTexture(unpack(LOOKS.campfire.divider))

    professionDivider = frame:CreateTexture(nil, "ARTWORK")
    professionDivider:SetHeight(1)
    professionDivider:SetColorTexture(unpack(LOOKS.campfire.divider))
    professionDivider:Hide()

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    -- Centered on a title-row-sized square in the corner, so it lines up
    -- with the title and its top and right margins match, then nudged in
    -- a little more off the border.
    local closeOffset = CAMPFIRE_TITLE_AREA_HEIGHT / 2 + CLOSE_BUTTON_EXTRA_PADDING
    closeButton:SetPoint("CENTER", frame, "TOPRIGHT", -closeOffset, -closeOffset)
    closeButton:SetScript("OnClick", CS.UI.Hide)

    campfireChrome = {
        backgroundFill, backgroundParchment, woodClip, titleIcon, titleGlow, titleText, titleDivider, closeButton,
    }

    -- The Forever style: Blizzard's own portrait frame, the template the
    -- default UI's Auction House and profession windows are built on, for
    -- its border, title bar, rock background, round portrait and close
    -- button, so the art is whatever this client's own frames use rather
    -- than texture paths guessed from retail. Its border sits just outside
    -- the panel's content and its title bar inside the title area. Kept at
    -- the panel's own frame level, under the rows and buttons, and not
    -- mouse-enabled, so dragging the panel still works through it. Neither
    -- the template nor its mixin methods are confirmed on Forever yet, so
    -- it's built under pcall; if it fails, the Forever style falls back to
    -- the campfire look (see applyStyle).
    local chrome
    local ok, err = pcall(function()
        chrome = CreateFrame("Frame", nil, frame, "PortraitFrameTemplate")
        chrome:SetPoint("TOPLEFT", frame, "TOPLEFT", -FOREVER_FRAME_OUTSET, 0)
        chrome:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", FOREVER_FRAME_OUTSET, -FOREVER_FRAME_OUTSET)
        chrome:SetFrameLevel(frame:GetFrameLevel())
        chrome:EnableMouse(false)
        chrome:SetTitle(CS.Data.L.ui_panel_title)
        chrome:SetPortraitToAsset("Interface/Icons/Spell_Fire_Fire")
        -- The template's close button would hide only this chrome frame.
        chrome.CloseButton:SetScript("OnClick", CS.UI.Hide)
        chrome:Hide()
        foreverChrome = chrome
    end)
    if not ok then
        -- A half-built frame (the template loaded, a mixin method didn't)
        -- would otherwise stay on screen over the campfire look.
        if chrome then
            chrome:Hide()
        end
        print("Campfire Stokers: could not build the Forever panel style (" .. tostring(err) .. ").")
    end

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
    -- Fires when an item cooldown starts or ends. Not yet confirmed on
    -- Forever, and registering an unknown event throws on this build (see
    -- docs/decision-log.md), so it's guarded: without it the swipe still
    -- updates on every Refresh, including BAG_UPDATE_DELAYED's after a
    -- campfire feature is placed.
    local cooldownEventOk = pcall(frame.RegisterEvent, frame, "BAG_UPDATE_COOLDOWN")
    if not cooldownEventOk then
        print("Campfire Stokers: BAG_UPDATE_COOLDOWN is not available; profession cooldowns update on refresh only.")
    end
    frame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_TARGET_CHANGED" then
            refreshTargetGating()
        elseif event == "BAG_UPDATE_COOLDOWN" then
            updateProfessionCooldowns()
        end
    end)

    for _, entry in ipairs(CS.Professions.FEATURES) do
        professionButtons[entry.id] = createProfessionButton(entry)
    end

    frame:Hide()
    CS.UI.Refresh()

    return frame
end
