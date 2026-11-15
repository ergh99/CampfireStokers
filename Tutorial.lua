local CS = select(2, ...)

---@class CampfireStokersTutorial
CS.Tutorial = CS.Tutorial or {}

-- The first-run tutorial: a welcome card after login, a guided tour of the
-- phrase editor, and a shorter tour of the campfire panel the first time it
-- auto-opens. See docs/tutorial-plan.md for the design and the decisions
-- behind it.
--
-- Split the same way as the rest of the repo: the due/seen state and the
-- step lists are pure and headless-tested (tests/tutorial_spec.lua); the
-- card, the callout frame and the event wiring below them need a real
-- client and are checked in-client.

-- Raise this to show the whole tutorial once more to everyone, after a
-- change significant enough to re-teach. Saved state written under an
-- older version counts as never seen.
CS.Tutorial.VERSION = 1

-- How long after PLAYER_LOGIN the welcome card waits, so it doesn't
-- compete with the loading screen and other add-ons' popups.
CS.Tutorial.WELCOME_DELAY_SECONDS = 3

---------------------------------------------------------------------------
-- Pure logic
---------------------------------------------------------------------------

-- Is `part` ("welcome", "editor", "panel" or "features") still to be
-- shown? A save with no tutorial table (a fresh install, or anyone
-- upgrading from v0.1.0) or one written under an older VERSION has every
-- part due.
function CS.Tutorial.IsDue(db, part)
    local state = db and db.tutorial
    if type(state) ~= "table" or (tonumber(state.version) or 0) < CS.Tutorial.VERSION then
        return true
    end
    return state[part] ~= true
end

-- Records `part` as seen. Starts a fresh table when the saved one is
-- missing or from an older VERSION, so stale entries never carry over.
-- Only booleans and an integer are written (AGENTS.md secret-value rule 5).
function CS.Tutorial.MarkSeen(db, part)
    local state = db.tutorial
    if type(state) ~= "table" or (tonumber(state.version) or 0) < CS.Tutorial.VERSION then
        state = { version = CS.Tutorial.VERSION }
        db.tutorial = state
    end
    state[part] = true
end

-- Forgets every part, so the next login behaves like a first install.
function CS.Tutorial.Reset(db)
    db.tutorial = nil
end

-- Why a tour ended. Only "done" (its last step's Done, or its action
-- button) and "closed" (the close X) count as seen; "targetHidden" (the
-- frame a callout points at went away, e.g. the panel auto-closed) and
-- "replaced" (another tour or the card took over) leave the tour due, so
-- it runs again in context later.
CS.Tutorial.END_REASONS = { done = true, closed = true, targetHidden = false, replaced = false }

-- Marks `part` seen if `reason` counts. Returns whether it did.
function CS.Tutorial.FinishTour(db, part, reason)
    if CS.Tutorial.END_REASONS[reason] then
        CS.Tutorial.MarkSeen(db, part)
        return true
    end
    return false
end

-- Each step: `id`, `textKey` (a CS.Data.L key), `anchor` (resolved to a
-- real frame at show time by the module that owns it), `placement` (which
-- side of the anchor the callout sits on), and optionally `requires`: a
-- table of context keys and the values they must have for the step to show.
-- The panel's steps sit to its left: it opens in the right half of the
-- screen by default.
CS.Tutorial.EDITOR_STEPS = {
    { id = "addCategory", textKey = "tutorial_editor_add_category", anchor = "addCategory", placement = "right" },
    {
        id = "categoryActions",
        textKey = "tutorial_editor_category_actions",
        anchor = "categoryActions",
        placement = "below",
        requires = { hasCategoryRow = true },
    },
    {
        id = "phraseActions",
        textKey = "tutorial_editor_phrase_actions",
        anchor = "phraseActions",
        placement = "below",
        requires = { hasPhraseRow = true },
    },
    {
        id = "dragHandle",
        textKey = "tutorial_editor_drag",
        anchor = "dragHandle",
        placement = "below",
        requires = { hasPhraseRow = true },
    },
}

CS.Tutorial.PANEL_STEPS = {
    {
        id = "phrase",
        textKey = "tutorial_panel_phrase",
        anchor = "firstPhrase",
        placement = "left",
        requires = { hasPhraseRow = true },
    },
    {
        id = "features",
        textKey = "tutorial_panel_features",
        anchor = "firstFeature",
        placement = "left",
        requires = { hasFeatureButtons = true },
    },
    {
        id = "editorOffer",
        textKey = "tutorial_panel_editor_offer",
        anchor = "panel",
        placement = "left",
        actionKey = "tutorial_panel_editor_offer_button",
        requires = { editorSeen = false },
    },
}

-- The feature step on its own, for when the panel tour ran without any
-- feature buttons showing and a later panel has some.
CS.Tutorial.FEATURE_STEPS = {
    {
        id = "features",
        textKey = "tutorial_panel_features",
        anchor = "firstFeature",
        placement = "left",
        requires = { hasFeatureButtons = true },
    },
}

function CS.Tutorial.StepAvailable(step, context)
    for key, value in pairs(step.requires or {}) do
        -- A missing key reads as false, so `editorSeen = false` holds for
        -- an empty context.
        if ((context or {})[key] or false) ~= value then
            return false
        end
    end
    return true
end

-- The index of the first available step after `index` (0 for the first
-- step), or nil when there's none left.
function CS.Tutorial.NextStep(steps, index, context)
    for i = (index or 0) + 1, #steps do
        if CS.Tutorial.StepAvailable(steps[i], context) then
            return i
        end
    end
    return nil
end

-- For the "2 / 4" counter: where step `index` falls among the steps
-- available in `context`, and how many there are.
function CS.Tutorial.StepPosition(steps, index, context)
    local position, total = 0, 0
    for i = 1, #steps do
        if CS.Tutorial.StepAvailable(steps[i], context) then
            total = total + 1
            if i <= index then
                position = position + 1
            end
        end
    end
    return position, total
end

---------------------------------------------------------------------------
-- Frames and wiring (in-client only)
---------------------------------------------------------------------------

local L -- CS.Data.L, set in Init (Data.lua loads first, but read it late)

local CALLOUT_WIDTH = 260
local CALLOUT_PADDING = 12
local ARROW_SIZE = 32
-- Between the callout and its anchor; the arrow sits in it, overlapping
-- the callout's edge by 4.
local CALLOUT_GAP = ARROW_SIZE - 4
-- The yellow tutorial arrow the default UI points at things with. It's
-- drawn pointing down; rotated per placement.
local ARROW_TEXTURE = "Interface/Buttons/UI-MicroStream-Yellow"

local CARD_NAME = "CampfireStokersWelcomeCard"
local CARD_WIDTH = 360

local eventFrame
local card
-- The card is due this session but not shown yet (the login delay, or
-- combat); the panel tour holds off until it has been.
local cardShowPending = false
local cardCombatDeferred = false -- tried to show in combat; retry on PLAYER_REGEN_ENABLED
local panelTourPending = false -- the panel auto-opened while the card was up
local editorTourPending = false -- start the editor tour the next time it's shown

-- One thing to do as soon as combat ends (the card's Show me, or the
-- callout's Open Editor, clicked mid-fight), or nil.
local afterCombat

local callout
-- The running tour: { part =, steps =, index =, getContext =, resolve =,
-- unpin = } or nil.
local activeTour
local hookedAnchors = {}

local function db()
    return CampfireStokersDB
end

-- The frame a region's OnHide can be watched on: the region itself if it's
-- a frame, else its parent (a FontString has no scripts).
local function watchFrameFor(region)
    if region.HookScript then
        return region
    end
    return region:GetParent()
end

local ARROW_ROTATION = {
    -- Callout below the anchor: the arrow sits above it, pointing up.
    below = math.pi,
    above = 0,
    right = -math.pi / 2,
    left = math.pi / 2,
}

local function placeCallout(anchor, placement)
    callout:ClearAllPoints()
    callout.arrow:ClearAllPoints()
    callout.arrow:SetRotation(ARROW_ROTATION[placement] or 0)
    if placement == "below" then
        callout:SetPoint("TOP", anchor, "BOTTOM", 0, -CALLOUT_GAP)
        callout.arrow:SetPoint("BOTTOM", callout, "TOP", 0, -4)
    elseif placement == "above" then
        callout:SetPoint("BOTTOM", anchor, "TOP", 0, CALLOUT_GAP)
        callout.arrow:SetPoint("TOP", callout, "BOTTOM", 0, 4)
    elseif placement == "left" then
        callout:SetPoint("RIGHT", anchor, "LEFT", -CALLOUT_GAP, 0)
        callout.arrow:SetPoint("LEFT", callout, "RIGHT", -4, 0)
    else
        callout:SetPoint("LEFT", anchor, "RIGHT", CALLOUT_GAP, 0)
        callout.arrow:SetPoint("RIGHT", callout, "LEFT", 4, 0)
    end
end

local showStep -- defined below; endTour and the buttons need it

-- Ends the running tour. `reason` as CS.Tutorial.END_REASONS.
local function endTour(reason)
    local tour = activeTour
    if not tour then
        return
    end
    activeTour = nil
    -- Stop watching first: unpinning hides the pinned anchor, and that
    -- hide must not be taken for the target going away.
    callout.watched = nil
    if tour.unpin then
        tour.unpin()
    end
    callout.anchor = nil
    callout:Hide()
    CS.Tutorial.FinishTour(db(), tour.part, reason)
    if tour.onEnd then
        tour.onEnd(reason)
    end
end

-- Hooked once per anchor frame (HookScript can't be undone); it only acts
-- while that frame is the current step's anchor, which is what "removed
-- when the step ends" amounts to. Checked a frame later rather than at
-- once: the panel and the editor both rebuild their rows by hiding and
-- reshowing pooled frames, so a hide is often immediately followed by the
-- same content coming back, possibly on a different pooled frame.
local function onAnchorHidden(frame)
    if not activeTour or callout.watched ~= frame then
        return
    end
    C_Timer.After(0, function()
        if activeTour and callout.watched == frame then
            showStep(activeTour.index)
        end
    end)
end

local function watchAnchor(region)
    local frame = watchFrameFor(region)
    if frame and not hookedAnchors[frame] then
        hookedAnchors[frame] = true
        frame:HookScript("OnHide", onAnchorHidden)
    end
    callout.watched = frame
end

-- Shows step `index` of the running tour, re-resolving its anchor (so it
-- also serves to re-anchor after a rebuild). Ends the tour as
-- "targetHidden" if the anchor is gone.
function showStep(index)
    local tour = activeTour
    local step = tour.steps[index]
    tour.index = index
    local context = tour.getContext()

    -- Same as endTour: stop watching the old anchor before unpinning it.
    callout.watched = nil
    if tour.unpin then
        tour.unpin()
        tour.unpin = nil
    end
    local anchor, unpin = tour.resolve(step.anchor, true)
    tour.unpin = unpin
    if not anchor or not anchor:IsVisible() then
        endTour("targetHidden")
        return
    end

    local nextIndex = CS.Tutorial.NextStep(tour.steps, index, context)
    local position, total = CS.Tutorial.StepPosition(tour.steps, index, context)
    callout.text:SetText(L[step.textKey])
    callout.counter:SetText(total > 1 and (position .. " / " .. total) or "")
    callout.nextButton:SetText(nextIndex and L.tutorial_next or L.tutorial_done)
    callout.nextIndex = nextIndex
    if step.actionKey then
        callout.actionButton:SetText(L[step.actionKey])
        callout.actionButton:Show()
    else
        callout.actionButton:Hide()
    end
    callout.actionButton:Enable()
    callout.fitHeight()

    callout.anchor = anchor
    watchAnchor(anchor)
    placeCallout(anchor, step.placement)
    callout:Show()
    if tour.onStep then
        tour.onStep(step)
    end
end

local function ensureCallout()
    if callout then
        return callout
    end
    callout = CreateFrame("Frame", "CampfireStokersTutorialCallout", UIParent, "BackdropTemplate")
    callout:SetWidth(CALLOUT_WIDTH)
    -- Above SettingsPanel, so the editor tour's callouts show over it.
    callout:SetFrameStrata("FULLSCREEN_DIALOG")
    callout:SetClampedToScreen(true)
    callout:EnableMouse(true)
    callout:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    callout:SetBackdropColor(0.05, 0.04, 0.02, 0.95)
    callout:SetBackdropBorderColor(1, 0.82, 0)

    callout.arrow = callout:CreateTexture(nil, "OVERLAY")
    callout.arrow:SetSize(ARROW_SIZE, ARROW_SIZE)
    callout.arrow:SetTexture(ARROW_TEXTURE)

    callout.text = callout:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    callout.text:SetPoint("TOPLEFT", callout, "TOPLEFT", CALLOUT_PADDING, -CALLOUT_PADDING)
    callout.text:SetWidth(CALLOUT_WIDTH - 2 * CALLOUT_PADDING - 14) -- clear of the close X
    callout.text:SetJustifyH("LEFT")
    callout.fitHeight = function()
        callout:SetHeight(CALLOUT_PADDING + callout.text:GetStringHeight() + 10 + 22 + CALLOUT_PADDING)
    end

    local closeButton = CreateFrame("Button", nil, callout, "UIPanelCloseButton")
    closeButton:SetSize(24, 24)
    closeButton:SetPoint("TOPRIGHT", callout, "TOPRIGHT", 0, 0)
    closeButton:SetScript("OnClick", function()
        endTour("closed")
    end)

    callout.nextButton = CreateFrame("Button", nil, callout, "UIPanelButtonTemplate")
    callout.nextButton:SetSize(70, 22)
    callout.nextButton:SetPoint("BOTTOMRIGHT", callout, "BOTTOMRIGHT", -CALLOUT_PADDING, CALLOUT_PADDING)
    callout.nextButton:SetScript("OnClick", function()
        if callout.nextIndex then
            showStep(callout.nextIndex)
        else
            endTour("done")
        end
    end)

    callout.actionButton = CreateFrame("Button", nil, callout, "UIPanelButtonTemplate")
    callout.actionButton:SetSize(100, 22)
    callout.actionButton:SetPoint("RIGHT", callout.nextButton, "LEFT", -6, 0)
    -- The action (Open Editor) runs before the tour ends, so a failure
    -- can be explained right here in the callout instead of somewhere
    -- else. Mid-fight it waits for combat to end, saying so in place.
    local function runAction(tour)
        if activeTour ~= tour then
            return
        end
        if tour.onAction() then
            endTour("done")
        else
            callout.text:SetText(L.tutorial_editor_open_failed)
            callout.fitHeight()
        end
    end
    callout.actionButton:SetScript("OnClick", function()
        local tour = activeTour
        if not (tour and tour.onAction) then
            return
        end
        if InCombatLockdown() then
            callout.text:SetText(L.tutorial_editor_after_combat)
            callout.fitHeight()
            callout.actionButton:Disable()
            afterCombat = function()
                runAction(tour)
            end
            return
        end
        runAction(tour)
    end)

    callout.counter = callout:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    callout.counter:SetPoint("BOTTOMLEFT", callout, "BOTTOMLEFT", CALLOUT_PADDING, CALLOUT_PADDING + 5)

    callout:Hide()
    return callout
end

-- Starts a tour. `tour`: part, steps, getContext() -> context table,
-- resolve(anchorName, pin) -> region, unpinFunction-or-nil, and optionally
-- onStep(step), onAction(), onEnd(reason). Ends any tour already running
-- (as "replaced", so it stays due).
local function startTour(tour)
    if activeTour then
        endTour("replaced")
    end
    ensureCallout()
    local first = CS.Tutorial.NextStep(tour.steps, 0, tour.getContext())
    if not first then
        CS.Tutorial.FinishTour(db(), tour.part, "done")
        return
    end
    activeTour = tour
    showStep(first)
end

local function isCardShown()
    return card ~= nil and card:IsShown()
end

---------------------------------------------------------------------------
-- Editor tour
---------------------------------------------------------------------------

local function startEditorTour()
    editorTourPending = false
    startTour({
        part = "editor",
        steps = CS.Tutorial.EDITOR_STEPS,
        getContext = function()
            return {
                hasCategoryRow = CS.Options.GetTourAnchor("categoryActions") ~= nil,
                hasPhraseRow = CS.Options.GetTourAnchor("phraseActions") ~= nil,
            }
        end,
        resolve = CS.Options.GetTourAnchor,
        onEnd = function(reason)
            -- Interrupted (Settings closed mid-tour): pick it up again the
            -- next time the editor is shown.
            if reason == "targetHidden" then
                editorTourPending = true
            end
        end,
    })
end

-- Called from the editor canvas's OnShow, after it has refreshed its rows.
-- Deferred a frame so the Settings system has finished sizing the canvas.
function CS.Tutorial.OnEditorShown()
    if not editorTourPending or isCardShown() then
        return
    end
    C_Timer.After(0, function()
        if editorTourPending and CS.Options.IsShown() then
            startEditorTour()
        end
    end)
end

-- Opens the editor and runs its tour there. Returns whether Settings
-- opened; if it didn't, the tour still starts from the canvas's OnShow
-- whenever the editor is next shown. The caller explains the failure.
function CS.Tutorial.StartEditorTour()
    editorTourPending = true
    if not CS.Options.Open() then
        return false
    end
    -- Already showing: no OnShow will fire, so start it here.
    CS.Tutorial.OnEditorShown()
    return true
end

---------------------------------------------------------------------------
-- Panel tour
---------------------------------------------------------------------------

local function panelContext()
    return {
        hasPhraseRow = CS.UI.GetTourAnchor("firstPhrase") ~= nil,
        hasFeatureButtons = CS.UI.GetTourAnchor("firstFeature") ~= nil,
        editorSeen = not CS.Tutorial.IsDue(db(), "editor"),
    }
end

local function markFeatureStepSeen(step)
    if step.id == "features" then
        CS.Tutorial.MarkSeen(db(), "features")
    end
end

-- `guided`: started from the card's Show me, so it runs even if already
-- seen and always ends by offering the editor.
local function startPanelTour(guided)
    panelTourPending = false
    if guided or CS.Tutorial.IsDue(db(), "panel") then
        startTour({
            part = "panel",
            steps = CS.Tutorial.PANEL_STEPS,
            getContext = function()
                local context = panelContext()
                if guided then
                    context.editorSeen = false
                end
                return context
            end,
            resolve = CS.UI.GetTourAnchor,
            onStep = markFeatureStepSeen,
            onAction = CS.Tutorial.StartEditorTour,
        })
    elseif CS.Tutorial.IsDue(db(), "features") and CS.UI.GetTourAnchor("firstFeature") then
        startTour({
            part = "features",
            steps = CS.Tutorial.FEATURE_STEPS,
            getContext = panelContext,
            resolve = CS.UI.GetTourAnchor,
        })
    end
end

-- Called by UI.lua right after the panel auto-opens at a campfire. Reads
-- only the panel's own frames, never aura data. Never lets a tutorial
-- error escape into the auto-open path.
function CS.Tutorial.OnPanelAutoOpened()
    local d = db()
    if not d or (not CS.Tutorial.IsDue(d, "panel") and not CS.Tutorial.IsDue(d, "features")) then
        return
    end
    if activeTour then
        return
    end
    if isCardShown() or cardShowPending then
        panelTourPending = true
        return
    end
    local ok, err = pcall(startPanelTour)
    if not ok then
        print(L.tutorial_error .. " (" .. tostring(err) .. ")")
    end
end

---------------------------------------------------------------------------
-- Welcome card
---------------------------------------------------------------------------

-- Show me: opens the real panel, wherever the player is, and tours it;
-- the tour's last step leads into the editor. Mid-fight it waits for
-- combat to end, saying so on the card.
local function showMe()
    if InCombatLockdown() then
        card.hint:SetText(L.tutorial_welcome_after_combat)
        card.primary:Disable()
        afterCombat = showMe
        return
    end
    -- A pending panel tour is replaced by this one.
    panelTourPending = false
    card:Hide()
    CS.UI.Show()
    local ok, err = pcall(startPanelTour, true)
    if not ok then
        print(L.tutorial_error .. " (" .. tostring(err) .. ")")
    end
end

local function buildCard()
    local window = CS.UI.CreateStyledWindow(CARD_NAME, CARD_WIDTH, L.tutorial_welcome_title)
    table.insert(UISpecialFrames, CARD_NAME) -- Esc closes it

    window.body = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    window.body:SetJustifyH("LEFT")
    window.body:SetSpacing(3)

    window.hint = window:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    window.hint:SetJustifyH("LEFT")

    window.primary = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    window.primary:SetSize(140, 24)
    window.primary:SetText(L.tutorial_welcome_primary)
    window.primary:SetScript("OnClick", showMe)

    window.later = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    window.later:SetSize(110, 24)
    window.later:SetText(L.tutorial_welcome_later)
    window.later:SetScript("OnClick", function()
        window:Hide()
    end)

    -- One popup at a time: a panel tour that came due while the card was
    -- up starts once it's gone. A Show me still waiting on combat is
    -- dropped if the card is closed.
    window:HookScript("OnHide", function()
        if afterCombat == showMe then
            afterCombat = nil
        end
        if panelTourPending and CS.UI.IsPanelShown() then
            local ok, err = pcall(startPanelTour)
            if not ok then
                print(L.tutorial_error .. " (" .. tostring(err) .. ")")
            end
        end
    end)

    return window
end

-- Re-lays out the card's contents for the active panel style, which can
-- change between showings.
local function layoutCard()
    local look = card:ApplyStyle()
    local inset = card.contentInset
    card.body:SetText(L.tutorial_welcome_body)
    card.body:SetTextColor(unpack(look.text))
    card.hint:SetText(L.tutorial_welcome_hint)
    card.primary:Enable()

    local textWidth = CARD_WIDTH - inset.left - inset.right
    card.body:ClearAllPoints()
    card.body:SetPoint("TOPLEFT", card, "TOPLEFT", inset.left, -inset.top)
    card.body:SetWidth(textWidth)
    card.hint:ClearAllPoints()
    card.hint:SetPoint("TOPLEFT", card.body, "BOTTOMLEFT", 0, -12)
    card.hint:SetWidth(textWidth)

    card.later:ClearAllPoints()
    card.later:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -inset.right, inset.bottom)
    card.primary:ClearAllPoints()
    card.primary:SetPoint("RIGHT", card.later, "LEFT", -8, 0)

    card:SetHeight(inset.top + card.body:GetStringHeight() + 12 + card.hint:GetStringHeight()
        + 16 + 24 + inset.bottom)
end

-- Shows the card now. Marked seen as soon as it's shown, and also if
-- building it throws, so a broken card never re-errors on every login.
local function showCard()
    cardShowPending = false
    cardCombatDeferred = false
    if activeTour then
        -- A panel tour the card interrupts resumes once the card is gone.
        if activeTour.part ~= "editor" then
            panelTourPending = true
        end
        endTour("replaced")
    end
    local ok, err = pcall(function()
        card = card or buildCard()
        layoutCard()
        card:ClearAllPoints()
        card:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
        card:Show()
    end)
    CS.Tutorial.MarkSeen(db(), "welcome")
    if not ok then
        if card then
            card:Hide()
        end
        print(L.tutorial_error .. " (" .. tostring(err) .. ")")
    end
end

local function tryShowCard()
    if InCombatLockdown() then
        cardShowPending = true
        cardCombatDeferred = true
        return
    end
    showCard()
end

-- `/campfire tutorial` and the editor's Replay button.
function CS.Tutorial.Replay()
    tryShowCard()
    if cardCombatDeferred then
        print(L.tutorial_after_combat)
    end
end

-- `/campfire tutorial reset`.
function CS.Tutorial.ResetAll()
    CS.Tutorial.Reset(db())
    print(L.tutorial_reset_done)
end

-- Called once from Core.lua's ADDON_LOADED handler, after the saved
-- variables are bootstrapped. Whether the card is due is decided there;
-- it's shown from PLAYER_LOGIN plus a short delay, or after combat.
function CS.Tutorial.Init()
    L = CS.Data.L
    -- Decided now, while the saved variables are fresh: the panel can
    -- auto-open before PLAYER_LOGIN if the player logs in at a fire, and
    -- its tour has to wait for the card.
    cardShowPending = CS.Tutorial.IsDue(db(), "welcome")
    eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PLAYER_LOGIN")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_LOGIN" then
            if cardShowPending then
                C_Timer.After(CS.Tutorial.WELCOME_DELAY_SECONDS, tryShowCard)
            end
        elseif event == "PLAYER_REGEN_ENABLED" then
            if InCombatLockdown() then
                return
            end
            if cardCombatDeferred then
                showCard()
            end
            local action = afterCombat
            afterCombat = nil
            if action then
                action()
            end
        end
    end)
end
