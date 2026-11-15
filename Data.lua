local CS = select(2, ...)

---@class CampfireStokersData
CS.Data = CS.Data or {}

-- Addon-wide debug flag: shared through the CS table rather than as a
-- real Lua global, which AGENTS.md's no-globals rule forbids. Set it to
-- true locally while developing; it must be false in every commit (see
-- AGENTS.md, "Debug flag"), and tests/data_spec.lua fails if it isn't.
-- Data.lua loads first in the TOC, so every other module can use it.
CS.DEBUG = false

-- Prints only while CS.DEBUG is true.
function CS.Debug(message)
    if CS.DEBUG then
        print("Campfire Stokers [debug]: " .. tostring(message))
    end
end

-- Bumped by Tree.lua's migration whenever a default category or phrase is
-- added to DefaultTree below, so existing SavedVariables trees can pick up
-- the addition without touching a player's own edits.
CS.Data.SCHEMA_VERSION = 1

-- Every player-visible string, keyed by the id of the node (or UI element)
-- it belongs to. Only enUS ships in v1; a future locale is added by
-- introducing another table like this one and selecting between them
-- (e.g. by GetLocale()) at the single point below where DefaultTree reads
-- from L, not by touching DefaultTree's shape.
local L = {
    cat_icebreakers = "Icebreakers",
    cat_trading = "Trading",
    cat_professions = "Professions",
    cat_infoadvice = "Info & Advice",
    cat_emotes = "Emotes",

    -- \226\128\153 is U+2019 (right single quotation mark), written as a
    -- decimal byte escape so the source stays plain ASCII.
    icebreakers_loot = "What\226\128\153s the best thing you looted today?",
    icebreakers_place = "What has been your favorite place in this zone?",
    icebreakers_hope = "What are you hoping to experience while you\226\128\153re in this area?",

    trading_spare = "Got anything taking up space you want to trade?",

    professions_skillup = "What are you making to skill up your professions?",

    info_group = "Looking to group for the next 10 mins to knock out a quest or explore?",
    info_ziptips = "What tips should everyone know about this zone?",

    emotes_salute = "/salute",
    emotes_warmfire = "/e warms their weary bones by the fire.",

    ui_say = "Say",
    ui_yell = "Yell",
    ui_selftest_title = "Campfire Stokers Self-Test",
    ui_panel_title = "Campfire Stokers",
    ui_needs_target_tooltip = "Requires a target to send.",

    ui_options_title = "Campfire Stokers",
    ui_add_category = "Add Category",
    ui_add_phrase = "Add Phrase",
    ui_rename = "Rename",
    ui_edit = "Edit",
    ui_delete = "Delete",
    ui_reset_defaults = "Reset to Defaults",
    ui_restore_defaults = "Restore Missing Defaults",
    ui_reset_confirm = "Reset the phrase tree? Confirm replaces everything, including your own categories and phrases. Restore Missing Defaults only adds back anything you've deleted, without touching your other edits.",
    ui_delete_category_confirm = "Delete the category \"%s\" and all its phrases? This can't be undone.",
    ui_new_category_prompt = "New category name:",
    ui_new_phrase_prompt = "New phrase text:",
    ui_rename_category_prompt = "Rename category:",
    ui_edit_phrase_prompt = "Edit phrase text:",
    ui_accept = "Accept",
    ui_confirm = "Confirm",
    ui_cancel = "Cancel",
    ui_error_empty = "This can't be empty.",
    ui_panel_style = "Panel style:",
    style_campfire = "Campfire",
    style_forever = "Forever",

    -- Campfire features (tier 1 only - see docs/definition.md's
    -- Future Scope section). One per profession except Cooking, which
    -- creates the initial campfire rather than extending one.
    feature_fishbowl = "Fish Bowl",
    feature_manawell = "Mana Well",
    feature_incensecandle = "Incense Candle",
    feature_firstaidkit = "First Aid Kit",
    feature_enchantedlute = "Enchanted Lute",
    feature_camptent = "Camp Tent",
    feature_reagentbot = "Reagent Bot",
    feature_sharpeningwheel = "Sharpening Wheel",
    feature_factionbanner = "Faction Banner",
    feature_lodestone = "Lodestone",
    feature_campchair = "Camp Chair",
    feature_status_use = "Can place",
    feature_status_craft = "Can craft",
    feature_status_request = "Missing materials - click to yell a request",
    feature_status_cooldown = "On cooldown",
    feature_request_not_ready = "still loading item data for this request - try again in a moment.",
}

CS.Data.L = L

-- The bootstrapped starter tree. Tree.lua deep-copies this into
-- CampfireStokersDB on first load and never mutates it afterwards, so
-- "reset to defaults" can always fall back to a clean copy. Categories sit
-- directly under the root; a category's children are always phrases.
CS.Data.DefaultTree = {
    {
        id = "cat_icebreakers",
        type = "category",
        name = L.cat_icebreakers,
        children = {
            { id = "icebreakers_loot", type = "phrase", text = L.icebreakers_loot },
            { id = "icebreakers_place", type = "phrase", text = L.icebreakers_place },
            { id = "icebreakers_hope", type = "phrase", text = L.icebreakers_hope },
        },
    },
    {
        id = "cat_trading",
        type = "category",
        name = L.cat_trading,
        children = {
            { id = "trading_spare", type = "phrase", text = L.trading_spare },
        },
    },
    {
        id = "cat_professions",
        type = "category",
        name = L.cat_professions,
        children = {
            { id = "professions_skillup", type = "phrase", text = L.professions_skillup },
        },
    },
    {
        id = "cat_infoadvice",
        type = "category",
        name = L.cat_infoadvice,
        children = {
            { id = "info_group", type = "phrase", text = L.info_group },
            { id = "info_ziptips", type = "phrase", text = L.info_ziptips },
        },
    },
    {
        id = "cat_emotes",
        type = "category",
        name = L.cat_emotes,
        children = {
            { id = "emotes_salute", type = "phrase", text = L.emotes_salute },
            { id = "emotes_warmfire", type = "phrase", text = L.emotes_warmfire },
        },
    },
}
