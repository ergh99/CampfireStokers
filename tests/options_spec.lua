local loadModule = require("support.load_module")

local tests = {}

local function loadOptions()
    local CS = {}
    loadModule("Options.lua", "CampfireStokers", CS)
    return CS
end

-- Three rows, top to bottom (WoW's Y axis increases upward, so the topmost
-- row has the largest top/bottom values): row1 spans 300-280, row2 spans
-- 220-200, row3 spans 140-120.
local RECTS = {
    { top = 300, bottom = 280 },
    { top = 220, bottom = 200 },
    { top = 140, bottom = 120 },
}

tests["dropping above every other row's midpoint gives index 1"] = function()
    local CS = loadOptions()
    -- Dragging row3 (index 3), dropping above row1's midpoint (290).
    assert(CS.Options.FindDropIndex(RECTS, 3, 350) == 1)
end

tests["dropping below every other row's midpoint gives the last index"] = function()
    local CS = loadOptions()
    -- Dragging row1 (index 1), dropping below row3's midpoint (130).
    assert(CS.Options.FindDropIndex(RECTS, 1, 50) == 3)
end

tests["dropping between two rows lands between them"] = function()
    local CS = loadOptions()
    -- Dragging row3 (index 3), dropping between row1 (mid 290) and row2 (mid 210).
    assert(CS.Options.FindDropIndex(RECTS, 3, 250) == 2)
end

tests["dropping near a row's own current position is roughly a no-op"] = function()
    local CS = loadOptions()
    -- Dragging row2 (index 2), dropping right at its own midpoint (210):
    -- row1's midpoint (290) is still above, row3's (130) still below, so
    -- it should land back at index 2.
    assert(CS.Options.FindDropIndex(RECTS, 2, 210) == 2)
end

tests["works with only two rows"] = function()
    local CS = loadOptions()
    local rects = {
        { top = 300, bottom = 280 },
        { top = 200, bottom = 180 },
    }
    assert(CS.Options.FindDropIndex(rects, 2, 350) == 1, "drop above the remaining row -> first")
    assert(CS.Options.FindDropIndex(rects, 1, 50) == 2, "drop below the remaining row -> last")
end

return tests
