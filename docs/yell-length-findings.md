# Yell length and item links findings ledger (started 2026-10-05)

Append-only observation ledger, kept per the `observation-ledger` skill:
each round is written as soon as its result is reported, before the next
test is designed. Observed fields are verbatim quotes of the report.

## Reported problem (verbatim, 2026-10-05)

From Round 3 of `docs/profession-use-findings.md`: "yes but the 255
character limit seems to be enforced incorrectly.  item links should not
be counted for their full length." ... "specifically the fishing and first
aid yells were blocked for a character that had none of the materials"

The user's request: "begin a findings phase for how item links should be
treated with regards to the 255 character limit".

## Code at ledger start (from the repo, not observed in-client)

- `Send.lua` `Classify`: rejects any text where `#text > 255`
  (`PHRASE_TEXT_LIMIT`), with the reason "Phrase text is longer than 255
  characters." `#text` is the raw byte length, so each item link counts
  at its full escape-code length (`|cff...|Hitem:...|h[Name]|h|r`), not
  its visible `[Name]` length.
- `Professions.lua` `BuildRequestMessage`: puts the main item and each
  missing reagent in the message as links when available; the request
  button sends it through `CS.Send.Send(..., { sendMode = "YELL" })`.
- Open question (not observed): what limit the client/server actually
  applies to a chat message containing links - raw bytes, visible
  characters, or something else.

## Rounds

### Round 1: measure one link; send a SAY of five links over 255 raw bytes
Action taken (verbatim):
  1. `/run local _,l=C_Item.GetItemInfo(279967) print(#l, #"[Fish Bowl]") print((l:gsub("|","||")))`
  2. `/run local _,a=C_Item.GetItemInfo(279967) local _,b=C_Item.GetItemInfo(279968) local m=a.." "..b.." "..a.." "..b.." "..a print(#m) SendChatMessage(m,"SAY")`
Observed result (verbatim):
  - Step 1: "61 11" / "[Fish Bowl]" / "(brackets indicate a clickable link in chat)"
  - Step 2: "317" / "all five links appeared in chat when the message was sent"
  - Errors: "no error text"
Interpretation (not observed - reasoning only): the Fish Bowl link is
  61 raw bytes for 11 visible characters. A 317-byte message (five
  links) went through `SendChatMessage` intact on SAY, so the game does
  not reject raw length over 255 when the excess is link codes. The
  escaped print in step 1 still rendered as a link, so the raw codes
  weren't shown.

### Round 2: SAY of ten links, about 620 raw bytes
Action taken (verbatim): `/run local _,a=C_Item.GetItemInfo(279967) local t={} for i=1,10 do t[i]=a end local m=table.concat(t," ") print(#m) SendChatMessage(m,"SAY")`
Observed result (verbatim):
  - "619"
  - "10 links appeared in chat"
  - "no error text"

### Round 3: SAY of 260 plain characters, no links
Action taken (verbatim): `/run local m=("abcdefghi "):rep(26) print(#m) SendChatMessage(m,"SAY")`
Observed result (verbatim):
  - "260"
  - "the message did not appear"
  - error text: "1x SendChatMessage(): Chat message limits exceeded"
Interpretation (not observed - reasoning only): plain text over 255
  characters is refused, and `SendChatMessage` raises a Lua error rather
  than failing silently. Together with Rounds 1-2 (317 and 619 raw bytes
  of links accepted), the limit is not on raw bytes; how link text is
  counted against it is still open.

### Round 4: SAY of 250 plain characters plus one Fish Bowl link
Action taken (verbatim): `/run local _,a=C_Item.GetItemInfo(279967) local m=("abcdefghi "):rep(25)..a print(#m) SendChatMessage(m,"SAY")`
Observed result (verbatim): "311 no message appeared, same error text"
Interpretation (not observed - reasoning only): the link counts for
  something - if links counted as zero this would be 250 and pass. Its
  visible `[Fish Bowl]` (11) would make 261, over the limit, which fits;
  the exact per-link count is still open.

### Round 5: boundary - 244, 245 and 247 plain characters plus one Fish Bowl link
Action taken (verbatim):
  - A: `/run local _,a=C_Item.GetItemInfo(279967) local m=("abcdefghi "):rep(24).."abcd"..a print(#m) SendChatMessage(m,"SAY")`
  - B: `/run local _,a=C_Item.GetItemInfo(279967) local m=("abcdefghi "):rep(24).."abcde"..a print(#m) SendChatMessage(m,"SAY")`
  - C: `/run local _,a=C_Item.GetItemInfo(279967) local m=("abcdefghi "):rep(24).."abcdefg"..a print(#m) SendChatMessage(m,"SAY")`
Observed result (verbatim):
  - "A. 305, message printed, ending in [Fish Bowl]"
  - "B. 306, no message printed, same error text"
  - "C. 308, no message printed, same error text"
Interpretation (not observed - reasoning only): A is 244 + 11 = 255
  counting the link as its visible `[Fish Bowl]` with brackets, and
  passed; B is 256 on that count and failed. Without the brackets B
  would be 254 and should have passed, so the brackets count.

### Round 6: real request yell after the fix (VisibleLength in Send.Classify)
Starting state: updated `Send.lua`; character with none of the
  Fishing/First Aid materials.
Action taken (verbatim): click the Fishing or First Aid request button.
Observed result (verbatim): "confirmed working"
Interpretation (not observed - reasoning only): which of the two
  buttons was clicked was not stated; this is the first YELL-channel
  confirmation of the visible-length rule.

## Findings summary (every claim traces to a round above)

- The game's limit is 255 **visible** characters, where an item link
  counts as its visible text including the brackets (`[Fish Bowl]` = 11):
  255 passed and 256 failed (Round 5 A/B), and 250 plain + one link
  failed (Round 4).
- Raw byte length is not the limit: 317 and 619 raw bytes made of links
  were sent intact (Rounds 1-2). No raw upper limit was found; none was
  tested beyond 619 bytes.
- Over the limit, `SendChatMessage` raises a Lua error, "Chat message
  limits exceeded", and nothing is sent (Rounds 3-5).
- Rounds 1-5 were on SAY; after the fix, a real request yell went
  through (Round 6, "confirmed working").
- Only item links were tested; other link types were not.
