local loadModule = require("support.load_module")
local wowStub = require("support.wow_stub")

local tests = {}

-- Core.lua is loaded last in the real TOC, after everything it depends on
-- has already populated CS. Mirror that load order here, with a fake frame
-- captured so the test can fire ADDON_LOADED itself instead of waiting for
-- a real client.
-- CS.UI.CreatePanel() builds a full frame tree (backdrops, font strings,
-- button templates) that's far beyond what the minimal fake frame here
-- models - that stays a manual, in-client check (see AGENTS.md). Core.lua
-- is only responsible for calling it and wiring its callback, so CS.UI is
-- stubbed to verify exactly that wiring.
local function makeUIStub()
    local ui = { createPanelCalls = 0, stateChanges = {} }
    ui.CreatePanel = function()
        ui.createPanelCalls = ui.createPanelCalls + 1
    end
    ui.OnCampfireStateChanged = function(atFire)
        table.insert(ui.stateChanges, atFire)
    end
    return ui
end

-- Same reasoning as makeUIStub: Options.lua's real CreateCanvas() needs a
-- full frame tree this test harness doesn't model, so it's stubbed to
-- verify only that Core.lua calls it.
local function makeOptionsStub()
    local options = { createCanvasCalls = 0 }
    options.CreateCanvas = function()
        options.createCanvasCalls = options.createCanvasCalls + 1
    end
    return options
end

local function loadCoreWithDependencies()
    local capturedFrame

    local CS = { UI = makeUIStub(), Options = makeOptionsStub() }
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
    assert(CS.UI.createPanelCalls == 1, "Core.lua must create the panel exactly once on load")
    assert(CS.Options.createCanvasCalls == 1, "Core.lua must create the options canvas exactly once on load")
    assert(CS.Detection.atFire == false, "no aura mocked, so the initial Refresh should leave it false")

    CS.Detection.Simulate(true)
    assert(#CS.UI.stateChanges == 1 and CS.UI.stateChanges[1] == true,
        "Core.lua must register CS.UI.OnCampfireStateChanged as Detection's callback")
end

return tests
