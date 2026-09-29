local loadModule = require("support.load_module")

local tests = {}

local function loadData()
    local CS = {}
    loadModule("Data.lua", "CampfireStokers", CS)
    return CS.Data
end

tests["DefaultTree holds five categories, in the documented order"] = function()
    local Data = loadData()
    local expectedIds = {
        "cat_icebreakers", "cat_trading", "cat_professions", "cat_infoadvice", "cat_emotes",
    }
    assert(#Data.DefaultTree == #expectedIds,
        "expected " .. #expectedIds .. " categories, got " .. #Data.DefaultTree)
    for i, expectedId in ipairs(expectedIds) do
        assert(Data.DefaultTree[i].id == expectedId,
            string.format("position %d: expected %s, got %s", i, expectedId, Data.DefaultTree[i].id))
    end
end

tests["DefaultTree holds exactly nine phrases"] = function()
    local Data = loadData()
    local count = 0
    for _, category in ipairs(Data.DefaultTree) do
        count = count + #category.children
    end
    assert(count == 9, "expected 9 phrases, got " .. count)
end

tests["every node id is unique"] = function()
    local Data = loadData()
    local seen = {}
    for _, category in ipairs(Data.DefaultTree) do
        assert(not seen[category.id], "duplicate id: " .. tostring(category.id))
        seen[category.id] = true
        for _, phrase in ipairs(category.children) do
            assert(not seen[phrase.id], "duplicate id: " .. tostring(phrase.id))
            seen[phrase.id] = true
        end
    end
end

tests["every phrase text is at most 255 characters"] = function()
    local Data = loadData()
    for _, category in ipairs(Data.DefaultTree) do
        for _, phrase in ipairs(category.children) do
            assert(#phrase.text <= 255,
                phrase.id .. " is " .. #phrase.text .. " characters, over the 255 limit")
        end
    end
end

tests["every node's name or text resolves against the locale table by id"] = function()
    local Data = loadData()
    local L = Data.L
    for _, category in ipairs(Data.DefaultTree) do
        assert(L[category.id] ~= nil, "no L entry for " .. category.id)
        assert(category.name == L[category.id], category.id .. " name doesn't match its L entry")
        for _, phrase in ipairs(category.children) do
            assert(L[phrase.id] ~= nil, "no L entry for " .. phrase.id)
            assert(phrase.text == L[phrase.id], phrase.id .. " text doesn't match its L entry")
        end
    end
end

return tests
