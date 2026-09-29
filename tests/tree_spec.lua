local loadModule = require("support.load_module")

local tests = {}

local function loadTree()
    local CS = {}
    loadModule("Data.lua", "CampfireStokers", CS)
    loadModule("Tree.lua", "CampfireStokers", CS)
    return CS
end

local function countNodes(tree)
    local categories, phrases = 0, 0
    for _, category in ipairs(tree) do
        categories = categories + 1
        phrases = phrases + #category.children
    end
    return categories, phrases
end

-- Bootstrap

tests["Bootstrap deep-copies DefaultTree on first load and never mutates it"] = function()
    local CS = loadTree()
    local db = CS.Tree.Bootstrap({})

    local categories, phrases = countNodes(db.tree)
    assert(categories == 5 and phrases == 9, "expected 5 categories / 9 phrases from a fresh bootstrap")
    assert(db.schemaVersion == CS.Data.SCHEMA_VERSION)
    assert(next(db.deletedDefaultIds) == nil, "a fresh install has no deleted defaults")

    db.tree[1].name = "mutated"
    table.remove(db.tree[1].children, 1)
    assert(CS.Data.DefaultTree[1].name == "Icebreakers", "DefaultTree must not be mutated")
    assert(#CS.Data.DefaultTree[1].children == 3, "DefaultTree must not be mutated")
end

tests["Bootstrap on an existing db runs Migrate instead of re-copying defaults"] = function()
    local CS = loadTree()
    local db = CS.Tree.Bootstrap({})
    CS.Tree.RenameCategory(db, "cat_icebreakers", "Renamed")

    local rebootstrapped = CS.Tree.Bootstrap(db)

    assert(rebootstrapped.tree[1].name == "Renamed", "an existing tree's edits must survive Bootstrap")
end

-- Operations

tests["AddCategory appends a category with a generated id"] = function()
    local CS = loadTree()
    local db = CS.Tree.Bootstrap({})
    local category = CS.Tree.AddCategory(db, "My Category")
    assert(category.type == "category")
    assert(category.name == "My Category")
    assert(type(category.id) == "string" and category.id ~= "")
    assert(db.tree[#db.tree] == category)
end

tests["AddPhrase appends a phrase to the named category"] = function()
    local CS = loadTree()
    local db = CS.Tree.Bootstrap({})
    local phrase, err = CS.Tree.AddPhrase(db, "cat_trading", "Selling stuff")
    assert(phrase and not err)
    assert(phrase.type == "phrase")
    assert(phrase.text == "Selling stuff")

    local category = db.tree[2]
    assert(category.id == "cat_trading")
    assert(category.children[#category.children] == phrase)
end

tests["AddPhrase rejects an unknown category"] = function()
    local CS = loadTree()
    local db = CS.Tree.Bootstrap({})
    local phrase, err = CS.Tree.AddPhrase(db, "cat_does_not_exist", "text")
    assert(phrase == nil and err ~= nil)
end

tests["AddPhrase rejects text over 255 characters, the only validation"] = function()
    local CS = loadTree()
    local db = CS.Tree.Bootstrap({})
    local tooLong = string.rep("x", 256)
    local phrase, err = CS.Tree.AddPhrase(db, "cat_trading", tooLong)
    assert(phrase == nil and err ~= nil)

    local exactly255 = string.rep("x", 255)
    local ok = CS.Tree.AddPhrase(db, "cat_trading", exactly255)
    assert(ok ~= nil, "255 characters exactly must be accepted")
end

tests["RenameCategory renames an existing category"] = function()
    local CS = loadTree()
    local db = CS.Tree.Bootstrap({})
    local ok = CS.Tree.RenameCategory(db, "cat_emotes", "Roleplay")
    assert(ok == true)
    assert(db.tree[5].name == "Roleplay")
end

tests["RenameCategory rejects an unknown id"] = function()
    local CS = loadTree()
    local db = CS.Tree.Bootstrap({})
    local ok, err = CS.Tree.RenameCategory(db, "nope", "x")
    assert(ok == false and err ~= nil)
end

tests["EditPhraseText edits an existing phrase and enforces the 255 limit"] = function()
    local CS = loadTree()
    local db = CS.Tree.Bootstrap({})
    local ok = CS.Tree.EditPhraseText(db, "trading_spare", "Updated text")
    assert(ok == true)

    local category = db.tree[2]
    assert(category.children[1].text == "Updated text")

    local rejected, err = CS.Tree.EditPhraseText(db, "trading_spare", string.rep("x", 256))
    assert(rejected == false and err ~= nil)
    assert(category.children[1].text == "Updated text", "a rejected edit must not apply")
end

tests["Delete removes a category and records its default id"] = function()
    local CS = loadTree()
    local db = CS.Tree.Bootstrap({})
    local ok = CS.Tree.Delete(db, "cat_professions")
    assert(ok == true)

    local categories = countNodes(db.tree)
    assert(categories == 4)
    assert(db.deletedDefaultIds["cat_professions"] == true)
end

tests["Delete removes a phrase and records its default id"] = function()
    local CS = loadTree()
    local db = CS.Tree.Bootstrap({})
    local ok = CS.Tree.Delete(db, "emotes_salute")
    assert(ok == true)

    local category = db.tree[5]
    assert(#category.children == 1)
    assert(category.children[1].id == "emotes_warmfire")
    assert(db.deletedDefaultIds["emotes_salute"] == true)
end

tests["Delete does not record a player-created node as a deleted default"] = function()
    local CS = loadTree()
    local db = CS.Tree.Bootstrap({})
    local category = CS.Tree.AddCategory(db, "Temp")
    CS.Tree.Delete(db, category.id)
    assert(db.deletedDefaultIds[category.id] == nil)
end

tests["Delete rejects an unknown id"] = function()
    local CS = loadTree()
    local db = CS.Tree.Bootstrap({})
    local ok, err = CS.Tree.Delete(db, "nope")
    assert(ok == false and err ~= nil)
end

tests["Reorder moves a category to a new position"] = function()
    local CS = loadTree()
    local db = CS.Tree.Bootstrap({})
    local ok = CS.Tree.Reorder(db, "cat_emotes", 1)
    assert(ok == true)
    assert(db.tree[1].id == "cat_emotes")
    assert(db.tree[2].id == "cat_icebreakers")
end

tests["Reorder moves a phrase within its category"] = function()
    local CS = loadTree()
    local db = CS.Tree.Bootstrap({})
    local category = db.tree[1]
    local ok = CS.Tree.Reorder(db, "icebreakers_hope", 1)
    assert(ok == true)
    assert(category.children[1].id == "icebreakers_hope")
end

tests["Reorder clamps an out-of-range index instead of erroring"] = function()
    local CS = loadTree()
    local db = CS.Tree.Bootstrap({})
    local ok = CS.Tree.Reorder(db, "cat_trading", 999)
    assert(ok == true)
    assert(db.tree[#db.tree].id == "cat_trading")
end

-- Reset and restore

tests["ResetToDefaults replaces the tree and clears deleted-ids"] = function()
    local CS = loadTree()
    local db = CS.Tree.Bootstrap({})
    CS.Tree.Delete(db, "cat_professions")
    CS.Tree.AddCategory(db, "Extra")

    CS.Tree.ResetToDefaults(db)

    local categories, phrases = countNodes(db.tree)
    assert(categories == 5 and phrases == 9)
    assert(next(db.deletedDefaultIds) == nil)
end

tests["RestoreMissingDefaults re-adds a deleted default without touching other edits"] = function()
    local CS = loadTree()
    local db = CS.Tree.Bootstrap({})
    CS.Tree.Delete(db, "cat_professions")
    CS.Tree.RenameCategory(db, "cat_trading", "My Trading")
    local extra = CS.Tree.AddCategory(db, "Extra")

    CS.Tree.RestoreMissingDefaults(db)

    local found
    for _, category in ipairs(db.tree) do
        if category.id == "cat_professions" then
            found = category
        end
    end
    assert(found ~= nil, "cat_professions should have been restored")
    assert(next(db.deletedDefaultIds) == nil)

    for _, category in ipairs(db.tree) do
        if category.id == "cat_trading" then
            assert(category.name == "My Trading", "unrelated edits must survive")
        end
    end
    local extraStillPresent = false
    for _, category in ipairs(db.tree) do
        if category.id == extra.id then
            extraStillPresent = true
        end
    end
    assert(extraStillPresent, "player-added nodes must survive")
end

-- Migration

tests["Migrate on a fresh install is a no-op (schemaVersion already current)"] = function()
    local CS = loadTree()
    local db = CS.Tree.Bootstrap({})
    local before = CS.Data.SCHEMA_VERSION
    CS.Tree.Migrate(db)
    assert(db.schemaVersion == before)
end

tests["Migrate adds a missing default when schemaVersion is older"] = function()
    local CS = loadTree()
    local db = {
        schemaVersion = 0,
        deletedDefaultIds = {},
        tree = {
            {
                id = "cat_icebreakers",
                type = "category",
                name = "Icebreakers",
                children = {},
            },
        },
    }

    CS.Tree.Migrate(db)

    local categories, phrases = countNodes(db.tree)
    assert(categories == 5, "missing default categories must be added")
    assert(phrases == 9, "missing default phrases must be added")
    assert(db.schemaVersion == CS.Data.SCHEMA_VERSION)
end

tests["Migrate does not restore a default the player deleted"] = function()
    local CS = loadTree()
    local db = CS.Tree.Bootstrap({})
    CS.Tree.Delete(db, "cat_professions")
    db.schemaVersion = 0

    CS.Tree.Migrate(db)

    for _, category in ipairs(db.tree) do
        assert(category.id ~= "cat_professions", "a player-deleted default must stay deleted through migration")
    end
    assert(db.schemaVersion == CS.Data.SCHEMA_VERSION)
end

tests["Migrate leaves a player-edited default's content alone"] = function()
    local CS = loadTree()
    local db = CS.Tree.Bootstrap({})
    CS.Tree.EditPhraseText(db, "trading_spare", "My custom wording")
    db.schemaVersion = 0

    CS.Tree.Migrate(db)

    local category = db.tree[2]
    assert(category.children[1].text == "My custom wording", "migration must not overwrite a player edit")
end

return tests
