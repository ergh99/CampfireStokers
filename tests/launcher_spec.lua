local loadModule = require("support.load_module")
local wowStub = require("support.wow_stub")

local tests = {}

local function loadLauncher()
    wowStub.install()
    local CS = {
        Data = { L = { ui_selftest_title = "Campfire Stokers Self-Test" } },
        Detection = { CAMPFIRE_SPELL_ID = 0, Simulate = function() end },
        UI = { Toggle = function() end, ShowTextPopup = function() end },
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

tests["the addon compartment click handler toggles the panel"] = function()
    local CS = loadLauncher()
    local toggled = 0
    CS.UI.Toggle = function()
        toggled = toggled + 1
    end

    CampfireStokers_OnAddonCompartmentClick("CampfireStokers", "CampfireStokers", nil)

    assert(toggled == 1)
end

local function runSelfTestAndCapture(CS)
    local title, text
    CS.UI.ShowTextPopup = function(popupTitle, popupText)
        title, text = popupTitle, popupText
    end
    SlashCmdList.CAMPFIRESTOKERS("selftest")
    return title, text
end

tests["selftest shows a popup (not chat prints) with a verdict section for each check"] = function()
    local CS = loadLauncher()
    local lines, restore = capturePrints()
    local title, text = runSelfTestAndCapture(CS)
    restore()

    assert(#lines == 0, "selftest should not print to chat at all")
    assert(title == "Campfire Stokers Self-Test")
    assert(type(text) == "string")

    local checkCount = 0
    for _ in text:gmatch("%[%u+%]") do
        checkCount = checkCount + 1
    end
    assert(checkCount == 9, "expected 9 check verdicts, got " .. checkCount)
end

tests["the emote command globals check ignores this add-on's own slash globals"] = function()
    local CS = loadLauncher()
    local _, text = runSelfTestAndCapture(CS)

    assert(text:find("emote command globals", 1, true) ~= nil)
    assert(text:find("CAMPFIRESTOKERS", 1, true) == nil,
        "must not report its own slash command as an emote global: " .. text)
end

local function getCheckStatus(text, name)
    for status, sectionName in text:gmatch("%[(%u+)%] ([^\n]+)") do
        if sectionName == name then
            return status
        end
    end
end

-- Regression coverage for exactly the gap manual T6 testing found: the
-- original version of this check only asked "did the read throw," which
-- reported FAIL the moment a real client didn't throw during secrecy -
-- even though canaccessvalue is the guard Detection.lua actually depends
-- on. These pin down all three outcomes so that gap can't reopen silently.
tests["aura-reads-while-secret: PASS when the read throws"] = function()
    local CS = loadLauncher()
    _G.C_Secrets = { ShouldAurasBeSecret = function() return true end }
    _G.C_UnitAuras = { GetPlayerAuraBySpellID = function() error("secret!") end }
    _G.canaccessvalue = nil

    local _, text = runSelfTestAndCapture(CS)

    assert(getCheckStatus(text, "aura reads while secrecy is active") == "PASS")

    _G.C_Secrets, _G.C_UnitAuras, _G.canaccessvalue = nil, nil, nil
end

tests["aura-reads-while-secret: PASS when the read doesn't throw but canaccessvalue flags it unreadable"] = function()
    local CS = loadLauncher()
    _G.C_Secrets = { ShouldAurasBeSecret = function() return true end }
    _G.C_UnitAuras = { GetPlayerAuraBySpellID = function() return { spellId = 1 } end }
    _G.canaccessvalue = function() return false end

    local _, text = runSelfTestAndCapture(CS)

    assert(getCheckStatus(text, "aura reads while secrecy is active") == "PASS")

    _G.C_Secrets, _G.C_UnitAuras, _G.canaccessvalue = nil, nil, nil
end

tests["aura-reads-while-secret: FAIL when neither throwing nor canaccessvalue catches it"] = function()
    local CS = loadLauncher()
    _G.C_Secrets = { ShouldAurasBeSecret = function() return true end }
    _G.C_UnitAuras = { GetPlayerAuraBySpellID = function() return { spellId = 1 } end }
    _G.canaccessvalue = function() return true end

    local _, text = runSelfTestAndCapture(CS)

    assert(getCheckStatus(text, "aura reads while secrecy is active") == "FAIL")

    _G.C_Secrets, _G.C_UnitAuras, _G.canaccessvalue = nil, nil, nil
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

tests["no arguments toggles the panel instead of erroring"] = function()
    local CS = loadLauncher()
    local toggled = 0
    CS.UI.Toggle = function()
        toggled = toggled + 1
    end

    local ok = pcall(SlashCmdList.CAMPFIRESTOKERS, "")

    assert(ok == true)
    assert(toggled == 1)
end

tests["an unknown subcommand is reported, not silently ignored"] = function()
    loadLauncher()
    local lines, restore = capturePrints()
    SlashCmdList.CAMPFIRESTOKERS("dance")
    restore()
    assert(#lines == 1 and lines[1]:find("unknown", 1, true) ~= nil)
end

return tests
