local loadModule = require("support.load_module")
local wowStub = require("support.wow_stub")

local tests = {}

-- Core.lua is loaded last in the real TOC, after everything it depends on
-- has already populated CS. Mirror that load order here, with a fake frame
-- captured so the test can fire ADDON_LOADED itself instead of waiting for
-- a real client.
local function loadCoreWithDependencies()
    local capturedFrame

    local CS = {}
    loadModule("Data.lua", "CampfireStokers", CS)
    loadModule("Tree.lua", "CampfireStokers", CS)
    loadModule("Send.lua", "CampfireStokers", CS)
    loadModule("Detection.lua", "CampfireStokers", CS)

    local realCreateFrame = _G.CreateFrame
    _G.CreateFrame = function(...)
        capturedFrame = wowStub.makeFakeFrame()
        return capturedFrame
    end

    loadModule("Core.lua", "CampfireStokers", CS)

    _G.CreateFrame = realCreateFrame

    return CS, capturedFrame
end

tests["Core.lua registers ADDON_LOADED and ignores other addons loading"] = function()
    _G.CampfireStokersDB = nil
    local CS, frame = loadCoreWithDependencies()

    assert(frame.events.ADDON_LOADED == true)

    frame:Fire("OnEvent", "ADDON_LOADED", "SomeOtherAddon")

    assert(_G.CampfireStokersDB == nil, "an unrelated addon loading must not bootstrap our db")
end

tests["ADDON_LOADED for this addon bootstraps CampfireStokersDB and wires Detection"] = function()
    _G.CampfireStokersDB = nil
    local CS, frame = loadCoreWithDependencies()

    -- Detection.CreateEventFrame will call the real CreateFrame again
    -- (already restored by loadCoreWithDependencies), so stub it once more
    -- for the duration of firing ADDON_LOADED.
    local realCreateFrame = _G.CreateFrame
    _G.CreateFrame = function()
        return wowStub.makeFakeFrame()
    end

    frame:Fire("OnEvent", "ADDON_LOADED", "CampfireStokers")

    _G.CreateFrame = realCreateFrame

    assert(type(_G.CampfireStokersDB) == "table")
    assert(#_G.CampfireStokersDB.tree == 5, "bootstrap should have deep-copied DefaultTree in")
    assert(CS.Detection.atFire == false, "no aura mocked, so the initial Refresh should leave it false")
end

return tests
