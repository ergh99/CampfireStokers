# Craft profession-switch findings ledger (started 2026-10-05)

Append-only observation ledger for the in-client investigation of
`C_TradeSkillUI.CraftRecipe` behavior behind the one-click campfire-goods
craft feature. Kept per the `observation-ledger` skill: each round is
written as soon as its result is reported, before the next test is
designed. Observed fields are verbatim quotes of the report.

This ledger starts from zero. It does not inherit any finding from
`docs/craft-profession-switch-investigation.md`; that file was used only
as a list of API names to probe.

## Test environment at ledger start (from the repo, not observed in-client)

- TOC load order: `CraftSwitchTest.lua`, `Data.lua`, `Tree.lua`,
  `Send.lua`, `Detection.lua`, `Professions.lua`, `UI.lua`,
  `Launcher.lua`, `Options.lua`, `Core.lua`. The temporary test file and
  `Professions.lua` are both loaded unless a round says otherwise.
- APIs in scope: `C_TradeSkillUI.CraftRecipe`, `.OpenRecipe`,
  `.OpenTradeSkill`, `.GetRecipeInfo`, `.GetRecipeSchematic`;
  `ProfessionsFrame` (`:IsShown()`, `:Hide()`); Blizzard's Create button;
  `CastSpellByName`; `C_Item.UseItemByName`; `SecureActionButtonTemplate`
  / `PreClick`; `C_Timer.After`; events `BAG_UPDATE_DELAYED`,
  `ADDON_LOADED`. Recipe spell IDs `1230161`, `1230171`.

## Rounds

### Round 1: control - manual craft through Blizzard's own UI, no add-on calls
Action taken (verbatim): Open the profession that owns recipe `1230161`
  by hand, select that recipe, click Blizzard's Create button. No `/run`
  commands, no Campfire Stokers buttons.
Observed result (verbatim):
  - Location: "executed twice, once away from the campfire and once at campfire with Welcoming Campfire aura"
  - Panel open beforehand: "none"
  - Outcome: "an animation and cast bar began, upon completion materials were consumed and a new item was added to the character's inventory.  there was no error text."
  - Recipe name shown: "Lodestone"
User clarification after Round 1 (verbatim): "Lodestone is a recipe in the Mining profession"

### Round 2: bare CraftRecipe from /run, no panel open
Starting state: away from the campfire; `/reload` done first; no
  profession panel open. Last panel opened by hand before this round was
  Mining (Round 1).
Action taken (verbatim): `/run C_TradeSkillUI.CraftRecipe(1230161)`,
  then watch about 5 seconds.
Observed result (verbatim):
  - Outcome: "nothing happened"
  - Anything else done between `/reload` and the `/run`: "no actions taken"

### Round 3: bare CraftRecipe from /run, matching panel opened by hand
Starting state: away from the campfire. Last panel opened by hand before
  this round was Mining (Round 1).
Action taken (verbatim): `/reload`; open Mining by hand and select
  Lodestone (no Create click); with the panel open, `/run
  C_TradeSkillUI.CraftRecipe(1230161)`; watch about 5 seconds.
Observed result (verbatim):
  - Step 1: "executed /reload"
  - Step 2: "done"
  - Step 3: "a craft operation was performed (animation, cast bar, produced item was added to inventory)"
  - Step 4: "result was immediate"
  - Panel state: "panel remained open from when it was manually opened through the crafting operation and beyond (still open)"
  - Reload: "a `/reload` was performed as part of 1"

### Round 4: OpenRecipe alone, no craft
Starting state: away from the campfire; `/reload`; no profession panel
  open. Last panel opened by hand before this round was Mining (Round 3).
Action taken (verbatim): `/run C_TradeSkillUI.OpenRecipe(1230161) print("shown:", ProfessionsFrame and ProfessionsFrame:IsShown())`
Observed result (verbatim):
  - Panel: "panel opened to Mining with Lodestone selected"
  - Chat: "shown: true" "was printed"

### Round 5: OpenRecipe then CraftRecipe in one /run, panel left open
Starting state: away from the campfire; `/reload`; no profession panel
  open. Last panel opened by hand before this round was Mining (Round 3).
Action taken (verbatim): `/run C_TradeSkillUI.OpenRecipe(1230161) C_TradeSkillUI.CraftRecipe(1230161)`,
  then watch about 5 seconds without touching the panel.
Observed result (verbatim):
  - Outcome: "panel opened and crafting operation began, no error text"
  - Panel afterwards: "panel remained open"

### Round 6: OpenRecipe, CraftRecipe, Hide in one /run
Starting state: away from the campfire; `/reload`; no profession panel
  open. Last panel opened by hand before this round was Mining (Round 3).
Action taken (verbatim): `/run C_TradeSkillUI.OpenRecipe(1230161) C_TradeSkillUI.CraftRecipe(1230161) ProfessionsFrame:Hide()`,
  then watch about 5 seconds.
Observed result (verbatim):
  - Panel seen: "did not see panel"
  - Cast: "crafting operation executed fully"
  - Item: "item was created"
  - Errors: "no error text"

### Round 7: Round 6 command after opening a different profession by hand
Starting state: away from the campfire; `/reload`.
Action taken (verbatim): open a different profession by hand, look,
  close it; with all panels closed, `/run C_TradeSkillUI.OpenRecipe(1230161) C_TradeSkillUI.CraftRecipe(1230161) ProfessionsFrame:Hide()`;
  watch about 5 seconds.
Observed result (verbatim):
  - Step 2: "i opened blacksmithing then closed it"
  - Panel during step 3: "no panel appeared when running the command"
  - Cast: "no cast started"
  - Errors: "no error text"

### Round 8: OpenRecipe alone, after opening a different profession by hand
Starting state: away from the campfire; `/reload`; Blacksmithing opened
  by hand, looked at, closed.
Action taken (verbatim): `/run C_TradeSkillUI.OpenRecipe(1230161) print("shown:", ProfessionsFrame and ProfessionsFrame:IsShown())`
Observed result (verbatim):
  - Panel: "the mining panel opened with Lodestone selected"
  - Chat: "shown: true" "was printed"

### Round 9: OpenRecipe then CraftRecipe in one /run, no Hide, after opening a different profession by hand
Starting state: away from the campfire; `/reload`; Blacksmithing opened
  by hand, looked at, closed.
Action taken (verbatim): `/run C_TradeSkillUI.OpenRecipe(1230161) C_TradeSkillUI.CraftRecipe(1230161)`,
  then watch about 5 seconds without touching the panel.
Observed result (verbatim):
  - Panel: "panel opened to Mining, Lodestone selected"
  - Cast: "no cast started nor any other crafting"
  - Errors: "no error"

### Round 10: OpenRecipe and CraftRecipe as two separate /run commands, after opening a different profession by hand
Starting state: away from the campfire; `/reload`; Blacksmithing opened
  by hand, looked at, closed.
Action taken (verbatim): `/run C_TradeSkillUI.OpenRecipe(1230161)`;
  check the panel without clicking in it; then `/run C_TradeSkillUI.CraftRecipe(1230161)`;
  watch about 5 seconds.
Observed result (verbatim):
  - Panel after step 3: "panel opened to Mining => Lodestone"
  - Time between steps 3 and 5: "enough time to tab back to VS Code, copy the command, tab back to game client, paste and hit Enter"
  - Outcome after step 5: "a crafting operation was performed as normal (animation, cast bar, materials consumed, item produced)"
  - Errors: "no error text"
User note covering all rounds so far (verbatim): "whenever a crafting operation has started during testing, there was has never been any visible delay.  it began as soon as Enter was pressed."

### Round 11: one /run, CraftRecipe deferred one frame with C_Timer.After(0), after opening a different profession by hand
Starting state: away from the campfire; `/reload`; Blacksmithing opened
  by hand, looked at, closed.
Action taken (verbatim): `/run C_TradeSkillUI.OpenRecipe(1230161) C_Timer.After(0, function() C_TradeSkillUI.CraftRecipe(1230161) end)`,
  then watch without touching the panel.
Observed result (verbatim):
  - Panel: "the panel appeared, MIning => Lodestone, as expected"
  - Cast: "a cast did not start despite an extended observation window (15 seconds or so, just to be sure)"
  - Errors: "no error text"
User comment (verbatim; user's reasoning, not an in-client observation from this ledger): "this is expected as calls wrapped in a C_Timer.After do not have the same hardware action context"

### Round 12: CraftRecipe deferred with C_Timer.After(0), matching panel opened by hand
Starting state: away from the campfire; `/reload`; Mining opened by hand
  with Lodestone selected (no Create click), panel left open.
Action taken (verbatim): `/run C_Timer.After(0, function() C_TradeSkillUI.CraftRecipe(1230161) end)`,
  then watch about 15 seconds.
Observed result (verbatim): "no crafting operation was performed (no cast, no error)"
Interpretation (not observed - reasoning only): Round 3 had the same
  setup with a direct `/run` call and crafted; the only change here is
  the timer. Consistent with `CraftRecipe` needing to run inside the
  keypress/click's own execution, not a later callback.

### Round 13: OpenRecipe + Hide in one /run, CraftRecipe in a later /run, after opening a different profession by hand
Starting state: away from the campfire; `/reload`; Blacksmithing opened
  by hand, looked at, closed.
Action taken (verbatim): `/run C_TradeSkillUI.OpenRecipe(1230161) ProfessionsFrame:Hide()`;
  check no panel is showing; then `/run C_TradeSkillUI.CraftRecipe(1230161)`;
  watch about 5 seconds.
Observed result (verbatim): "no observable results (success or failure) from either command"
Interpretation (not observed - reasoning only): compared with Round 10
  (same two-command sequence, panel left open between them, crafted),
  the only change is hiding the panel in the first command. Consistent
  with the panel needing to still be shown when the separate craft
  command runs, in this state.

### Round 14: two-input design - OpenRecipe in one /run, CraftRecipe + Hide in a later /run, after opening a different profession by hand
Starting state: away from the campfire; `/reload`; Blacksmithing opened
  by hand, looked at, closed.
Action taken (verbatim): `/run C_TradeSkillUI.OpenRecipe(1230161)`;
  check the panel without clicking in it; then `/run C_TradeSkillUI.CraftRecipe(1230161) ProfessionsFrame:Hide()`;
  watch until the cast would have finished.
Observed result (verbatim):
  - Panel after step 3: "panel opened, Mining => Lodestone"
  - After step 5: "crafting operation performed as normal and panel immediately closed as it began"
  - Errors: "no error text"
User's observation standard, stated after Round 14 (verbatim; applies to all rounds): "(if a crafting operation shows a cast bar, it is safe to assume that the animation and item creation occurred as well)"

### Round 15: two-click design from the real secure test button, after opening a different profession by hand
Starting state: away from the campfire; `/reload`; Blacksmithing opened
  by hand, looked at, closed. `CraftSwitchTest.lua` PreClick changed to:
  if `ProfessionsFrame` not shown -> `OpenRecipe(id)` only; else
  `CraftRecipe(id)` then `ProfessionsFrame:Hide()`. Target 1230161.
Action taken (verbatim): click "CS Craft Switch Test" once; check the
  panel without clicking in it; click the test button a second time.
Observed result (verbatim):
  - After click 1: "panel opened, Mining => Lodestone"
  - After click 2: "crafting cast began with 2nd click"
  - Chat: "chat print (abridged)" "click 1 - calling OpenRecipe" "click 2 - calling CraftRecipe then hiding"
  - Errors: "no error text"
  - Whether the panel closed after click 2: not reported.
User clarification after Round 15 (verbatim): "the panel did close as expected"

### Round 16: Round 15 at the campfire
Starting state (as proposed): `/reload`; at a campfire with Welcoming
  Campfire aura and Campfire Stokers' panel showing; Blacksmithing opened
  by hand, looked at, closed. Test button PreClick unchanged from Round 15.
Action taken (verbatim): click "CS Craft Switch Test" once; check the
  panel without clicking in it; click the test button a second time.
Observed result (verbatim):
  - Campfire Stokers' panel: "the addon window popped up upon running `/sit` while near the campfire"
  - After click 1: "click 1 caused the Mining => Lodestone panel"
  - After click 2: "click 2 caused a cast bar to initiate (appear and start depleting) and the profession panel to disappear"
  - Errors: "no error text"
  - Blacksmithing-opened-by-hand step and Welcoming Campfire aura: not explicitly reported this round.

### Round 17: two-click CS.Professions.Craft from the add-on panel's real profession-good button
Starting state: `CS.Professions.Craft` changed to the two-click form
  (first click OpenRecipe only; second click, if Craft opened that same
  recipe and ProfessionsFrame is still shown, CraftRecipe then hide).
  Proposed: Blacksmithing opened by hand and closed first, at the
  campfire, click Lodestone's craft button twice.
Action taken (verbatim): click the add-on panel's craft button twice.
Observed result (verbatim):
  - Outcome: "the addon panel 2 click approach worked as expected, opening the panel, crafting and hiding the panel across 2 clicks."
  - Separate behavior seen during this round: "in order to not spend the characters materials, the craft cast initiated by the test was interrupted by moving the character. this causes the campfire aura to be removed.  the panel changes based on this trigger by hiding the crafting buttons.  the panel itself and the rest of the UI elements remain visible until the delayed closer timer completes."
  - User's desired behavior (verbatim): "the profession buttons should remain visible." (Logged in docs/tasks.md for later; not addressed now.)
  - Blacksmithing-opened-by-hand step: not explicitly reported this round.
