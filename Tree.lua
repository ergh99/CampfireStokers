local CS = select(2, ...)

CS.Tree = CS.Tree or {}

local PHRASE_TEXT_LIMIT = 255

local function deepCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for k, v in pairs(value) do
        copy[k] = deepCopy(v)
    end
    return copy
end

local function collectIds(tree)
    local ids = {}
    for _, category in ipairs(tree) do
        ids[category.id] = true
        for _, phrase in ipairs(category.children) do
            ids[phrase.id] = true
        end
    end
    return ids
end

local function findCategory(tree, id)
    for _, category in ipairs(tree) do
        if category.id == id then
            return category
        end
    end
    return nil
end

-- Returns the owning category, the phrase itself, and the phrase's index
-- within that category's children, or nothing if no phrase has this id.
local function findPhrase(tree, id)
    for _, category in ipairs(tree) do
        for i, phrase in ipairs(category.children) do
            if phrase.id == id then
                return category, phrase, i
            end
        end
    end
    return nil
end

local function isDefaultId(id)
    for _, category in ipairs(CS.Data.DefaultTree) do
        if category.id == id then
            return true
        end
        for _, phrase in ipairs(category.children) do
            if phrase.id == id then
                return true
            end
        end
    end
    return false
end

local function recordIfDefault(db, id)
    if isDefaultId(id) then
        db.deletedDefaultIds = db.deletedDefaultIds or {}
        db.deletedDefaultIds[id] = true
    end
end

local function clampIndex(index, max)
    if index < 1 then
        return 1
    end
    if index > max then
        return max
    end
    return index
end

local function generateId(db, prefix)
    db.nextNodeId = (db.nextNodeId or 0) + 1
    return string.format("%s_%d", prefix, db.nextNodeId)
end

-- Adds any default category or phrase whose id is neither already present
-- nor recorded as player-deleted. Shared by Migrate (which also bumps
-- schemaVersion) and RestoreMissingDefaults (which clears the deleted-ids
-- record first instead).
local function addMissingDefaults(db)
    db.deletedDefaultIds = db.deletedDefaultIds or {}
    local existingIds = collectIds(db.tree)
    for _, defaultCategory in ipairs(CS.Data.DefaultTree) do
        if not existingIds[defaultCategory.id] and not db.deletedDefaultIds[defaultCategory.id] then
            table.insert(db.tree, deepCopy(defaultCategory))
        else
            local categoryNode = findCategory(db.tree, defaultCategory.id)
            if categoryNode then
                for _, defaultPhrase in ipairs(defaultCategory.children) do
                    if not existingIds[defaultPhrase.id] and not db.deletedDefaultIds[defaultPhrase.id] then
                        table.insert(categoryNode.children, deepCopy(defaultPhrase))
                    end
                end
            end
        end
    end
end

-- On first load (db.tree is nil), deep-copies CS.Data.DefaultTree in. On
-- every later load, runs Migrate instead. Either way, returns the db table
-- so a caller can do `CampfireStokersDB = CS.Tree.Bootstrap(CampfireStokersDB)`.
function CS.Tree.Bootstrap(db)
    db = db or {}
    if db.tree == nil then
        db.tree = deepCopy(CS.Data.DefaultTree)
        db.deletedDefaultIds = {}
        db.schemaVersion = CS.Data.SCHEMA_VERSION
    else
        CS.Tree.Migrate(db)
    end
    return db
end

function CS.Tree.Migrate(db)
    if (db.schemaVersion or 0) >= CS.Data.SCHEMA_VERSION then
        return db
    end
    addMissingDefaults(db)
    db.schemaVersion = CS.Data.SCHEMA_VERSION
    return db
end

function CS.Tree.ResetToDefaults(db)
    db.tree = deepCopy(CS.Data.DefaultTree)
    db.deletedDefaultIds = {}
    db.schemaVersion = CS.Data.SCHEMA_VERSION
    return db
end

function CS.Tree.RestoreMissingDefaults(db)
    db.deletedDefaultIds = {}
    addMissingDefaults(db)
    return db
end

-- Categories always sit directly under the root: there is deliberately no
-- parentCategoryId parameter, so nesting a category inside a category isn't
-- a case to reject at runtime, it's simply not an operation this API has.
function CS.Tree.AddCategory(db, name)
    local category = {
        id = generateId(db, "player_cat"),
        type = "category",
        name = name,
        children = {},
    }
    table.insert(db.tree, category)
    return category
end

function CS.Tree.AddPhrase(db, categoryId, text)
    if #text > PHRASE_TEXT_LIMIT then
        return nil, "Phrase text can't be longer than " .. PHRASE_TEXT_LIMIT .. " characters."
    end
    local category = findCategory(db.tree, categoryId)
    if not category then
        return nil, "No such category."
    end
    local phrase = {
        id = generateId(db, "player_phrase"),
        type = "phrase",
        text = text,
    }
    table.insert(category.children, phrase)
    return phrase
end

function CS.Tree.RenameCategory(db, categoryId, name)
    local category = findCategory(db.tree, categoryId)
    if not category then
        return false, "No such category."
    end
    category.name = name
    return true
end

function CS.Tree.EditPhraseText(db, phraseId, text)
    if #text > PHRASE_TEXT_LIMIT then
        return false, "Phrase text can't be longer than " .. PHRASE_TEXT_LIMIT .. " characters."
    end
    local _, phrase = findPhrase(db.tree, phraseId)
    if not phrase then
        return false, "No such phrase."
    end
    phrase.text = text
    return true
end

function CS.Tree.Delete(db, id)
    for i, category in ipairs(db.tree) do
        if category.id == id then
            table.remove(db.tree, i)
            recordIfDefault(db, id)
            return true
        end
    end
    local category, phrase, index = findPhrase(db.tree, id)
    if category and phrase and index then
        table.remove(category.children, index)
        recordIfDefault(db, id)
        return true
    end
    return false, "No such node."
end

function CS.Tree.Reorder(db, id, newIndex)
    for i, category in ipairs(db.tree) do
        if category.id == id then
            table.remove(db.tree, i)
            table.insert(db.tree, clampIndex(newIndex, #db.tree + 1), category)
            return true
        end
    end
    local category, phrase, index = findPhrase(db.tree, id)
    if category and phrase and index then
        table.remove(category.children, index)
        table.insert(category.children, clampIndex(newIndex, #category.children + 1), phrase)
        return true
    end
    return false, "No such node."
end
