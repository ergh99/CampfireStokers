local ADDON_NAME, CS = ...

CS.Core = CS.Core or {}

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")

frame:SetScript("OnEvent", function(_, event, loadedAddonName)
    if event ~= "ADDON_LOADED" or loadedAddonName ~= ADDON_NAME then
        return
    end

    CampfireStokersDB = CS.Tree.Bootstrap(CampfireStokersDB)
    -- Before the panel exists: Detection.Refresh below can auto-open it,
    -- and the tutorial has to know by then whether its welcome card is due.
    CS.Tutorial.Init()

    CS.UI.CreatePanel()
    CS.Options.CreateCanvas()
    CS.Detection.RegisterStateChangedCallback(CS.UI.OnCampfireStateChanged)

    CS.Detection.CreateEventFrame()
    CS.Detection.Refresh()
    CS.Professions.CreateEventFrame()
    CS.Professions.WarmItemCache()
end)
