local CS = select(2, ...)

---@class CampfireStokersDetection
CS.Detection = CS.Detection or {}

-- Confirmed in-client during T6 (2026-09-30); see docs/decision-log.md.
CS.Detection.CAMPFIRE_SPELL_ID = 1229739

-- The permanent tutorial campfires in starting zones apply a different
-- aura than the one above - without also checking this id, sitting at
-- one of these would never register as "at a campfire" at all. See
-- docs/decision-log.md.
CS.Detection.TUTORIAL_CAMPFIRE_SPELL_ID = 1289723

CS.Detection.CAMPFIRE_SPELL_IDS = { CS.Detection.CAMPFIRE_SPELL_ID, CS.Detection.TUTORIAL_CAMPFIRE_SPELL_ID }

CS.Detection.atFire = false

local stateChangedCallbacks = {}

function CS.Detection.RegisterStateChangedCallback(callback)
    table.insert(stateChangedCallbacks, callback)
end

local function setState(atFire)
    if atFire == CS.Detection.atFire then
        return
    end
    CS.Detection.atFire = atFire
    for _, callback in ipairs(stateChangedCallbacks) do
        callback(atFire)
    end
end

-- Pure: decides whether the player counts as at a campfire right now,
-- without touching any real WoW state unless the caller lets it fall
-- through to the defaults. `options`:
--   shouldAurasBeSecret()        defaults to C_Secrets.ShouldAurasBeSecret
--   getPlayerAuraBySpellID(id)   defaults to C_UnitAuras.GetPlayerAuraBySpellID
--                                (already player-only; takes no unit arg)
--   canAccessValue(value)        defaults to canaccessvalue
--   spellIds                     defaults to CS.Detection.CAMPFIRE_SPELL_IDS
-- Ask-then-read-then-check-readability, in that order, per AGENTS.md's
-- secret-value rules: skip the read entirely while auras are secret, and
-- never branch on an aura result before canAccessValue confirms it's
-- safe. ShouldAurasBeSecret is asked once, up front, covering every id
-- checked below - it's a blanket restriction on reading auras at all
-- this frame, not a per-aura one. Each id is otherwise independent: an
-- unreadable or nil result for one doesn't mean the next one is also
-- absent, so the loop keeps checking rather than bailing out on the
-- first miss - the player only needs to be at ONE kind of campfire.
function CS.Detection.EvaluateState(options)
    options = options or {}

    local shouldAurasBeSecret = options.shouldAurasBeSecret
        or (C_Secrets and C_Secrets.ShouldAurasBeSecret)
    local getPlayerAuraBySpellID = options.getPlayerAuraBySpellID
        or (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID)
    local canAccessValue = options.canAccessValue or canaccessvalue
    local spellIds = options.spellIds or CS.Detection.CAMPFIRE_SPELL_IDS

    if shouldAurasBeSecret and shouldAurasBeSecret() then
        return false
    end

    if not getPlayerAuraBySpellID then
        return false
    end

    for _, spellId in ipairs(spellIds) do
        local aura = getPlayerAuraBySpellID(spellId)
        if (not canAccessValue or canAccessValue(aura)) and aura ~= nil then
            return true
        end
    end

    return false
end

function CS.Detection.Refresh(options)
    setState(CS.Detection.EvaluateState(options))
end

-- Forces a state and announces it, bypassing EvaluateState entirely, so the
-- panel (and T6's self-test) can be exercised without a real campfire.
function CS.Detection.Simulate(atFire)
    setState(atFire and true or false)
end

-- Creates (or wires up an injected) event frame. UNIT_AURA is registered
-- for the player only via RegisterUnitEvent; PLAYER_ENTERING_WORLD is a
-- core event and always succeeds. ADDON_RESTRICTION_STATE_CHANGED is not a
-- core event on Forever and registering an unknown event throws there, so
-- it's wrapped in pcall and its failure is not fatal to the other two.
function CS.Detection.CreateEventFrame(frame)
    frame = frame or CreateFrame("Frame")

    frame:RegisterUnitEvent("UNIT_AURA", "player")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    pcall(frame.RegisterEvent, frame, "ADDON_RESTRICTION_STATE_CHANGED")

    frame:SetScript("OnEvent", function()
        CS.Detection.Refresh()
    end)

    return frame
end
