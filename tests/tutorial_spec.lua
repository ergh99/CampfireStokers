local loadModule = require("support.load_module")

local tests = {}

-- Only Tutorial.lua's pure half is exercised here: due/seen state, tour
-- endings, and step skipping. The card, the callout frame and the event
-- wiring need a real client (see AGENTS.md).
local function loadTutorial()
    local CS = {}
    loadModule("Tutorial.lua", "CampfireStokers", CS)
    return CS.Tutorial
end

local PARTS = { "welcome", "editor", "panel", "features" }

local function idsOf(steps, context)
    local Tutorial = loadTutorial()
    local ids = {}
    local index = Tutorial.NextStep(steps, 0, context)
    while index do
        table.insert(ids, steps[index].id)
        index = Tutorial.NextStep(steps, index, context)
    end
    return table.concat(ids, ",")
end

-- IsDue / MarkSeen

tests["a fresh install has every part due"] = function()
    local Tutorial = loadTutorial()
    for _, part in ipairs(PARTS) do
        assert(Tutorial.IsDue({}, part), part)
    end
end

tests["a v0.1.0 save (tree, no tutorial table) has every part due"] = function()
    local Tutorial = loadTutorial()
    local db = { tree = {}, schemaVersion = 1, sendMode = "SAY" }
    for _, part in ipairs(PARTS) do
        assert(Tutorial.IsDue(db, part), part)
    end
end

tests["MarkSeen marks only the part given, under the current version"] = function()
    local Tutorial = loadTutorial()
    local db = {}
    Tutorial.MarkSeen(db, "welcome")
    assert(db.tutorial.version == Tutorial.VERSION)
    assert(not Tutorial.IsDue(db, "welcome"))
    assert(Tutorial.IsDue(db, "editor"))
    assert(Tutorial.IsDue(db, "panel"))
    assert(Tutorial.IsDue(db, "features"))
end

tests["a save from an older version has every part due again"] = function()
    local Tutorial = loadTutorial()
    local db = {
        tutorial = { version = Tutorial.VERSION - 1, welcome = true, editor = true, panel = true, features = true },
    }
    for _, part in ipairs(PARTS) do
        assert(Tutorial.IsDue(db, part), part)
    end
end

tests["MarkSeen over an older version's save drops its stale entries"] = function()
    local Tutorial = loadTutorial()
    local db = { tutorial = { version = Tutorial.VERSION - 1, editor = true } }
    Tutorial.MarkSeen(db, "welcome")
    assert(db.tutorial.version == Tutorial.VERSION)
    assert(db.tutorial.editor == nil)
    assert(Tutorial.IsDue(db, "editor"))
end

tests["the saved tutorial state holds only booleans and an integer version"] = function()
    local Tutorial = loadTutorial()
    local db = {}
    for _, part in ipairs(PARTS) do
        Tutorial.MarkSeen(db, part)
    end
    for key, value in pairs(db.tutorial) do
        if key == "version" then
            assert(type(value) == "number" and value == math.floor(value))
        else
            assert(type(value) == "boolean", key)
        end
    end
end

tests["Reset makes everything due again"] = function()
    local Tutorial = loadTutorial()
    local db = {}
    for _, part in ipairs(PARTS) do
        Tutorial.MarkSeen(db, part)
    end
    Tutorial.Reset(db)
    assert(db.tutorial == nil)
    for _, part in ipairs(PARTS) do
        assert(Tutorial.IsDue(db, part), part)
    end
end

-- FinishTour

tests["a tour ended with Done or the close X counts as seen"] = function()
    local Tutorial = loadTutorial()
    local db = {}
    assert(Tutorial.FinishTour(db, "editor", "done") == true)
    assert(not Tutorial.IsDue(db, "editor"))
    assert(Tutorial.FinishTour(db, "panel", "closed") == true)
    assert(not Tutorial.IsDue(db, "panel"))
end

tests["a tour cut short by its target hiding, or replaced, stays due"] = function()
    local Tutorial = loadTutorial()
    local db = {}
    assert(Tutorial.FinishTour(db, "panel", "targetHidden") == false)
    assert(Tutorial.FinishTour(db, "editor", "replaced") == false)
    assert(Tutorial.IsDue(db, "panel"))
    assert(Tutorial.IsDue(db, "editor"))
end

-- Step skipping

tests["the editor tour runs all four steps when there are rows"] = function()
    local Tutorial = loadTutorial()
    assert(idsOf(Tutorial.EDITOR_STEPS, { hasCategoryRow = true, hasPhraseRow = true })
        == "addCategory,categoryActions,phraseActions,dragHandle")
end

tests["the editor tour skips row steps when there are no rows"] = function()
    local Tutorial = loadTutorial()
    assert(idsOf(Tutorial.EDITOR_STEPS, { hasCategoryRow = true, hasPhraseRow = false })
        == "addCategory,categoryActions")
    assert(idsOf(Tutorial.EDITOR_STEPS, {}) == "addCategory")
end

tests["the panel tour includes the feature step only when feature buttons show"] = function()
    local Tutorial = loadTutorial()
    assert(idsOf(Tutorial.PANEL_STEPS, { hasPhraseRow = true, hasFeatureButtons = true, editorSeen = true })
        == "phrase,features")
    assert(idsOf(Tutorial.PANEL_STEPS, { hasPhraseRow = true, hasFeatureButtons = false, editorSeen = true })
        == "phrase")
end

tests["the panel tour offers the editor tour only if it hasn't run"] = function()
    local Tutorial = loadTutorial()
    assert(idsOf(Tutorial.PANEL_STEPS, { hasPhraseRow = true, hasFeatureButtons = true, editorSeen = false })
        == "phrase,features,editorOffer")
    assert(idsOf(Tutorial.PANEL_STEPS, { hasPhraseRow = true, editorSeen = false })
        == "phrase,editorOffer")
end

tests["the offer step is the last one and has an action button"] = function()
    local Tutorial = loadTutorial()
    local steps = Tutorial.PANEL_STEPS
    local last = steps[#steps]
    assert(last.id == "editorOffer" and last.actionKey ~= nil)
    assert(Tutorial.NextStep(steps, #steps, { editorSeen = false }) == nil)
end

tests["the feature-only tour needs feature buttons"] = function()
    local Tutorial = loadTutorial()
    assert(Tutorial.NextStep(Tutorial.FEATURE_STEPS, 0, { hasFeatureButtons = false }) == nil)
    assert(Tutorial.NextStep(Tutorial.FEATURE_STEPS, 0, { hasFeatureButtons = true }) == 1)
end

tests["StepPosition counts only the available steps"] = function()
    local Tutorial = loadTutorial()
    local context = { hasPhraseRow = true, hasFeatureButtons = false, editorSeen = false }
    -- phrase, (features skipped), editorOffer
    local position, total = Tutorial.StepPosition(Tutorial.PANEL_STEPS, 3, context)
    assert(position == 2 and total == 2, position .. "/" .. total)
    position, total = Tutorial.StepPosition(Tutorial.PANEL_STEPS, 1, context)
    assert(position == 1 and total == 2)
end

tests["every step's text, and the offer's button, is a CS.Data.L string"] = function()
    local CS = {}
    loadModule("Data.lua", "CampfireStokers", CS)
    loadModule("Tutorial.lua", "CampfireStokers", CS)
    for _, list in ipairs({ CS.Tutorial.EDITOR_STEPS, CS.Tutorial.PANEL_STEPS, CS.Tutorial.FEATURE_STEPS }) do
        for _, step in ipairs(list) do
            assert(type(CS.Data.L[step.textKey]) == "string", step.textKey)
            if step.actionKey then
                assert(type(CS.Data.L[step.actionKey]) == "string", step.actionKey)
            end
        end
    end
end

return tests
