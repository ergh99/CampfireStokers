local loadModule = require("support.load_module")

local tests = {}

local function loadDetection()
    local CS = {}
    loadModule("Detection.lua", "CampfireStokers", CS)
    return CS
end

-- EvaluateState

tests["EvaluateState is false while auras are secret, without reading one"] = function()
    local CS = loadDetection()
    local readCalled = false
    local atFire = CS.Detection.EvaluateState({
        shouldAurasBeSecret = function() return true end,
        getPlayerAuraBySpellID = function() readCalled = true end,
        canAccessValue = function() return true end,
        spellId = 12345,
    })
    assert(atFire == false)
    assert(readCalled == false, "the aura must never be read while auras are secret")
end

tests["EvaluateState is true when the aura is readable and present"] = function()
    local CS = loadDetection()
    local atFire = CS.Detection.EvaluateState({
        shouldAurasBeSecret = function() return false end,
        getPlayerAuraBySpellID = function(id)
            assert(id == 12345)
            return { spellId = 12345 }
        end,
        canAccessValue = function() return true end,
        spellId = 12345,
    })
    assert(atFire == true)
end

tests["EvaluateState is false when the aura is readable but nil"] = function()
    local CS = loadDetection()
    local atFire = CS.Detection.EvaluateState({
        shouldAurasBeSecret = function() return false end,
        getPlayerAuraBySpellID = function() return nil end,
        canAccessValue = function() return true end,
        spellId = 12345,
    })
    assert(atFire == false)
end

tests["EvaluateState is false when canAccessValue reports the result unreadable"] = function()
    local CS = loadDetection()
    local atFire = CS.Detection.EvaluateState({
        shouldAurasBeSecret = function() return false end,
        getPlayerAuraBySpellID = function() return { spellId = 12345 } end,
        canAccessValue = function() return false end,
        spellId = 12345,
    })
    assert(atFire == false, "an unreadable result must count as no campfire aura")
end

-- Refresh / callbacks

tests["Refresh announces a state change to registered callbacks"] = function()
    local CS = loadDetection()
    local seen = {}
    CS.Detection.RegisterStateChangedCallback(function(atFire)
        table.insert(seen, atFire)
    end)

    CS.Detection.Refresh({
        shouldAurasBeSecret = function() return false end,
        getPlayerAuraBySpellID = function() return { spellId = 1 } end,
        canAccessValue = function() return true end,
        spellId = 1,
    })

    assert(#seen == 1 and seen[1] == true)
end

tests["Refresh does not re-announce when the state hasn't changed"] = function()
    local CS = loadDetection()
    local seen = {}
    CS.Detection.RegisterStateChangedCallback(function(atFire)
        table.insert(seen, atFire)
    end)

    local options = {
        shouldAurasBeSecret = function() return true end,
    }
    CS.Detection.Refresh(options)
    CS.Detection.Refresh(options)
    CS.Detection.Refresh(options)

    assert(#seen == 0, "starting state is already false; no change should be announced")
end

tests["Simulate forces a state and announces it without touching real WoW state"] = function()
    local CS = loadDetection()
    local seen = {}
    CS.Detection.RegisterStateChangedCallback(function(atFire)
        table.insert(seen, atFire)
    end)

    CS.Detection.Simulate(true)
    CS.Detection.Simulate(true)
    CS.Detection.Simulate(false)

    assert(#seen == 2, "only actual changes should announce")
    assert(seen[1] == true and seen[2] == false)
end

-- Event registration

local function makeFakeFrame(failingEvents)
    local frame = { registered = {} }
    function frame:RegisterUnitEvent(event, unit)
        table.insert(self.registered, event .. ":" .. unit)
    end
    function frame:RegisterEvent(event)
        if failingEvents[event] then
            error("unknown event: " .. event)
        end
        table.insert(self.registered, event)
    end
    function frame:SetScript(script, handler)
        self.scripts = self.scripts or {}
        self.scripts[script] = handler
    end
    return frame
end

tests["CreateEventFrame registers UNIT_AURA for the player and PLAYER_ENTERING_WORLD"] = function()
    local CS = loadDetection()
    local frame = makeFakeFrame({})
    CS.Detection.CreateEventFrame(frame)

    local registered = {}
    for _, event in ipairs(frame.registered) do
        registered[event] = true
    end
    assert(registered["UNIT_AURA:player"] == true)
    assert(registered["PLAYER_ENTERING_WORLD"] == true)
end

tests["CreateEventFrame survives ADDON_RESTRICTION_STATE_CHANGED failing to register"] = function()
    local CS = loadDetection()
    local frame = makeFakeFrame({ ADDON_RESTRICTION_STATE_CHANGED = true })

    local ok = pcall(CS.Detection.CreateEventFrame, frame)

    assert(ok == true, "a failed event registration must not raise out of CreateEventFrame")

    local registered = {}
    for _, event in ipairs(frame.registered) do
        registered[event] = true
    end
    assert(registered["UNIT_AURA:player"] == true, "other registrations must still happen")
    assert(registered["PLAYER_ENTERING_WORLD"] == true, "other registrations must still happen")
end

return tests
