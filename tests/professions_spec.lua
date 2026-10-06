local loadModule = require("support.load_module")
local wowStub = require("support.wow_stub")

local tests = {}

local function loadProfessions()
    local CS = {}
    loadModule("Data.lua", "CampfireStokers", CS)
    loadModule("Professions.lua", "CampfireStokers", CS)
    return CS
end

-- GOODS sanity

tests["GOODS has 11 entries with unique ids and non-empty names"] = function()
    local CS = loadProfessions()
    assert(#CS.Professions.GOODS == 11)

    local seenIds = {}
    for _, entry in ipairs(CS.Professions.GOODS) do
        assert(not seenIds[entry.id], "duplicate id: " .. tostring(entry.id))
        seenIds[entry.id] = true
        assert(type(entry.itemName) == "string" and #entry.itemName > 0)
    end
end

tests["only Tailoring's ids are faction-variant tables"] = function()
    local CS = loadProfessions()
    for _, entry in ipairs(CS.Professions.GOODS) do
        if entry.id == "tailoring" then
            assert(type(entry.itemId) == "table" and entry.itemId.Alliance and entry.itemId.Horde)
            assert(type(entry.recipeSpellId) == "table" and entry.recipeSpellId.Alliance
                and entry.recipeSpellId.Horde)
        else
            assert(type(entry.itemId) == "number", entry.id .. "'s itemId should be a plain number")
            assert(type(entry.recipeSpellId) == "number", entry.id .. "'s recipeSpellId should be a plain number")
        end
    end
end

-- ResolveEntry

tests["ResolveEntry passes non-variant entries through unchanged"] = function()
    local CS = loadProfessions()
    local entry = { itemId = 111, recipeSpellId = 222 }
    local itemId, recipeSpellId = CS.Professions.ResolveEntry(entry, {
        getFaction = function() return "Horde" end,
    })
    assert(itemId == 111 and recipeSpellId == 222)
end

tests["ResolveEntry resolves Tailoring's Faction Banner by faction"] = function()
    local CS = loadProfessions()
    local entry = {
        itemId = { Alliance = 1, Horde = 2 },
        recipeSpellId = { Alliance = 10, Horde = 20 },
    }

    local itemId, recipeSpellId = CS.Professions.ResolveEntry(entry, {
        getFaction = function() return "Horde" end,
    })
    assert(itemId == 2 and recipeSpellId == 20)

    itemId, recipeSpellId = CS.Professions.ResolveEntry(entry, {
        getFaction = function() return "Alliance" end,
    })
    assert(itemId == 1 and recipeSpellId == 10)
end

tests["ResolveEntry falls back to Alliance for an unrecognized faction"] = function()
    local CS = loadProfessions()
    local entry = {
        itemId = { Alliance = 1, Horde = 2 },
        recipeSpellId = { Alliance = 10, Horde = 20 },
    }

    local itemId, recipeSpellId = CS.Professions.ResolveEntry(entry, {
        getFaction = function() return "Neutral" end,
    })
    assert(itemId == 1 and recipeSpellId == 10)
end

-- EvaluateGood

local TEST_ENTRY = { id = "test", itemName = "Test Item", itemId = 999, recipeSpellId = 5555 }

local function baseGoodOptions(overrides)
    local options = {
        isRecipeProfessionLearned = function() return true end,
        getRecipeInfo = function() return { icon = 12345 } end,
        getItemCount = function() return 0 end,
        getRecipeSchematic = function() return { reagentSlotSchematics = {} } end,
    }
    for key, value in pairs(overrides or {}) do
        options[key] = value
    end
    return options
end

tests["EvaluateGood is invisible when the profession isn't learned"] = function()
    local CS = loadProfessions()
    local result = CS.Professions.EvaluateGood(TEST_ENTRY, baseGoodOptions({
        isRecipeProfessionLearned = function() return false end,
    }))
    assert(result.visible == false)
end

tests["EvaluateGood is invisible when the required APIs aren't available at all"] = function()
    local CS = loadProfessions()
    local result = CS.Professions.EvaluateGood(TEST_ENTRY, {})
    assert(result.visible == false)
end

tests["EvaluateGood returns use when the item is already owned"] = function()
    local CS = loadProfessions()
    local result = CS.Professions.EvaluateGood(TEST_ENTRY, baseGoodOptions({
        getItemCount = function(id) return id == 999 and 2 or 0 end,
    }))
    assert(result.visible == true)
    assert(result.action == "use")
    assert(result.itemId == 999)
    assert(result.itemName == "Test Item")
    assert(result.icon == 12345)
end

tests["EvaluateGood returns craft when not owned but materials are on hand"] = function()
    local CS = loadProfessions()
    local counts = { [111] = 46, [222] = 62 }
    local result = CS.Professions.EvaluateGood(TEST_ENTRY, baseGoodOptions({
        getItemCount = function(id) return counts[id] or 0 end,
        getRecipeSchematic = function()
            return {
                reagentSlotSchematics = {
                    { quantityRequired = 1, reagents = { { itemID = 111 } } },
                    { quantityRequired = 1, reagents = { { itemID = 222 } } },
                },
            }
        end,
    }))
    assert(result.visible == true)
    assert(result.action == "craft")
    assert(result.recipeSpellId == 5555)
end

-- Reported from in-client testing: GetCraftableCount returned 0 for two
-- recipes despite the character holding 46x/62x of the only two
-- reagents required (1 each) - confirming GetCraftableCount can be 0
-- for reasons unrelated to materials and must not be trusted. This is
-- exactly that scenario: plenty of both reagents, so the result must
-- be "craft," never "request" with an empty list.
tests["EvaluateGood returns craft, not an empty request, when reagents are abundant"] = function()
    local CS = loadProfessions()
    local result = CS.Professions.EvaluateGood(TEST_ENTRY, baseGoodOptions({
        getItemCount = function(id)
            if id == 2835 then return 46 end
            if id == 2840 then return 62 end
            return 0
        end,
        getRecipeSchematic = function()
            return {
                reagentSlotSchematics = {
                    { quantityRequired = 1, reagents = { { itemID = 2835 } } },
                    { quantityRequired = 1, reagents = { { itemID = 2840 } } },
                },
            }
        end,
    }))
    assert(result.visible == true)
    assert(result.action == "craft")
end

tests["EvaluateGood returns request with the correct missing list when materials are short"] = function()
    local CS = loadProfessions()
    local counts = { [111] = 1, [222] = 0 }
    local result = CS.Professions.EvaluateGood(TEST_ENTRY, baseGoodOptions({
        getItemCount = function(id) return counts[id] or 0 end,
        getRecipeSchematic = function()
            return {
                reagentSlotSchematics = {
                    { quantityRequired = 2, reagents = { { itemID = 111 } } },
                    { quantityRequired = 1, reagents = { { itemID = 222 } } },
                },
            }
        end,
    }))

    assert(result.visible == true)
    assert(result.action == "request")
    assert(result.itemId == 999 and result.itemName == "Test Item" and result.recipeSpellId == 5555)
    assert(#result.missing == 2)
    assert(result.missing[1].itemId == 111 and result.missing[1].have == 1
        and result.missing[1].need == 2 and result.missing[1].missingCount == 1)
    assert(result.missing[2].itemId == 222 and result.missing[2].have == 0
        and result.missing[2].need == 1 and result.missing[2].missingCount == 1)
end

-- BuildRequestMessage

tests["BuildRequestMessage matches the confirmed template"] = function()
    local CS = loadProfessions()
    local names = { [111] = "Raw Fish", [222] = "Copper Ore" }
    local message = CS.Professions.BuildRequestMessage(
        { itemName = "Fish Bowl" },
        279967,
        { { itemId = 111, missingCount = 2 }, { itemId = 222, missingCount = 1 } },
        {
            getItemInfo = function(id)
                if id == 279967 then
                    return "Fish Bowl", "[Fish Bowl]"
                end
                return names[id]
            end,
        }
    )
    assert(message == "I can place a/an [Fish Bowl] at the campfire if someone wants to provide "
        .. "2 Raw Fish, 1 Copper Ore.")
end

-- Reported from in-client testing: reagent links resolve the same way
-- the main item's does - there was never a real obstacle to it, the
-- earlier design just only ever asked for the reagent's name. A
-- missing reagent's link should be preferred over its plain name.
tests["BuildRequestMessage prefers a missing reagent's link over its name"] = function()
    local CS = loadProfessions()
    local message = CS.Professions.BuildRequestMessage(
        { itemName = "Fish Bowl" },
        279967,
        { { itemId = 111, missingCount = 2 } },
        {
            getItemInfo = function(id)
                if id == 279967 then
                    return "Fish Bowl", "[Fish Bowl]"
                end
                return "Raw Fish", "[Raw Fish]"
            end,
        }
    )
    assert(message == "I can place a/an [Fish Bowl] at the campfire if someone wants to provide "
        .. "2 [Raw Fish].")
end

tests["BuildRequestMessage falls back to the entry's item name without an item-info resolver"] = function()
    local CS = loadProfessions()
    local message = CS.Professions.BuildRequestMessage(
        { itemName = "Fish Bowl" },
        279967,
        {},
        { getItemInfo = function() return nil end }
    )
    assert(message:find("a/an Fish Bowl", 1, true) ~= nil)
end

-- Confirmed from in-client testing: broadcasting a raw "item <id>"
-- fallback in a public yell is unacceptable, since unlike the main
-- item's entry.itemName (a string this add-on controls and trusts),
-- a reagent's name only ever comes from the API with no safe fallback
-- of our own. BuildRequestMessage must refuse to build a message at
-- all in that case, not paper over it with a placeholder.
tests["BuildRequestMessage returns nil rather than leak a missing reagent's bare item id"] = function()
    local CS = loadProfessions()
    local message = CS.Professions.BuildRequestMessage(
        { itemName = "Fish Bowl" },
        279967,
        { { itemId = 111, missingCount = 3 } },
        { getItemInfo = function(id) return id == 279967 and "Fish Bowl" or nil end }
    )
    assert(message == nil)
end

-- Craft: DI, same style as EvaluateGood/BuildRequestMessage. Confirmed
-- in-client 2026-10-05: a bare CraftRecipe call does nothing at all
-- without OpenRecipe first, and hiding the frame immediately after
-- does not interrupt the resulting cast - so the real sequence is
-- OpenRecipe -> CraftRecipe -> hide the frame, in that order.

tests["Craft calls OpenRecipe, then CraftRecipe, then hides the frame, in order"] = function()
    local CS = loadProfessions()
    local calls = {}
    CS.Professions.Craft(1230161, {
        openRecipe = function(id) table.insert(calls, { "open", id }) end,
        craftRecipe = function(id) table.insert(calls, { "craft", id }) end,
        hideFrame = function() table.insert(calls, { "hide" }) end,
    })

    assert(#calls == 3)
    assert(calls[1][1] == "open" and calls[1][2] == 1230161)
    assert(calls[2][1] == "craft" and calls[2][2] == 1230161)
    assert(calls[3][1] == "hide")
end

tests["Craft still hides the frame even if openRecipe/craftRecipe aren't available"] = function()
    local CS = loadProfessions()
    local hidden = false
    local ok = pcall(CS.Professions.Craft, 1230161, {
        hideFrame = function() hidden = true end,
    })
    assert(ok == true)
    assert(hidden == true)
end

-- WarmItemCache

tests["WarmItemCache touches every good's item id, including both Tailoring variants"] = function()
    local CS = loadProfessions()
    local touched = {}
    CS.Professions.WarmItemCache({
        getItemInfo = function(itemId) touched[itemId] = true end,
    })

    for _, entry in ipairs(CS.Professions.GOODS) do
        if type(entry.itemId) == "table" then
            assert(touched[entry.itemId.Alliance], "Alliance variant should be touched")
            assert(touched[entry.itemId.Horde], "Horde variant should be touched")
        else
            assert(touched[entry.itemId], entry.id .. "'s item id should be touched")
        end
    end
end

-- Confirmed in-client 2026-10-05: gating this on IsRecipeProfessionLearned
-- (like EvaluateGood does) silently skipped reagent warming entirely,
-- since that check isn't reliable this early in the login sequence.
-- Reagent definitions are static game data, not character-specific, so
-- this now warms them for every good unconditionally - no learned-gate
-- to test around.
tests["WarmItemCache touches every good's reagent item ids too, regardless of learned status"] = function()
    local CS = loadProfessions()
    local touched = {}
    CS.Professions.WarmItemCache({
        getItemInfo = function(itemId) touched[itemId] = true end,
        getRecipeSchematic = function()
            return { reagentSlotSchematics = { { reagents = { { itemID = 777 } } } } }
        end,
        getFaction = function() return "Alliance" end,
    })
    assert(touched[777], "a reagent item id should be warmed regardless of learned status")
end

tests["WarmItemCache does nothing when no getItemInfo is available"] = function()
    local CS = loadProfessions()
    local ok = pcall(CS.Professions.WarmItemCache, {})
    assert(ok == true, "must not error when C_Item.GetItemInfo isn't available")
end

-- CreateEventFrame

tests["CreateEventFrame registers BAG_UPDATE_DELAYED"] = function()
    local CS = loadProfessions()
    CS.UI = { IsPanelShown = function() return false end }
    local frame = CS.Professions.CreateEventFrame(wowStub.makeFakeFrame())
    assert(frame.events.BAG_UPDATE_DELAYED == true)
end

tests["CreateEventFrame refreshes only while the panel is shown"] = function()
    local CS = loadProfessions()
    local refreshCalls = 0
    local shown = false
    CS.UI = {
        IsPanelShown = function() return shown end,
        Refresh = function() refreshCalls = refreshCalls + 1 end,
    }
    local frame = CS.Professions.CreateEventFrame(wowStub.makeFakeFrame())

    frame:Fire("OnEvent", "BAG_UPDATE_DELAYED")
    assert(refreshCalls == 0, "must not refresh a hidden panel")

    shown = true
    frame:Fire("OnEvent", "BAG_UPDATE_DELAYED")
    assert(refreshCalls == 1)
end

return tests
