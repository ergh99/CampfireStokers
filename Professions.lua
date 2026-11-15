local CS = select(2, ...)

---@class CampfireStokersProfessions
CS.Professions = CS.Professions or {}

local L = CS.Data.L

-- One entry per profession's tier-1 campfire feature - a placeable object
-- that augments the sit-at-campfire buff for anyone who benefits from
-- that fire, not just the player who placed it (Engineering's Reagent
-- Bot is the one exception - interactable, spawns a vendor - but needs
-- no special handling here; this add-on's job ends at use/craft/request
-- regardless of what the object does after placement). Tiers 2/3 are
-- out of scope - see docs/definition.md's Future Scope section. Cooking
-- is deliberately excluded: its tier-1 campfire feature (Basic Campfire Kit)
-- creates the initial campfire rather than extending one, and this
-- panel only ever shows when a campfire already exists. Data confirmed
-- in docs/research.txt; Tailoring is the one campfire feature with two real
-- underlying items (one per faction).
CS.Professions.FEATURES = {
    { id = "fishing", itemName = L.feature_fishbowl, itemId = 279967, recipeSpellId = 1229745 },
    { id = "alchemy", itemName = L.feature_manawell, itemId = 279956, recipeSpellId = 1230564 },
    { id = "herbalism", itemName = L.feature_incensecandle, itemId = 279962, recipeSpellId = 1229705 },
    { id = "firstaid", itemName = L.feature_firstaidkit, itemId = 279968, recipeSpellId = 1230117 },
    { id = "enchanting", itemName = L.feature_enchantedlute, itemId = 279976, recipeSpellId = 1230643 },
    { id = "leatherworking", itemName = L.feature_camptent, itemId = 279978, recipeSpellId = 1229432 },
    { id = "engineering", itemName = L.feature_reagentbot, itemId = 279950, recipeSpellId = 1230656 },
    { id = "blacksmithing", itemName = L.feature_sharpeningwheel, itemId = 279944, recipeSpellId = 1230171 },
    {
        id = "tailoring",
        itemName = L.feature_factionbanner,
        itemId = { Alliance = 279973, Horde = 279972 },
        recipeSpellId = { Alliance = 1263425, Horde = 1229504 },
    },
    { id = "mining", itemName = L.feature_lodestone, itemId = 279960, recipeSpellId = 1230161 },
    { id = "skinning", itemName = L.feature_campchair, itemId = 279979, recipeSpellId = 1229517 },
}

-- Pure: resolves a (possibly faction-variant) FEATURES entry to concrete
-- itemId/recipeSpellId for this character. Only Tailoring's Faction
-- Banner varies by faction; every other entry's ids are already plain
-- numbers and pass through unchanged. `options.getFaction` defaults to
-- UnitFactionGroup("player"); an unrecognized faction (e.g. "Neutral")
-- falls back to the Alliance variant rather than erroring.
function CS.Professions.ResolveEntry(entry, options)
    options = options or {}

    if type(entry.itemId) ~= "table" then
        return entry.itemId, entry.recipeSpellId
    end

    local getFaction = options.getFaction or function()
        return (UnitFactionGroup("player"))
    end
    local faction = getFaction()

    return entry.itemId[faction] or entry.itemId.Alliance,
        entry.recipeSpellId[faction] or entry.recipeSpellId.Alliance
end

-- Pure except for injected lookups (all default to the real
-- C_TradeSkillUI/C_Item functions, matching the DI style
-- Detection.EvaluateState/Send.Classify already use). Decides what
-- clicking this campfire feature's button would do right now, without doing it.
-- `options`:
--   isRecipeProfessionLearned(id) defaults to C_TradeSkillUI.IsRecipeProfessionLearned
--   getRecipeInfo(id)             defaults to C_TradeSkillUI.GetRecipeInfo
--   getItemCount(id)              defaults to C_Item.GetItemCount
--   getRecipeSchematic(id, bool)  defaults to C_TradeSkillUI.GetRecipeSchematic
--   getFaction()                  see ResolveEntry
-- Confirmed in-client 2026-10-04 (see docs/decision-log.md):
-- IsRecipeProfessionLearned is the real per-character "do I know this"
-- gate - GetRecipeInfo's own `craftable` field returns true even for a
-- profession the character doesn't have at all, so it can't be used for
-- this.
-- `GetCraftableCount` is deliberately NOT used, despite initially
-- looking like the obvious craft-vs-request gate: reported from
-- in-client testing, it returned 0 for two recipes (Blacksmithing,
-- Mining) while the character held 46x/62x of the only two reagents
-- the schematic actually requires (1 each) - it can be 0 for reasons
-- that have nothing to do with missing materials (a cooldown or
-- similar). The schematic-vs-bag-count walk below is the only signal
-- used, since it's the one that's actually about materials.
-- Returns one of:
--   { visible = false }
--   { visible = true, action = "use", itemId, itemName, icon, entry }
--   { visible = true, action = "craft", recipeSpellId, icon, entry }
--   { visible = true, action = "request", itemId, itemName, recipeSpellId,
--     icon, missing = { { itemId, have, need, missingCount }, ... }, entry }
function CS.Professions.EvaluateFeature(entry, options)
    options = options or {}

    local isRecipeProfessionLearned = options.isRecipeProfessionLearned
        or (C_TradeSkillUI and C_TradeSkillUI.IsRecipeProfessionLearned)
    local getRecipeInfo = options.getRecipeInfo
        or (C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo)
    local getItemCount = options.getItemCount or (C_Item and C_Item.GetItemCount)
    local getRecipeSchematic = options.getRecipeSchematic
        or (C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic)

    if not (isRecipeProfessionLearned and getRecipeInfo and getItemCount and getRecipeSchematic) then
        return { visible = false }
    end

    local itemId, recipeSpellId = CS.Professions.ResolveEntry(entry, options)

    if not isRecipeProfessionLearned(recipeSpellId) then
        return { visible = false }
    end

    local recipeInfo = getRecipeInfo(recipeSpellId)
    local icon = recipeInfo and recipeInfo.icon

    if (getItemCount(itemId) or 0) > 0 then
        return {
            visible = true,
            action = "use",
            itemId = itemId,
            itemName = entry.itemName,
            icon = icon,
            entry = entry,
        }
    end

    local missing = {}
    local schematic = getRecipeSchematic(recipeSpellId, false)
    for _, slot in ipairs((schematic and schematic.reagentSlotSchematics) or {}) do
        local reagent = slot.reagents and slot.reagents[1]
        if reagent and reagent.itemID then
            local need = slot.quantityRequired or 1
            local have = getItemCount(reagent.itemID) or 0
            if have < need then
                table.insert(missing, {
                    itemId = reagent.itemID,
                    have = have,
                    need = need,
                    missingCount = need - have,
                })
            end
        end
    end

    if #missing == 0 then
        return {
            visible = true,
            action = "craft",
            recipeSpellId = recipeSpellId,
            icon = icon,
            entry = entry,
        }
    end

    return {
        visible = true,
        action = "request",
        itemId = itemId,
        itemName = entry.itemName,
        recipeSpellId = recipeSpellId,
        icon = icon,
        missing = missing,
        entry = entry,
    }
end

-- Reads one campfire feature's item cooldown. Placing any campfire
-- feature puts every campfire feature's Use on one shared cooldown, so each item's own
-- cooldown already reflects it - no grouping needed here. Returns
-- start, duration while a cooldown is running, nil otherwise.
-- `options`:
--   getItemCooldown(id) -> start, duration, enable  defaults to
--     C_Item.GetItemCooldown, falling back to C_Container.GetItemCooldown
--     (retail has both; neither is confirmed on Forever yet).
--   canAccessValue(v)  defaults to canaccessvalue. Cooldown data may be
--     secret while addon restrictions are active; a value we can't read
--     is treated as "no cooldown" rather than compared against.
function CS.Professions.GetItemCooldown(itemId, options)
    options = options or {}
    local getItemCooldown = options.getItemCooldown
        or (C_Item and C_Item.GetItemCooldown)
        or (C_Container and C_Container.GetItemCooldown)
    local canAccessValue = options.canAccessValue or canaccessvalue
    if not getItemCooldown then
        return nil
    end

    local start, duration, enable = getItemCooldown(itemId)
    if canAccessValue and not (canAccessValue(start) and canAccessValue(duration) and canAccessValue(enable)) then
        return nil
    end
    if type(start) ~= "number" or type(duration) ~= "number" or duration <= 0 then
        return nil
    end
    -- Older clients return enable as 0/1, newer ones as a boolean; either
    -- "off" value means the cooldown hasn't actually started counting.
    if enable == false or enable == 0 then
        return nil
    end
    return start, duration
end

-- The global cooldown is at most 1.5 seconds; an item cooldown this short
-- or shorter is that, not the shared campfire feature cooldown.
CS.Professions.GLOBAL_COOLDOWN_MAX_SECONDS = 1.5

-- Applied when a Use isn't followed by a readable shared cooldown.
-- Observed in-client: the cooldown is only readable while some campfire
-- feature item is still in the bags, so using the last one left nothing
-- to read it from.
CS.Professions.FORCED_COOLDOWN_SECONDS = 3600

-- GetTime()-based start of the forced cooldown, or nil. Session-only:
-- not saved, so it's gone after a reload.
local forcedCooldownStart

local function isFeatureCooldown(duration)
    return duration ~= nil and duration > CS.Professions.GLOBAL_COOLDOWN_MAX_SECONDS
end

-- Called shortly after a campfire feature's Use. Reports the detected
-- cooldown through CS.Debug and, if none is readable, starts the forced
-- one. `options` is passed through to GetItemCooldown, plus
-- getTime() defaulting to GetTime.
-- Returns start, duration of whichever cooldown now applies.
function CS.Professions.CheckCooldownAfterUse(itemId, options)
    options = options or {}
    local getTime = options.getTime or GetTime
    local now = getTime()

    local start, duration = CS.Professions.GetItemCooldown(itemId, options)
    if isFeatureCooldown(duration) then
        forcedCooldownStart = nil
        CS.Debug(string.format("Use of item %s: detected cooldown start=%.1f duration=%.1f (%.0fs left).",
            tostring(itemId), start, duration, start + duration - now))
        return start, duration
    end

    forcedCooldownStart = now
    CS.Debug(string.format("Use of item %s: no cooldown detected (start=%s duration=%s); forcing %ds.",
        tostring(itemId), tostring(start), tostring(duration), CS.Professions.FORCED_COOLDOWN_SECONDS))
    return forcedCooldownStart, CS.Professions.FORCED_COOLDOWN_SECONDS
end

-- The cooldown a campfire feature's Use button should show: the real one
-- when readable, else the forced one while it lasts, else whatever
-- GetItemCooldown returned (nil, or a global-cooldown sweep).
-- `options` as CheckCooldownAfterUse.
function CS.Professions.GetFeatureCooldown(itemId, options)
    options = options or {}
    local start, duration = CS.Professions.GetItemCooldown(itemId, options)
    if isFeatureCooldown(duration) then
        return start, duration
    end

    if forcedCooldownStart then
        local getTime = options.getTime or GetTime
        if getTime() < forcedCooldownStart + CS.Professions.FORCED_COOLDOWN_SECONDS then
            return forcedCooldownStart, CS.Professions.FORCED_COOLDOWN_SECONDS
        end
        forcedCooldownStart = nil
    end
    return start, duration
end

-- Pure. "an" before a name starting with a vowel letter, "a" otherwise.
-- Letter-based, not sound-based: right for all 11 FEATURES names ("an
-- Incense Candle", "an Enchanted Lute", "a" for the rest), none of which
-- start with a silent "h" or a "you"-sounding "u"/"eu".
function CS.Professions.IndefiniteArticle(name)
    if name and name:match("^%s*[AEIOUaeiou]") then
        return "an"
    end
    return "a"
end

-- Builds the confirmed yell template: "I can place a/an <item link> at
-- the campfire if someone wants to provide <list>." - with "a" or "an"
-- chosen from the item's plain name via IndefiniteArticle. `options`:
--   getItemInfo(id) -> name, link, ...  defaults to C_Item.GetItemInfo.
--     Used for both the main item AND each missing reagent, preferring
--     the link over the plain name for both (confirmed in-client that
--     reagent links resolve the same way the main item's does - there
--     was no real obstacle to it, just an earlier design that only
--     ever asked for the reagent's name). The main item still falls
--     back to its own known entry.itemName - a string this add-on
--     controls, so showing it plain is harmless - if neither link nor
--     name resolve. C_Item.GetItemLink/GetItemNameByID were tried
--     first but both only reflect the client's async item-data cache -
--     GetItemLink needs the item owned (confirmed 2026-10-04) and
--     GetItemNameByID turned out to have the exact same "not cached
--     yet" gap GetItemInfo does. Consolidating on one API means one
--     cache, warmed once by WarmItemCache below, instead of two.
-- Returns nil, not a message with a raw item id in it, if ANY missing
-- reagent has neither a link nor a name available - unlike the main
-- item, a reagent has no safe fallback string of our own, and
-- broadcasting "item 6291" in a public yell is not acceptable, so the
-- caller must not send anything when this returns nil.
function CS.Professions.BuildRequestMessage(entry, itemId, missing, options)
    options = options or {}
    local getItemInfo = options.getItemInfo or (C_Item and C_Item.GetItemInfo)

    local itemName, itemLink
    if getItemInfo then
        itemName, itemLink = getItemInfo(itemId)
    end
    local link = itemLink or itemName or entry.itemName

    local parts = {}
    for _, missingReagent in ipairs(missing) do
        local reagentName, reagentLink
        if getItemInfo then
            reagentName, reagentLink = getItemInfo(missingReagent.itemId)
        end
        local display = reagentLink or reagentName
        if not display then
            return nil
        end
        table.insert(parts, missingReagent.missingCount .. " " .. display)
    end

    local article = CS.Professions.IndefiniteArticle(itemName or entry.itemName)
    return "I can place " .. article .. " " .. link .. " at the campfire if someone wants to provide "
        .. table.concat(parts, ", ") .. "."
end

-- Recipe this module last opened via OpenRecipe, so a second click only
-- crafts when the shown ProfessionsFrame is the one Craft itself opened
-- for that same recipe (not a panel the player opened on something else).
local openedRecipeSpellId

-- Impure. Two clicks, per docs/craft-profession-switch-findings.md: a
-- single click doing OpenRecipe -> CraftRecipe -> hide produced no cast
-- once a different profession had been opened by hand (Rounds 7, 9),
-- while OpenRecipe on one click and CraftRecipe -> hide on a later click,
-- with ProfessionsFrame still shown in between, crafted (Rounds 14-16).
-- CraftRecipe must run inside the click itself - deferring it with
-- C_Timer.After produced no cast (Rounds 11, 12) - and hiding the frame
-- between the two clicks broke it (Round 13).
-- Returns "opened" for the first click and "crafted" for the second.
-- `options.openRecipe`/`craftRecipe` default to the real
-- C_TradeSkillUI functions; `options.isFrameShown`/`hideFrame` default
-- to checking/hiding the real ProfessionsFrame.
function CS.Professions.Craft(recipeSpellId, options)
    options = options or {}
    local openRecipe = options.openRecipe or (C_TradeSkillUI and C_TradeSkillUI.OpenRecipe)
    local craftRecipe = options.craftRecipe or (C_TradeSkillUI and C_TradeSkillUI.CraftRecipe)
    local isFrameShown = options.isFrameShown or function()
        return ProfessionsFrame ~= nil and ProfessionsFrame:IsShown()
    end
    local hideFrame = options.hideFrame or function()
        if ProfessionsFrame then
            ProfessionsFrame:Hide()
        end
    end

    if openedRecipeSpellId ~= recipeSpellId or not isFrameShown() then
        openedRecipeSpellId = recipeSpellId
        if openRecipe then
            openRecipe(recipeSpellId)
        end
        return "opened"
    end

    openedRecipeSpellId = nil
    if craftRecipe then
        craftRecipe(recipeSpellId)
    end
    hideFrame()
    return "crafted"
end

-- Fire-and-forget: touches C_Item.GetItemInfo for every campfire feature's item id
-- (both faction variants for Tailoring), and every one of their
-- reagent item ids too, to start the client's async item-data cache
-- fetch early rather than the first time a request message needs an
-- item's link/name. Confirmed in-client: both the main item's link and
-- a missing reagent's name/link fell back to placeholder text the
-- first time they were ever referenced, before the cache caught up.
-- Deliberately NOT gated on IsRecipeProfessionLearned (unlike
-- EvaluateFeature) - confirmed in-client 2026-10-05: gating it that way
-- silently skipped reagent warming entirely, because
-- IsRecipeProfessionLearned isn't reliable this early in the login
-- sequence (ADDON_LOADED fires before profession data is necessarily
-- populated) - the main item warmed fine since it isn't gated, but
-- every reagent lookup fell through to "warm it for the first time at
-- actual click time" instead, which is exactly the race this function
-- exists to avoid. Recipe reagent *definitions* are static game data,
-- not character-specific, so warming them unconditionally for all 11
-- campfire features costs a few harmless extra API calls and removes the timing
-- dependency entirely. This narrows the remaining race (items are
-- "seen" at ADDON_LOADED instead of at first use) but can't fully
-- close it for an item referenced within the first moments after
-- login, before the fetch completes. `options` mirrors EvaluateFeature's
-- DI surface (getRecipeSchematic, getFaction) plus getItemInfo.
function CS.Professions.WarmItemCache(options)
    options = options or {}
    local getItemInfo = options.getItemInfo or (C_Item and C_Item.GetItemInfo)
    if not getItemInfo then
        return
    end

    local getRecipeSchematic = options.getRecipeSchematic
        or (C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic)

    for _, entry in ipairs(CS.Professions.FEATURES) do
        if type(entry.itemId) == "table" then
            for _, itemId in pairs(entry.itemId) do
                getItemInfo(itemId)
            end
        else
            getItemInfo(entry.itemId)
        end

        if getRecipeSchematic then
            local _, recipeSpellId = CS.Professions.ResolveEntry(entry, options)
            local schematicOk, schematic = pcall(getRecipeSchematic, recipeSpellId, false)
            if schematicOk and schematic then
                for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
                    local reagent = slot.reagents and slot.reagents[1]
                    if reagent and reagent.itemID then
                        getItemInfo(reagent.itemID)
                    end
                end
            end
        end
    end
end

-- Creates (or wires up an injected) event frame that live-refreshes the
-- profession block while the panel is open. BAG_UPDATE_DELAYED covers
-- both reagent and craft-output changes - confirmed in-client
-- 2026-10-04 to fire reliably. TRADE_SKILL_CRAFT_RESULT was tried and
-- confirmed NOT to exist on this build ("Attempt to register unknown
-- event"), so it isn't registered at all, not even pcall-guarded - see
-- docs/decision-log.md.
function CS.Professions.CreateEventFrame(frame)
    frame = frame or CreateFrame("Frame")

    frame:RegisterEvent("BAG_UPDATE_DELAYED")

    frame:SetScript("OnEvent", function()
        if CS.UI.IsPanelShown() then
            CS.UI.Refresh()
        end
    end)

    return frame
end
