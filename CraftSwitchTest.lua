-- TEMPORARY: in-client smoke test only, isolating whether
-- C_TradeSkillUI.OpenRecipe alone (no CastSpellByName, no
-- OpenTradeSkill mixed in) sets the "active profession" for a
-- subsequent CraftRecipe call, when invoked from a real secure
-- button's click handler instead of /run. Remove this file (and its
-- CampfireStokers.toc entry) once that's confirmed either way - it is
-- not part of the shipped feature set and has no reason to exist in a
-- release build.

local button = CreateFrame("Button", "CampfireStokersCraftSwitchTestButton", UIParent, "SecureActionButtonTemplate")
button:SetSize(200, 32)
button:SetPoint("CENTER", UIParent, "CENTER", 0, 240)
button:RegisterForClicks("AnyUp")

local background = button:CreateTexture(nil, "BACKGROUND")
background:SetAllPoints()
background:SetColorTexture(0.1, 0.1, 0.1, 0.8)

local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
text:SetAllPoints()
text:SetJustifyH("CENTER")
text:SetText("CS Craft Switch Test\n1230161")

local recipeSpellId = 1230161

-- Reverted back to the exact synchronous form that last succeeded
-- (no C_Timer.After) - every version since introducing a delay has
-- failed, including a clean self-match (Blacksmithing last displayed,
-- targeting Blacksmithing itself), which rules out profession/recipe
-- mismatch as the cause. C_Timer.After callbacks run detached from the
-- click's hardware-event context that scheduled them - if CraftRecipe
-- (or the profession-switch it depends on) needs that context, any
-- delay at all would silently break it regardless of what's selected.
button:SetScript("PreClick", function()
    print("CampfireStokers CraftSwitchTest: calling OpenRecipe(" .. recipeSpellId .. ")...")
    C_TradeSkillUI.OpenRecipe(recipeSpellId)
    print("CampfireStokers CraftSwitchTest: calling CraftRecipe(" .. recipeSpellId .. ")...")
    C_TradeSkillUI.CraftRecipe(recipeSpellId)
    if ProfessionsFrame then
        ProfessionsFrame:Hide()
    end
    print("CampfireStokers CraftSwitchTest: sequence complete - watch for a cast bar/animation.")
end)

SLASH_CAMPFIRESTOKERSCRAFTSWITCHTEST1 = "/cscraftswitch"
SlashCmdList["CAMPFIRESTOKERSCRAFTSWITCHTEST"] = function(msg)
    local id = tonumber(msg)
    if id then
        recipeSpellId = id
    end
    text:SetText("CS Craft Switch Test\n" .. recipeSpellId)
    print("CampfireStokers CraftSwitchTest: now targeting recipe " .. recipeSpellId)
end
