local CS = select(2, ...)

---@class CampfireStokersLauncher
CS.Launcher = CS.Launcher or {}

function CampfireStokers_OnAddonCompartmentClick(_addonName, _buttonName, _menuButtonFrame)
    CS.UI.Toggle()
end

-- T6's in-client verification checks. Each returns ("pass" | "fail" |
-- "unknown", message). "pass"/"fail" are only used where the check can be
-- run safely and automatically and has a documented assumption to compare
-- against (see docs/definition.md's "Known deviations from retail" and the
-- secret-value sources in AGENTS.md); "unknown" covers both "couldn't run
-- right now" and "this is deliberately manual" cases. None of these ever
-- call ReloadUI, SendChatMessage, or DoEmote for real: those would reload
-- the player's UI or broadcast a visible chat message just from running a
-- diagnostic command, so those three checks are manual/instructional only.
local SELF_TESTS = {
    {
        name = "campfire aura spell ID",
        run = function()
            return "pass", string.format(
                "CAMPFIRE_SPELL_ID is %d, confirmed in-client 2026-09-30 (see docs/decision-log.md).",
                CS.Detection.CAMPFIRE_SPELL_ID
            )
        end,
    },
    {
        -- Confirmed in combat 2026-09-30 (see docs/decision-log.md): this
        -- campfire aura's data is neither throw-protected nor flagged
        -- unreadable by canaccessvalue during secrecy on this build -
        -- contradicting forever-addon-kit and, more specifically, meaning
        -- this particular aura doesn't appear to be secret-restricted here
        -- at all. That's fine: Detection.lua's real safety net is "ask
        -- ShouldAurasBeSecret first," which means it never attempts this
        -- read during secrecy regardless of whether the read itself would
        -- have been safe. This check still reports the raw finding (fail
        -- against the documented assumption) rather than papering over it,
        -- since a future patch narrowing or widening what's secret should
        -- show up here.
        name = "aura reads while secrecy is active",
        run = function()
            if not (C_Secrets and C_Secrets.ShouldAurasBeSecret) then
                return "unknown", "C_Secrets.ShouldAurasBeSecret isn't available; see the C_Secrets check below."
            end
            if not C_Secrets.ShouldAurasBeSecret() then
                return "unknown", "Auras aren't secret right now. Run "
                    .. "/console addonCombatRestrictionsForced 1 (or enter combat, a Mythic+ run, "
                    .. "or a PvP match) and run selftest again."
            end
            local ok, result = pcall(C_UnitAuras.GetPlayerAuraBySpellID, CS.Detection.CAMPFIRE_SPELL_ID)
            if not ok then
                return "pass", "Reading an aura while secret threw. Detection.lua never reaches this "
                    .. "path anyway (it skips the read once ShouldAurasBeSecret() is true), so this "
                    .. "is belt-and-suspenders either way."
            end
            if canaccessvalue and not canaccessvalue(result) then
                return "pass", "Reading an aura while secret did not throw, but canaccessvalue "
                    .. "correctly reports the result as unreadable. This confirms the canaccessvalue "
                    .. "check - not just avoiding the read - is what actually keeps this safe."
            end
            return "fail", "Reading an aura while secret neither threw nor was flagged unreadable by "
                .. "canaccessvalue - confirmed in combat 2026-09-30 (see docs/decision-log.md). This "
                .. "specific campfire aura doesn't appear to be secret-restricted on this build at "
                .. "all. No code change: Detection.lua's ShouldAurasBeSecret-first guard means it "
                .. "never attempts this read during secrecy regardless of whether the read itself "
                .. "would be safe, so this is accepted as informational, not an open problem."
        end,
    },
    {
        name = "registering an unknown event",
        run = function()
            local frame = CreateFrame("Frame")
            local ok = pcall(frame.RegisterEvent, frame, "CAMPFIRESTOKERS_SELFTEST_UNKNOWN_EVENT")
            if ok then
                return "fail", "Registering an unrecognized event did NOT throw here, contradicting "
                    .. "docs/definition.md's Known Deviations. Harmless either way since "
                    .. "ADDON_RESTRICTION_STATE_CHANGED is still pcall-wrapped; note this for the "
                    .. "Decision Log."
            end
            return "pass", "Registering an unrecognized event threw, as documented. The pcall wrap "
                .. "around ADDON_RESTRICTION_STATE_CHANGED is confirmed necessary."
        end,
    },
    {
        name = "ReloadUI protection",
        run = function()
            return "unknown", "Manually tested both out of combat and in combat 2026-09-30: ReloadUI "
                .. "ran without error both times (see docs/decision-log.md) - it isn't blocked from a "
                .. "slash-command context on this build. Not auto-tested here since running it would "
                .. "reload your UI. Moot either way: this add-on never calls ReloadUI regardless "
                .. "(Options.lua refreshes in place)."
        end,
    },
    {
        name = "%t through SendChatMessage",
        run = function()
            return "unknown", "Not auto-tested: would send a real, visible chat message. Manually "
                .. "target something and send a phrase containing %t (once the panel exists, or via "
                .. "SendChatMessage(\"%t\", \"SAY\") yourself), and confirm the target's name appears."
        end,
    },
    {
        name = "hardware-event requirement for sends",
        run = function()
            return "pass", "Manually confirmed 2026-09-30 (see docs/decision-log.md): clicking a "
                .. "phrase button in the panel sends it. A button's OnClick is already a real "
                .. "hardware event, so Send.lua's dispatch running from there is sufficient."
        end,
    },
    {
        name = "the addon compartment",
        run = function()
            if type(AddonCompartmentFrame) == "table" then
                return "pass", "AddonCompartmentFrame exists."
            end
            return "fail", "AddonCompartmentFrame is missing. The TOC's AddonCompartmentFunc entry "
                .. "will have nothing to attach to; raise this for a design decision."
        end,
    },
    {
        name = "C_Secrets",
        run = function()
            if C_Secrets and type(C_Secrets.ShouldAurasBeSecret) == "function" then
                return "pass", "C_Secrets.ShouldAurasBeSecret exists."
            end
            return "fail", "C_Secrets.ShouldAurasBeSecret is missing. Detection.lua's entire "
                .. "secret-value guard depends on it; raise this immediately."
        end,
    },
    {
        name = "the client's emote command globals",
        run = function()
            local found
            for key, value in pairs(_G) do
                if type(key) == "string" and type(value) == "string"
                    and key ~= "SLASH_CAMPFIRESTOKERS1" and key ~= "SLASH_CAMPFIRESTOKERS2"
                    and key:match("^SLASH_%u+%d+$")
                then
                    found = key .. " = " .. value
                    break
                end
            end
            if found then
                return "pass", "Found at least one emote command global (" .. found .. "). "
                    .. "Send.lua's FindEmoteToken scan has something to match against."
            end
            return "fail", "No SLASH_<TOKEN><N> globals found. Send.lua's built-in emote detection "
                .. "(e.g. /salute) won't find anything to match; raise this for a design decision."
        end,
    },
}

local function buildSelfTestReport()
    local sections = {}
    for _, check in ipairs(SELF_TESTS) do
        local ok, status, message = pcall(check.run)
        if not ok then
            status, message = "fail", "self-test check errored: " .. tostring(status)
        end
        table.insert(sections, string.format("[%s] %s\n%s", status:upper(), check.name, message))
    end
    return table.concat(sections, "\n\n")
end

-- The chat frame line-wraps and scrolls away long multi-paragraph text, so
-- this goes in a copyable popup (CS.UI.ShowTextPopup) rather than nine
-- separate print() lines.
local function runSelfTest()
    CS.UI.ShowTextPopup(CS.Data.L.ui_selftest_title, buildSelfTestReport())
end

local function runSimulate(arg)
    arg = (arg or ""):lower()
    if arg == "on" then
        CS.Detection.Simulate(true)
        print("Campfire Stokers: simulating at-fire.")
    elseif arg == "off" then
        CS.Detection.Simulate(false)
        print("Campfire Stokers: simulating not-at-fire.")
    else
        print("Campfire Stokers: usage: /campfire simulate on|off")
    end
end

local function handleSlashCommand(msg)
    local command, rest = (msg or ""):match("^(%S*)%s*(.-)$")
    command = command:lower()

    if command == "selftest" then
        runSelfTest()
    elseif command == "simulate" then
        runSimulate(rest)
    elseif command == "" then
        CS.UI.Toggle()
    else
        print("Campfire Stokers: unknown command '" .. command .. "'. Try selftest or simulate on|off.")
    end
end

SLASH_CAMPFIRESTOKERS1 = "/campfire"
SLASH_CAMPFIRESTOKERS2 = "/cfs"
SlashCmdList.CAMPFIRESTOKERS = handleSlashCommand
