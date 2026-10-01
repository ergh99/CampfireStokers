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

    -- Launcher.lua. SlashCmdList itself must stay read-only (never
    -- reassigned), but other_fields = true is needed because we legitimately
    -- write a new key into it (SlashCmdList.CAMPFIRESTOKERS = handler) -
    -- the standard way every WoW addon registers a slash command, flagged
    -- by Luacheck's default "read_globals means read-only fields too"
    -- the first time this actually ran (see docs/decision-log.md).
    SlashCmdList = { other_fields = true },
    "AddonCompartmentFrame",

    -- UI.lua
    "UIParent",
    "DEFAULT_CHAT_FRAME",
    "C_Timer",
    "UnitExists",
    "GameTooltip",

    -- Options.lua. Same other_fields reasoning as SlashCmdList above: we
    -- write new dialog definitions into StaticPopupDialogs, never reassign
    -- the table itself.
    StaticPopupDialogs = { other_fields = true },
    "StaticPopup_Show",
    "Settings",
    "GetCursorPosition",
}

-- tests/ mocks real WoW API globals by assigning directly over them (e.g.
-- SendChatMessage = function(...) ... end) to intercept calls from the
-- module under test - the entire point of a mock. That's a real reassignment
-- Luacheck's default read_globals correctly flags as suspicious for
-- production code, so it's only loosened for this one global, in this one
-- directory, not everywhere.
files["tests/**/*.lua"] = {
    globals = { "SendChatMessage", "DoEmote" },
}
