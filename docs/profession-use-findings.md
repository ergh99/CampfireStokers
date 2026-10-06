# Profession good "use" click findings ledger (started 2026-10-05)

Append-only observation ledger, kept per the `observation-ledger` skill:
each round is written as soon as its result is reported, before the next
test is designed. Observed fields are verbatim quotes of the report.

## Reported problem (verbatim, 2026-10-05)

"a button click that should initiate placing a prepared campfire good does
nothing and produces no error"

## Code at ledger start (from the repo, not observed in-client)

- `UI.lua` `createProfessionButton`: `SecureActionButtonTemplate`,
  `RegisterForClicks("AnyUp")` only (changed from `"AnyUp","AnyDown"`
  after the 2026-10-04 smoke test double-fired `PreClick` - see
  docs/tasks.md; whether item use was re-tested after that change is not
  recorded).
- `applyProfessionButtonState`, use state: `SetAttribute("type", "item")`,
  `SetAttribute("item", result.itemName)`, where `itemName` is
  `entry.itemName` - the add-on's own `Data.lua` string (e.g.
  `"Lodestone"`), not a name read from the client. `PreClick` does
  nothing in this state.
- Hypotheses to test (not observed): (1) the `item` attribute doesn't
  match the real item name; (2) with only `"AnyUp"` registered, the
  secure handler ignores the click depending on the
  `ActionButtonUseKeyDown` CVar.

## Rounds

### Round 1 setup check: which button is in the use (green) state
Action taken (verbatim): at the campfire, panel open, check whether the
  Mining button shows the green (use) glow.
Observed result (verbatim): "the blacksmithing button is green, mining is blue"

### Round 1: read the use-state button's attributes and ActionButtonUseKeyDown
Starting state: at the campfire, panel open, Blacksmithing button green
  (use), not clicked.
Action taken (verbatim): `/run local b=CampfireStokersProfessionButtonblacksmithing print(b.pendingAction,b:GetAttribute("type"),b:GetAttribute("item"),GetCVar("ActionButtonUseKeyDown"),(C_Item.GetItemInfo(279944)))`
Observed result (verbatim): "use item Sharpening Wheel 1 Sharpening Wheel"
Interpretation (not observed - reasoning only): state `use`, `type` =
  `item`, `item` = `Sharpening Wheel`, `ActionButtonUseKeyDown` = `1`,
  and the client's own name for 279944 is `Sharpening Wheel` - the same
  string as the attribute. That makes hypothesis (1), a name mismatch,
  unlikely. Hypothesis (2) is still open: the key-down setting is on
  while the button only registers `"AnyUp"`.

### Round 2: also register "AnyDown" on the use-state button
Starting state: at the campfire, panel open, Blacksmithing button green
  (use).
Action taken (verbatim): `/run CampfireStokersProfessionButtonblacksmithing:RegisterForClicks("AnyUp","AnyDown")`,
  then click the Blacksmithing button once.
Observed result (verbatim):
  - "the button click began the cast to place the Sharpening Wheel as expected"
  - "no error text"
  - "the button turned blue when the cast completed (and the object appeared at the character's feet)"
User correction given with this report (verbatim; user's game knowledge): "only the campfire kit produces a ground target reticule when "cast"; the other campfire goods simply start a cast that places the item at the characters feet on completiong."
Interpretation (not observed - reasoning only): Round 1's attributes
  were unchanged; the only difference from the failing click is the
  added "AnyDown" registration. Consistent with hypothesis (2): with
  `ActionButtonUseKeyDown` = 1 the secure item use happens on the press,
  which an "AnyUp"-only button never receives. Turning blue afterwards
  is the normal refresh moving from use to craft once the item left
  the bags.

### Round 3: all three states with the fix (both clicks registered, PreClick ignores the press)
Starting state: `/reload` with the updated `UI.lua`; at the campfire.
User note given with this report (verbatim): "placing a campfire object incurs a 1 hr cooldown, so tests will now be conducted with leatherworking and skinning"
Action taken (verbatim): 1. click a green (use) button once; 2. click a
  blue (craft) button twice; 3. click a red-orange (request) button once.
Observed result (verbatim):
  - 1: "yes"
  - 2: "yes"
  - 3: "yes but the 255 character limit seems to be enforced incorrectly.  item links should not be counted for their full length."
  - Further detail (verbatim): "specifically the fishing and first aid yells were blocked for a character that had none of the materials"
  The 255-character question continues in `docs/yell-length-findings.md`.
