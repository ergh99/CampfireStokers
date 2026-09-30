local CS = select(2, ...)

CS.Send = CS.Send or {}

local PHRASE_TEXT_LIMIT = 255

local SAY_COMMANDS = { ["/s"] = true, ["/say"] = true }
local YELL_COMMANDS = { ["/y"] = true, ["/yell"] = true }
local EMOTE_COMMANDS = { ["/e"] = true, ["/emote"] = true }

-- Confirmed in-client 2026-09-30 (see docs/decision-log.md): Forever
-- registers built-in emotes as EMOTE<id>_CMD<n> globals (e.g.
-- EMOTE79_CMD1 = "/salute"), keyed by a numeric emote id with no token
-- name in sight - not the classic retail SLASH_<TOKEN><N> convention this
-- originally assumed. DoEmote, however, still takes the classic uppercase
-- name string (DoEmote("SALUTE") performs the emote; DoEmote(79) silently
-- does nothing), and that name has always just been the command word
-- itself uppercased. So the fix isn't to extract a token from the
-- registration key - there isn't one to extract - it's to derive it from
-- `command`, and use the global scan only to confirm `command` really is
-- a registered emote (not to source the token). Both naming conventions
-- are checked, since the classic one hasn't been proven entirely absent
-- (SLASH_STOPATTACK1 exists on this build, just not for actual emotes).
local EMOTE_GLOBAL_PATTERNS = {
    "^EMOTE%d+_CMD%d+$",
    "^SLASH_%u+%d+$",
}

function CS.Send.FindEmoteToken(command, emoteGlobals)
    emoteGlobals = emoteGlobals or _G
    for key, value in pairs(emoteGlobals) do
        if type(key) == "string" and type(value) == "string" and value:lower() == command then
            for _, pattern in ipairs(EMOTE_GLOBAL_PATTERNS) do
                if key:match(pattern) then
                    return command:sub(2):upper()
                end
            end
        end
    end
    return nil
end

function CS.Send.ContainsTargetToken(text)
    return text:find("%%t") ~= nil
end

-- Pure: decides what sending `text` would do, without doing it. `options`:
--   sendMode        "SAY" or "YELL", the panel toggle; used when text has no
--                    leading slash command.
--   emoteGlobals     table to scan for built-in emote commands; defaults to
--                    _G. Tests pass a small fake table instead.
--   isEmoteRestricted(token) -> boolean, checked before allowing a built-in
--                    emote through; defaults to nil (nothing is restricted)
--                    until T6 confirms the client API for this.
-- Returns a table: { kind = "chat", channel, text }
--              or  { kind = "emote", emoteToken }
--              or  { kind = "rejected", reason }
function CS.Send.Classify(text, options)
    options = options or {}

    if text == "" then
        return { kind = "rejected", reason = "There's no text to send." }
    end

    if #text > PHRASE_TEXT_LIMIT then
        return { kind = "rejected", reason = "Phrase text is longer than " .. PHRASE_TEXT_LIMIT .. " characters." }
    end

    if text:sub(1, 1) ~= "/" then
        return {
            kind = "chat",
            channel = (options.sendMode == "YELL") and "YELL" or "SAY",
            text = text,
        }
    end

    local command, rest = text:match("^(%S+)%s*(.*)$")
    command = command and command:lower() or text:lower()

    if SAY_COMMANDS[command] then
        if rest == "" then
            return { kind = "rejected", reason = "Nothing to say after " .. command .. "." }
        end
        return { kind = "chat", channel = "SAY", text = rest }
    end

    if YELL_COMMANDS[command] then
        if rest == "" then
            return { kind = "rejected", reason = "Nothing to yell after " .. command .. "." }
        end
        return { kind = "chat", channel = "YELL", text = rest }
    end

    if EMOTE_COMMANDS[command] then
        if rest == "" then
            return { kind = "rejected", reason = "Nothing to emote after " .. command .. "." }
        end
        return { kind = "chat", channel = "EMOTE", text = rest }
    end

    local emoteToken = CS.Send.FindEmoteToken(command, options.emoteGlobals)
    if emoteToken then
        if options.isEmoteRestricted and options.isEmoteRestricted(emoteToken) then
            return { kind = "rejected", reason = command .. " can't be performed right now." }
        end
        return { kind = "emote", emoteToken = emoteToken }
    end

    return { kind = "rejected", reason = command .. " isn't a command this add-on can send." }
end

-- Impure: classifies `text` and actually sends it (SendChatMessage or
-- DoEmote), or reports the rejection reason through `options.report`
-- (defaults to print) if it can't be sent. Returns the same action table
-- Classify would have, so a caller can inspect what happened.
function CS.Send.Send(text, options)
    options = options or {}
    local action = CS.Send.Classify(text, options)

    if action.kind == "chat" then
        SendChatMessage(action.text, action.channel)
    elseif action.kind == "emote" then
        DoEmote(action.emoteToken)
    elseif action.kind == "rejected" then
        local report = options.report or print
        report("Campfire Stokers: " .. action.reason)
    end

    return action
end
