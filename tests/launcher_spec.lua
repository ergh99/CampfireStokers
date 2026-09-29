local loadModule = require("support.load_module")
local wowStub = require("support.wow_stub")

local tests = {}

local function loadLauncher()
    wowStub.install()
    local CS = {
        Detection = { CAMPFIRE_SPELL_ID = 0, Simulate = function() end },
    }
    loadModule("Launcher.lua", "CampfireStokers", CS)
    return CS
end

local function capturePrints()
    local lines = {}
    local realPrint = _G.print
    _G.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do
            parts[i] = tostring(select(i, ...))
        end
        table.insert(lines, table.concat(parts, " "))
    end
    return lines, function()
        _G.print = realPrint
    end
end

tests["Launcher.lua defines the addon compartment click handler"] = function()
    loadLauncher()
    assert(type(CampfireStokers_OnAddonCompartmentClick) == "function")
end

tests["selftest runs every check and prints a verdict line for each"] = function()
    loadLauncher()
    local lines, restore = capturePrints()
    SlashCmdList.CAMPFIRESTOKERS("selftest")
    restore()

    assert(#lines == 10, "expected a header plus 9 check lines, got " .. #lines)
    for i = 2, #lines do
        assert(lines[i]:match("^%s*%[%u+%]") ~= nil, "line should start with a [STATUS]: " .. lines[i])
    end
end

tests["the emote command globals check ignores this add-on's own slash globals"] = function()
    loadLauncher()
    local lines, restore = capturePrints()
    SlashCmdList.CAMPFIRESTOKERS("selftest")
    restore()

    local emoteLine
    for _, line in ipairs(lines) do
        if line:find("emote command globals", 1, true) then
            emoteLine = line
        end
    end
    assert(emoteLine ~= nil)
    assert(emoteLine:find("CAMPFIRESTOKERS", 1, true) == nil,
        "must not report its own slash command as an emote global: " .. emoteLine)
end

tests["simulate on/off calls Detection.Simulate with the right boolean"] = function()
    local CS = loadLauncher()
    local seen = {}
    CS.Detection.Simulate = function(atFire)
        table.insert(seen, atFire)
    end

    SlashCmdList.CAMPFIRESTOKERS("simulate on")
    SlashCmdList.CAMPFIRESTOKERS("simulate off")
    SlashCmdList.CAMPFIRESTOKERS("simulate sideways")

    assert(#seen == 2, "an invalid argument must not call Simulate")
    assert(seen[1] == true and seen[2] == false)
end

tests["no arguments prints a friendly message instead of erroring"] = function()
    loadLauncher()
    local lines, restore = capturePrints()
    local ok = pcall(SlashCmdList.CAMPFIRESTOKERS, "")
    restore()
    assert(ok == true)
    assert(#lines == 1)
end

tests["an unknown subcommand is reported, not silently ignored"] = function()
    loadLauncher()
    local lines, restore = capturePrints()
    SlashCmdList.CAMPFIRESTOKERS("dance")
    restore()
    assert(#lines == 1 and lines[1]:find("unknown", 1, true) ~= nil)
end

return tests
