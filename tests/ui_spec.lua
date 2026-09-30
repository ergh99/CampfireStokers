local loadModule = require("support.load_module")

local tests = {}

local function loadUI()
    local CS = {}
    loadModule("UI.lua", "CampfireStokers", CS)
    return CS
end

tests["ShouldAutoOpen allows the first auto-open of a session immediately"] = function()
    local CS = loadUI()
    assert(CS.UI.ShouldAutoOpen(nil, 1000, 300) == true)
end

tests["ShouldAutoOpen refuses another auto-open before the delay elapses"] = function()
    local CS = loadUI()
    assert(CS.UI.ShouldAutoOpen(1000, 1299, 300) == false)
end

tests["ShouldAutoOpen allows another auto-open once the delay has elapsed"] = function()
    local CS = loadUI()
    assert(CS.UI.ShouldAutoOpen(1000, 1300, 300) == true)
end

return tests
