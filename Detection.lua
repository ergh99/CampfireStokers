local CS = select(2, ...)

CS.Detection = CS.Detection or {}

-- Placeholder. T6's self-test confirms the campfire aura's real spell ID
-- in-client and this constant is updated then; 0 is deliberately never a
-- real aura, so until it's corrected the add-on fails closed (never
-- reports "at fire") instead of matching the wrong aura.
CS.Detection.CAMPFIRE_SPELL_ID = 0

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
--   spellId                      defaults to CS.Detection.CAMPFIRE_SPELL_ID
-- Ask-then-read-then-check-readability, in that order, per AGENTS.md's
-- secret-value rules: skip the read entirely while auras are secret, and
-- never branch on the aura result before canAccessValue confirms it's safe.
function CS.Detection.EvaluateState(options)
    options = options or {}

    local shouldAurasBeSecret = options.shouldAurasBeSecret
        or (C_Secrets and C_Secrets.ShouldAurasBeSecret)
    local getPlayerAuraBySpellID = options.getPlayerAuraBySpellID
        or (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID)
    local canAccessValue = options.canAccessValue or canaccessvalue
    local spellId = options.spellId or CS.Detection.CAMPFIRE_SPELL_ID

    if shouldAurasBeSecret and shouldAurasBeSecret() then
        return false
    end

    if not getPlayerAuraBySpellID then
        return false
    end

    local aura = getPlayerAuraBySpellID(spellId)

    if canAccessValue and not canAccessValue(aura) then
        return false
    end

    return aura ~= nil
end

function CS.Detection.Refresh(options)
    setState(CS.Detection.EvaluateState(options))
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
