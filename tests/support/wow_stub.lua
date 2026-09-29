-- Minimal stand-ins for the WoW globals Core.lua and Launcher.lua touch
-- merely by being loaded (CreateFrame to register their top-level event
-- frame, SlashCmdList to register the slash command). This does not model
-- real WoW behavior, only enough that those modules don't error out at
-- module-load time in a plain Lua process. Real client behavior stays a
-- manual, in-client check - see AGENTS.md, "Test, secret-value lint and
-- release commands".
local function makeFakeFrame()
    local frame = { events = {}, scripts = {} }

    function frame:RegisterEvent(event)
        self.events[event] = true
    end

    function frame:RegisterUnitEvent(event, unit)
        self.events[event .. ":" .. unit] = true
    end

    function frame:UnregisterEvent(event)
        self.events[event] = nil
    end

    function frame:SetScript(script, handler)
        self.scripts[script] = handler
    end

    -- Test-only convenience: fire a registered script's handler directly.
    function frame:Fire(script, ...)
        local handler = self.scripts[script]
        if handler then
            handler(frame, ...)
        end
    end

    return frame
end

local M = {}

M.makeFakeFrame = makeFakeFrame

function M.install()
    _G.CreateFrame = _G.CreateFrame or function()
        return makeFakeFrame()
    end
    _G.SlashCmdList = _G.SlashCmdList or {}
end

return M
