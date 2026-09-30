local CS = select(2, ...)

CS.Data = CS.Data or {}

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
