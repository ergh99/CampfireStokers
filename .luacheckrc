std = "lua51"

max_line_length = false

-- leafo/gh-actions-lua and luarocks both install into the repo working
-- copy in CI (.lua/ and .luarocks/ respectively, confirmed the hard way
-- when the first real CI run's syntax check tried to read .lua as a Lua
-- file and choked on a Lua 5.3-syntax vendor file under .luarocks/ - see
-- docs/decision-log.md). Luacheck would otherwise lint that installed,
-- third-party code as if it were ours.
exclude_files = {
    ".lua/**",
    ".luarocks/**",
    "lua_modules/**",
}

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

    -- UI.lua
    "UIParent",
    "DEFAULT_CHAT_FRAME",
    "C_Timer",
    "UnitExists",
    "GameTooltip",

    -- Options.lua
    "StaticPopupDialogs",
    "StaticPopup_Show",
    "Settings",
    "GetCursorPosition",
}
