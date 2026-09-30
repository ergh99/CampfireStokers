local loadModule = require("support.load_module")

local tests = {}

-- Confirmed real data 2026-09-30 (see docs/decision-log.md): this is how
-- Forever actually registers the built-in /salute emote - EMOTE<id>_CMD<n>,
-- not the classic SLASH_<TOKEN><N> convention.
local FAKE_EMOTE_GLOBALS = {
    EMOTE79_CMD1 = "/salute",
    EMOTE79_CMD2 = "/salute",
}

-- The classic retail convention. Confirmed NOT how Forever registers real
-- emotes, but SLASH_STOPATTACK1 (a non-emote command) does still exist in
-- this form on this build, so FindEmoteToken keeps supporting it too.
local FAKE_CLASSIC_EMOTE_GLOBALS = {
    SLASH_BOW1 = "/bow",
}

local function loadSend()
    local CS = {}
    loadModule("Send.lua", "CampfireStokers", CS)
    return CS
end

-- Classify: plain text

tests["Classify sends plain text on SAY by default"] = function()
    local CS = loadSend()
    local action = CS.Send.Classify("hello there")
    assert(action.kind == "chat")
    assert(action.channel == "SAY")
    assert(action.text == "hello there")
end

tests["Classify sends plain text on YELL when the panel toggle says so"] = function()
    local CS = loadSend()
    local action = CS.Send.Classify("hello there", { sendMode = "YELL" })
    assert(action.kind == "chat" and action.channel == "YELL")
end

tests["Classify rejects empty text"] = function()
    local CS = loadSend()
    local action = CS.Send.Classify("")
    assert(action.kind == "rejected")
end

tests["Classify rejects text over 255 characters"] = function()
    local CS = loadSend()
    local action = CS.Send.Classify(string.rep("x", 256))
    assert(action.kind == "rejected")
end

-- Classify: /s, /say, /y, /yell, /e, /emote, case and spacing

tests["/s and /say send on SAY, case-insensitively"] = function()
    local CS = loadSend()
    for _, cmd in ipairs({ "/s", "/S", "/say", "/SAY", "/Say" }) do
        local action = CS.Send.Classify(cmd .. " hi there")
        assert(action.kind == "chat" and action.channel == "SAY" and action.text == "hi there",
            "failed for " .. cmd)
    end
end

tests["/y and /yell send on YELL"] = function()
    local CS = loadSend()
    for _, cmd in ipairs({ "/y", "/yell", "/YELL" }) do
        local action = CS.Send.Classify(cmd .. " hi there")
        assert(action.kind == "chat" and action.channel == "YELL" and action.text == "hi there",
            "failed for " .. cmd)
    end
end

tests["/e and /emote send as a custom EMOTE chat message"] = function()
    local CS = loadSend()
    for _, cmd in ipairs({ "/e", "/emote" }) do
        local action = CS.Send.Classify(cmd .. " warms their weary bones by the fire.")
        assert(action.kind == "chat" and action.channel == "EMOTE")
        assert(action.text == "warms their weary bones by the fire.")
    end
end

tests["a recognized command with nothing after it is rejected, not sent"] = function()
    local CS = loadSend()
    for _, cmd in ipairs({ "/s", "/say", "/y", "/yell", "/e", "/emote" }) do
        local action = CS.Send.Classify(cmd)
        assert(action.kind == "rejected", "expected rejection for bare " .. cmd)
    end
end

-- Classify: built-in emote commands via scanned globals

tests["a built-in emote command performs that emote, found by scanning emote globals"] = function()
    local CS = loadSend()
    local action = CS.Send.Classify("/salute", { emoteGlobals = FAKE_EMOTE_GLOBALS })
    assert(action.kind == "emote")
    assert(action.emoteToken == "SALUTE")
end

tests["a built-in emote command matches case-insensitively"] = function()
    local CS = loadSend()
    local action = CS.Send.Classify("/SALUTE", { emoteGlobals = FAKE_EMOTE_GLOBALS })
    assert(action.kind == "emote" and action.emoteToken == "SALUTE")
end

tests["a built-in emote command ignores any text after it"] = function()
    local CS = loadSend()
    local action = CS.Send.Classify("/salute for the win", { emoteGlobals = FAKE_EMOTE_GLOBALS })
    assert(action.kind == "emote" and action.emoteToken == "SALUTE")
end

tests["falls back to the classic SLASH_<TOKEN><N> pattern too"] = function()
    local CS = loadSend()
    local action = CS.Send.Classify("/bow", { emoteGlobals = FAKE_CLASSIC_EMOTE_GLOBALS })
    assert(action.kind == "emote")
    assert(action.emoteToken == "BOW")
end

tests["a restricted built-in emote is rejected"] = function()
    local CS = loadSend()
    local action = CS.Send.Classify("/salute", {
        emoteGlobals = FAKE_EMOTE_GLOBALS,
        isEmoteRestricted = function(token)
            return token == "SALUTE"
        end,
    })
    assert(action.kind == "rejected")
end

-- Classify: unrecognized commands

tests["an unrecognized slash command is rejected"] = function()
    local CS = loadSend()
    local action = CS.Send.Classify("/dance", { emoteGlobals = FAKE_EMOTE_GLOBALS })
    assert(action.kind == "rejected")
end

-- ContainsTargetToken

tests["ContainsTargetToken reports whether %t is present"] = function()
    local CS = loadSend()
    assert(CS.Send.ContainsTargetToken("Hello %t!") == true)
    assert(CS.Send.ContainsTargetToken("Hello there!") == false)
end

-- Send: actually dispatches through mocked SendChatMessage / DoEmote

tests["Send calls SendChatMessage for plain text"] = function()
    local CS = loadSend()
    local calls = {}
    SendChatMessage = function(msg, channel)
        table.insert(calls, { msg = msg, channel = channel })
    end

    CS.Send.Send("hello there", { sendMode = "SAY" })

    assert(#calls == 1)
    assert(calls[1].msg == "hello there" and calls[1].channel == "SAY")
end

tests["Send calls DoEmote for a built-in emote command"] = function()
    local CS = loadSend()
    local calls = {}
    DoEmote = function(token)
        table.insert(calls, token)
    end

    CS.Send.Send("/salute", { emoteGlobals = FAKE_EMOTE_GLOBALS })

    assert(#calls == 1 and calls[1] == "SALUTE")
end

tests["Send reports the reason instead of sending when rejected"] = function()
    local CS = loadSend()
    local reported = {}

    CS.Send.Send("/dance", {
        emoteGlobals = FAKE_EMOTE_GLOBALS,
        report = function(message)
            table.insert(reported, message)
        end,
    })

    assert(#reported == 1)
    assert(reported[1]:find("dance", 1, true) ~= nil)
end

return tests
