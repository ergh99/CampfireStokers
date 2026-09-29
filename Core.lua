local ADDON_NAME, CS = ...

CS.Core = CS.Core or {}

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")

frame:SetScript("OnEvent", function(_, event, loadedAddonName)
    if event ~= "ADDON_LOADED" or loadedAddonName ~= ADDON_NAME then
        return
    end

    CampfireStokersDB = CS.Tree.Bootstrap(CampfireStokersDB)

    -- Placeholder until UI.lua (T7) registers the real panel show/hide
    -- callback; gives the T6 selftest/simulate commands visible feedback
    -- in the meantime.
    CS.Detection.RegisterStateChangedCallback(function(atFire)
        print("Campfire Stokers: " .. (atFire and "at a campfire." or "left the campfire."))
    end)

    CS.Detection.CreateEventFrame()
    CS.Detection.Refresh()
end)
