local ADDON_NAME, CS = ...

CS.Core = CS.Core or {}

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")

frame:SetScript("OnEvent", function(_, event, loadedAddonName)
    if event ~= "ADDON_LOADED" or loadedAddonName ~= ADDON_NAME then
        return
    end

    CampfireStokersDB = CS.Tree.Bootstrap(CampfireStokersDB)

    CS.UI.CreatePanel()
    CS.Options.CreateCanvas()
    CS.Detection.RegisterStateChangedCallback(CS.UI.OnCampfireStateChanged)

    CS.Detection.CreateEventFrame()
    CS.Detection.Refresh()
end)
