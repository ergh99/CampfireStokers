std = "lua51"

max_line_length = false

-- Real globals this addon defines. Each one is required by name by a
-- specific WoW API convention (SavedVariables, AddonCompartmentFunc, or the
-- SLASH_x/N slash-command registration); see AGENTS.md, "Lua 5.1 and
-- no-globals rules".
globals = {
    "CampfireStokersDB",
    "CampfireStokers_OnAddonCompartmentClick",
    "SLASH_CAMPFIRESTOKERS1",
    "SLASH_CAMPFIRESTOKERS2",
}

-- WoW API globals this addon reads, added one at a time as modules start
-- calling them. Anything not listed here is flagged as an undefined global,
-- which is how a typo'd API name gets caught before it ships (the WoW client
-- itself never rejects a bad global name at load time). See AGENTS.md,
-- "Adding a WoW API global".
read_globals = {
    -- Send.lua
    "SendChatMessage",
    "DoEmote",

    -- Detection.lua
    "CreateFrame",
    "C_Secrets",
    "C_UnitAuras",
    "canaccessvalue",

    -- Launcher.lua
    "SlashCmdList",
    "AddonCompartmentFrame",
}
